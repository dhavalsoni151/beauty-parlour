import '../app_database.dart';

/// All reporting/analytics done via SQL aggregation (COUNT / SUM / GROUP BY) —
/// never by loading rows into Dart. Service-level grouping keys on service_id
/// (falling back to the snapshot triple for legacy rows without an id) so two
/// services that share a name under different categories/types stay distinct.
class ReportDao {
  Map<String, dynamic> _mapTopServiceRow(Map<String, Object?> row) {
    return {
      'service_id': row['service_id'] as int?,
      'category': row['category'] as String?,
      'service_type': row['service_type'] as String?,
      'name': row['name'] as String? ?? '',
      'transactions': (row['transactions'] as num? ?? 0).toInt(),
      'visits': (row['visits'] as num? ?? 0).toInt(),
      'quantity': (row['quantity'] as num? ?? 0).toInt(),
      'revenue': (row['revenue'] as num? ?? 0).toDouble(),
      'avg_price': (row['avg_price'] as num? ?? 0).toDouble(),
    };
  }

  // ── Financial summary / P&L ───────────────────────────────────────────────

  Future<Map<String, dynamic>> getDashboardStats(
      String startDate, String endDate) async {
    final db = await AppDatabase.instance.database;

    final sales = (await db.rawQuery('''
      SELECT
        COUNT(*) AS visit_count,
        COALESCE(SUM(subtotal), 0) AS gross_sales,
        COALESCE(SUM(discount_amount), 0) AS total_discounts,
        COALESCE(SUM(final_total), 0) AS net_sales,
        COALESCE(SUM(total_paid), 0) AS collected,
        COALESCE(SUM(pending_amount), 0) AS pending
      FROM visits
      WHERE visit_date >= ? AND visit_date < ?
    ''', [startDate, endDate])).first;

    final writtenOff = (await db.rawQuery('''
      SELECT COALESCE(SUM(w.amount), 0) AS written_off
      FROM write_offs w
      JOIN visits v ON v.id = w.visit_id
      WHERE v.visit_date >= ? AND v.visit_date < ?
    ''', [startDate, endDate])).first;

    final expenses = (await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS total_expenses
      FROM expenses
      WHERE DATE(expense_date) >= DATE(?) AND DATE(expense_date) < DATE(?)
    ''', [startDate, endDate])).first;

    final newCustomers = (await db.rawQuery('''
      SELECT COUNT(*) AS count FROM customers
      WHERE created_date >= ? AND created_date < ? AND is_active = 1
    ''', [startDate, endDate])).first;

    final returningCustomers = (await db.rawQuery('''
      SELECT COUNT(DISTINCT customer_id) AS count FROM visits
      WHERE visit_date >= ? AND visit_date < ?
      AND customer_id IN (
        SELECT customer_id FROM visits WHERE visit_date < ? GROUP BY customer_id
      )
    ''', [startDate, endDate, startDate])).first;

    final grossSales = (sales['gross_sales'] as num? ?? 0).toDouble();
    final collected = (sales['collected'] as num? ?? 0).toDouble();
    final totalExpenses = (expenses['total_expenses'] as num? ?? 0).toDouble();

    return {
      'visit_count': sales['visit_count'] ?? 0,
      'gross_sales': grossSales,
      'total_discounts': (sales['total_discounts'] as num? ?? 0).toDouble(),
      'net_sales': (sales['net_sales'] as num? ?? 0).toDouble(),
      'collected': collected,
      'pending': (sales['pending'] as num? ?? 0).toDouble(),
      'written_off': (writtenOff['written_off'] as num? ?? 0).toDouble(),
      'total_expenses': totalExpenses,
      'profit': collected - totalExpenses,
      'new_customers': newCustomers['count'] ?? 0,
      'returning_customers': returningCustomers['count'] ?? 0,
    };
  }

  Future<List<Map<String, dynamic>>> getDailySalesTrend(
      String startDate, String endDate) async {
    final db = await AppDatabase.instance.database;
    return db.rawQuery('''
      SELECT DATE(visit_date) AS date,
             COALESCE(SUM(final_total), 0) AS sales,
             COUNT(*) AS visits
      FROM visits
      WHERE visit_date >= ? AND visit_date < ?
      GROUP BY DATE(visit_date)
      ORDER BY date ASC
    ''', [startDate, endDate]);
  }

  Future<List<Map<String, dynamic>>> getPaymentMethodBreakdown(
      String startDate, String endDate) async {
    final db = await AppDatabase.instance.database;
    return db.rawQuery('''
      SELECT p.payment_method, COALESCE(SUM(p.amount), 0) AS total
      FROM payments p
      JOIN visits v ON v.id = p.visit_id
      WHERE v.visit_date >= ? AND v.visit_date < ?
      GROUP BY p.payment_method
      ORDER BY total DESC
    ''', [startDate, endDate]);
  }

  // ── Category → ServiceType → Service drill-down ───────────────────────────

  static const _serviceGroupKey =
      "COALESCE(CAST(vs.service_id AS TEXT), 'x') || '|' || "
      "vs.category_name_snapshot || '|' || "
      "COALESCE(vs.service_type_name_snapshot, '') || '|' || "
      "vs.service_name_snapshot";

  String _orderCol(String sort, Map<String, String> allowed, String fallback) {
    return allowed[sort] ?? allowed[fallback]!;
  }

  /// Top categories grouped by the category name snapshot (always present),
  /// with revenue, quantity, transactions and distinct visit count.
  Future<List<Map<String, dynamic>>> getTopCategories(
    String startDate,
    String endDate, {
    String sort = 'revenue',
    int limit = 50,
  }) async {
    final db = await AppDatabase.instance.database;
    final order = _orderCol(sort, {
      'revenue': 'revenue',
      'quantity': 'quantity',
      'transactions': 'transactions',
      'visits': 'visits',
      'avg': 'avg_price',
    }, 'revenue');
    return db.rawQuery('''
      SELECT
        vs.category_name_snapshot AS name,
        MAX(vs.category_id) AS category_id,
        COUNT(*) AS transactions,
        COUNT(DISTINCT vs.visit_id) AS visits,
        COALESCE(SUM(vs.quantity), 0) AS quantity,
        COALESCE(SUM(vs.total), 0) AS revenue,
        CASE WHEN SUM(vs.quantity) > 0
             THEN SUM(vs.total) * 1.0 / SUM(vs.quantity) ELSE 0 END AS avg_price
      FROM visit_services vs
      JOIN visits v ON v.id = vs.visit_id
      WHERE v.visit_date >= ? AND v.visit_date < ?
      GROUP BY vs.category_name_snapshot
      ORDER BY $order DESC
      LIMIT $limit
    ''', [startDate, endDate]);
  }

  /// Top service types within a category (scoped by category name snapshot).
  /// Rows with no service type collapse into a single "(No Type)" bucket.
  Future<List<Map<String, dynamic>>> getTopServiceTypes(
    String startDate,
    String endDate, {
    required String categoryName,
    String sort = 'revenue',
    int limit = 50,
  }) async {
    final db = await AppDatabase.instance.database;
    final order = _orderCol(sort, {
      'revenue': 'revenue',
      'quantity': 'quantity',
      'transactions': 'transactions',
      'visits': 'visits',
      'avg': 'avg_price',
    }, 'revenue');
    return db.rawQuery('''
      SELECT
        COALESCE(NULLIF(vs.service_type_name_snapshot, ''), '(No Type)') AS name,
        MAX(vs.service_type_id) AS service_type_id,
        CASE WHEN vs.service_type_name_snapshot IS NULL
                  OR vs.service_type_name_snapshot = '' THEN 1 ELSE 0 END AS is_no_type,
        COUNT(*) AS transactions,
        COUNT(DISTINCT vs.visit_id) AS visits,
        COALESCE(SUM(vs.quantity), 0) AS quantity,
        COALESCE(SUM(vs.total), 0) AS revenue,
        CASE WHEN SUM(vs.quantity) > 0
             THEN SUM(vs.total) * 1.0 / SUM(vs.quantity) ELSE 0 END AS avg_price
      FROM visit_services vs
      JOIN visits v ON v.id = vs.visit_id
      WHERE v.visit_date >= ? AND v.visit_date < ?
        AND vs.category_name_snapshot = ?
      GROUP BY name, is_no_type
      ORDER BY $order DESC
      LIMIT $limit
    ''', [startDate, endDate, categoryName]);
  }

  /// Top services with the full "Category → ServiceType → Service" path.
  /// Grouped on service_id (distinct even when names collide). Optionally
  /// scoped to a category and/or a service type (or the "no type" bucket).
  Future<List<Map<String, dynamic>>> getTopServices(
    String startDate,
    String endDate, {
    String? categoryName,
    String? serviceTypeName,
    bool serviceTypeIsNull = false,
    String sort = 'revenue',
    int limit = 20,
  }) async {
    final db = await AppDatabase.instance.database;
    final order = _orderCol(sort, {
      'revenue': 'revenue',
      'quantity': 'quantity',
      'transactions': 'transactions',
      'avg': 'avg_price',
    }, 'revenue');

    final wheres = <String>['v.visit_date >= ?', 'v.visit_date < ?'];
    final args = <dynamic>[startDate, endDate];
    if (categoryName != null) {
      wheres.add('vs.category_name_snapshot = ?');
      args.add(categoryName);
    }
    if (serviceTypeIsNull) {
      wheres.add("(vs.service_type_name_snapshot IS NULL OR vs.service_type_name_snapshot = '')");
    } else if (serviceTypeName != null) {
      wheres.add('vs.service_type_name_snapshot = ?');
      args.add(serviceTypeName);
    }

    final rows = await db.rawQuery('''
      SELECT
        MAX(vs.service_id) AS service_id,
        vs.category_name_snapshot AS category,
        vs.service_type_name_snapshot AS service_type,
        vs.service_name_snapshot AS name,
        COUNT(*) AS transactions,
        COALESCE(COUNT(DISTINCT vs.visit_id), 0) AS visits,
        COALESCE(SUM(vs.quantity), 0) AS quantity,
        COALESCE(SUM(vs.total), 0) AS revenue,
        CASE WHEN SUM(vs.quantity) > 0
             THEN SUM(vs.total) * 1.0 / SUM(vs.quantity) ELSE 0 END AS avg_price
      FROM visit_services vs
      JOIN visits v ON v.id = vs.visit_id
      WHERE ${wheres.join(' AND ')}
      GROUP BY $_serviceGroupKey
      ORDER BY $order DESC
      LIMIT $limit
    ''', args);

    return rows.map(_mapTopServiceRow).toList();
  }

  // ── Customer reports ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTopCustomers(
    String startDate,
    String endDate, {
    String orderBy = 'revenue',
    int limit = 20,
  }) async {
    final db = await AppDatabase.instance.database;
    final order = _orderCol(orderBy, {
      'revenue': 'collected',
      'collected': 'collected',
      'billed': 'billed',
      'visits': 'visit_count',
      'pending': 'pending',
      'written_off': 'written_off',
      'last_visit': 'last_visit',
    }, 'revenue');
    return db.rawQuery('''
      SELECT
        c.id, c.name, c.phone,
        COUNT(v.id) AS visit_count,
        COALESCE(SUM(v.final_total), 0) AS billed,
        COALESCE(SUM(v.total_paid), 0) AS collected,
        COALESCE(SUM(v.total_paid), 0) AS revenue,
        COALESCE(SUM(v.pending_amount), 0) AS pending,
        COALESCE(woq.wo, 0) AS written_off,
        MAX(v.visit_date) AS last_visit
      FROM customers c
      JOIN visits v ON v.customer_id = c.id
      LEFT JOIN (
        SELECT v2.customer_id AS cid, SUM(w.amount) AS wo
        FROM write_offs w
        JOIN visits v2 ON v2.id = w.visit_id
        WHERE v2.visit_date >= ? AND v2.visit_date < ?
        GROUP BY v2.customer_id
      ) woq ON woq.cid = c.id
      WHERE v.visit_date >= ? AND v.visit_date < ?
      GROUP BY c.id
      ORDER BY $order DESC
      LIMIT $limit
    ''', [startDate, endDate, startDate, endDate]);
  }

  Future<Map<String, dynamic>> getCustomerStats(int customerId) async {
    final db = await AppDatabase.instance.database;
    final result = (await db.rawQuery('''
      SELECT
        COUNT(*) AS total_visits,
        COALESCE(SUM(final_total), 0) AS total_billed,
        COALESCE(SUM(total_paid), 0) AS total_paid,
        COALESCE(SUM(pending_amount), 0) AS total_pending,
        MAX(visit_date) AS last_visit,
        MIN(visit_date) AS first_visit
      FROM visits
      WHERE customer_id = ?
    ''', [customerId])).first;
    return result;
  }

  Future<List<Map<String, dynamic>>> getBirthdaysInRange(
      String mmdd1, String mmdd2) async {
    final db = await AppDatabase.instance.database;
    return db.rawQuery('''
      SELECT id, name, phone, birth_date, SUBSTR(birth_date, 6) AS mm_dd
      FROM customers
      WHERE birth_date IS NOT NULL AND is_active = 1
        AND SUBSTR(birth_date, 6) BETWEEN ? AND ?
      ORDER BY SUBSTR(birth_date, 6) ASC
    ''', [mmdd1, mmdd2]);
  }

  Future<Map<String, dynamic>> getAppointmentStats(
      String startDate, String endDate) async {
    final db = await AppDatabase.instance.database;
    final row = (await db.rawQuery('''
      SELECT
        COUNT(*) AS total_appointments,
        SUM(CASE WHEN status = 'PENDING' THEN 1 ELSE 0 END) AS pending_count,
        SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END) AS completed_count,
        SUM(CASE WHEN status = 'NOT_ATTENDED' THEN 1 ELSE 0 END) AS not_attended_count,
        SUM(CASE WHEN status = 'CANCELLED' THEN 1 ELSE 0 END) AS cancelled_count
      FROM appointments
      WHERE appointment_date >= DATE(?) AND appointment_date < DATE(?)
    ''', [startDate, endDate])).first;

    final total = (row['total_appointments'] as num? ?? 0).toInt();
    final completed = (row['completed_count'] as num? ?? 0).toInt();
    final notAttended = (row['not_attended_count'] as num? ?? 0).toInt();
    final cancelled = (row['cancelled_count'] as num? ?? 0).toInt();
    final resolved = completed + notAttended + cancelled;

    return {
      'total_appointments': total,
      'pending_count': (row['pending_count'] as num? ?? 0).toInt(),
      'completed_count': completed,
      'not_attended_count': notAttended,
      'cancelled_count': cancelled,
      'completion_rate': total > 0 ? completed / total : 0.0,
      'resolved_completion_rate': resolved > 0 ? completed / resolved : 0.0,
      'cancellation_rate': total > 0 ? cancelled / total : 0.0,
    };
  }

  // ── Expenses ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getExpenseByCategory(
      String startDate, String endDate) async {
    final db = await AppDatabase.instance.database;
    return db.rawQuery('''
      SELECT ec.name, COALESCE(SUM(e.amount), 0) AS total
      FROM expenses e
      JOIN expense_categories ec ON ec.id = e.expense_category_id
      WHERE DATE(e.expense_date) >= DATE(?) AND DATE(e.expense_date) < DATE(?)
      GROUP BY ec.name
      ORDER BY total DESC
    ''', [startDate, endDate]);
  }
}
