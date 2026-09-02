import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/customer_models.dart';
import '../models/visit_models.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('beauty_parlour.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        birth_date TEXT,
        notes TEXT,
        created_date TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_date TEXT NOT NULL,
        display_order INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE services (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        default_price REAL NOT NULL,
        description TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_date TEXT NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE visits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        visit_date TEXT NOT NULL,
        subtotal REAL NOT NULL,
        discount_type TEXT NOT NULL DEFAULT 'FIXED',
        discount_value REAL NOT NULL DEFAULT 0,
        discount_amount REAL NOT NULL DEFAULT 0,
        final_total REAL NOT NULL,
        total_paid REAL NOT NULL DEFAULT 0,
        pending_amount REAL NOT NULL DEFAULT 0,
        payment_status TEXT NOT NULL DEFAULT 'PENDING',
        notes TEXT,
        created_date TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE visit_services (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id INTEGER NOT NULL,
        service_id INTEGER NOT NULL,
        service_name_snapshot TEXT NOT NULL,
        category_name_snapshot TEXT NOT NULL DEFAULT '',
        price REAL NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        total REAL NOT NULL,
        FOREIGN KEY (visit_id) REFERENCES visits(id),
        FOREIGN KEY (service_id) REFERENCES services(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id INTEGER NOT NULL,
        payment_date TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'CASH',
        notes TEXT,
        FOREIGN KEY (visit_id) REFERENCES visits(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE write_offs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        write_off_date TEXT NOT NULL,
        reason TEXT NOT NULL DEFAULT '',
        notes TEXT,
        FOREIGN KEY (visit_id) REFERENCES visits(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE expense_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        expense_category_id INTEGER NOT NULL,
        expense_date TEXT NOT NULL,
        description TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'CASH',
        notes TEXT,
        created_date TEXT NOT NULL,
        FOREIGN KEY (expense_category_id) REFERENCES expense_categories(id)
      )
    ''');

    // Indexes for performance
    await db.execute('CREATE INDEX idx_visits_customer ON visits(customer_id)');
    await db.execute('CREATE INDEX idx_visits_date ON visits(visit_date)');
    await db.execute('CREATE INDEX idx_visit_services ON visit_services(visit_id)');
    await db.execute('CREATE INDEX idx_payments_visit ON payments(visit_id)');
    await db.execute('CREATE INDEX idx_expenses_date ON expenses(expense_date)');

    // Seed default settings
    await _seedDefaultData(db);
  }

  Future<void> _seedDefaultData(Database db) async {
    final now = DateTime.now().toIso8601String();

    // Default settings
    final defaultSettings = {
      'parlour_name': 'My Beauty Parlour',
      'owner_name': '',
      'phone': '',
      'address': '',
      'currency': '₹',
      'default_payment_method': 'CASH',
    };
    for (final entry in defaultSettings.entries) {
      await db.insert('settings', {'key': entry.key, 'value': entry.value});
    }

    // Default expense categories
    final expenseCategories = [
      'Rent', 'Electricity', 'Water', 'Salaries', 'Products',
      'Wax', 'Facial Products', 'Cleaning', 'Maintenance',
      'Marketing', 'Equipment', 'Other'
    ];
    for (final cat in expenseCategories) {
      await db.insert('expense_categories', {'name': cat, 'is_active': 1});
    }

    // Default service categories
    final serviceCategories = [
      {'name': 'Wax', 'display_order': 1},
      {'name': 'Facial', 'display_order': 2},
      {'name': 'Hair', 'display_order': 3},
      {'name': 'Manicure', 'display_order': 4},
      {'name': 'Pedicure', 'display_order': 5},
      {'name': 'Makeup', 'display_order': 6},
      {'name': 'Hair Spa', 'display_order': 7},
      {'name': 'Threading', 'display_order': 8},
      {'name': 'Other', 'display_order': 9},
    ];
    for (final cat in serviceCategories) {
      await db.insert('categories', {
        'name': cat['name'],
        'is_active': 1,
        'created_date': now,
        'display_order': cat['display_order'],
      });
    }
  }

  // ═══════════════════════════════════════════════════════════
  // SETTINGS
  // ═══════════════════════════════════════════════════════════

  Future<Map<String, String>> getSettings() async {
    final db = await database;
    final rows = await db.query('settings');
    return Map.fromEntries(rows.map((r) => MapEntry(r['key'] as String, r['value'] as String? ?? '')));
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ═══════════════════════════════════════════════════════════
  // CUSTOMERS
  // ═══════════════════════════════════════════════════════════

  Future<int> insertCustomer(Customer customer) async {
    final db = await database;
    return await db.insert('customers', customer.toMap());
  }

  Future<int> updateCustomer(Customer customer) async {
    final db = await database;
    return await db.update('customers', customer.toMap(), where: 'id = ?', whereArgs: [customer.id]);
  }

  Future<List<Customer>> getCustomers({bool activeOnly = true}) async {
    final db = await database;
    final rows = await db.query(
      'customers',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name ASC',
    );
    return rows.map((r) => Customer.fromMap(r)).toList();
  }

  Future<Customer?> getCustomer(int id) async {
    final db = await database;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<List<Customer>> searchCustomers(String query) async {
    final db = await database;
    final rows = await db.query(
      'customers',
      where: 'is_active = 1 AND (name LIKE ? OR phone LIKE ?)',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'name ASC',
    );
    return rows.map((r) => Customer.fromMap(r)).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // CATEGORIES
  // ═══════════════════════════════════════════════════════════

  Future<int> insertCategory(Category category) async {
    final db = await database;
    return await db.insert('categories', category.toMap());
  }

  Future<int> updateCategory(Category category) async {
    final db = await database;
    return await db.update('categories', category.toMap(), where: 'id = ?', whereArgs: [category.id]);
  }

  Future<List<Category>> getCategories({bool activeOnly = false}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT c.*, COUNT(CASE WHEN s.is_active = 1 THEN 1 END) as service_count
      FROM categories c
      LEFT JOIN services s ON s.category_id = c.id
      ${activeOnly ? 'WHERE c.is_active = 1' : ''}
      GROUP BY c.id
      ORDER BY c.display_order ASC, c.name ASC
    ''');
    return rows.map((r) => Category.fromMap(r)).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // SERVICES
  // ═══════════════════════════════════════════════════════════

  Future<int> insertService(Service service) async {
    final db = await database;
    return await db.insert('services', service.toMap());
  }

  Future<int> updateService(Service service) async {
    final db = await database;
    return await db.update('services', service.toMap(), where: 'id = ?', whereArgs: [service.id]);
  }

  Future<List<Service>> getServices({int? categoryId, bool activeOnly = true}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.*, c.name as category_name
      FROM services s
      JOIN categories c ON c.id = s.category_id
      WHERE ${activeOnly ? 's.is_active = 1 AND c.is_active = 1' : '1=1'}
      ${categoryId != null ? 'AND s.category_id = $categoryId' : ''}
      ORDER BY c.display_order ASC, s.name ASC
    ''');
    return rows.map((r) => Service.fromMap(r)).toList();
  }

  Future<List<Service>> searchServices(String query) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.*, c.name as category_name
      FROM services s
      JOIN categories c ON c.id = s.category_id
      WHERE s.is_active = 1 AND (s.name LIKE ? OR c.name LIKE ?)
      ORDER BY s.name ASC
    ''', ['%$query%', '%$query%']);
    return rows.map((r) => Service.fromMap(r)).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // VISITS
  // ═══════════════════════════════════════════════════════════

  Future<int> insertVisit(Visit visit, List<VisitService> services, List<Payment> payments) async {
    final db = await database;
    return await db.transaction((txn) async {
      final visitId = await txn.insert('visits', visit.toMap());
      for (final s in services) {
        await txn.insert('visit_services', {
          ...s.toMap(),
          'visit_id': visitId,
        });
      }
      for (final p in payments) {
        await txn.insert('payments', {
          ...p.toMap(),
          'visit_id': visitId,
        });
      }
      return visitId;
    });
  }

  Future<Visit?> getVisit(int id) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT v.*, c.name as customer_name, c.phone as customer_phone
      FROM visits v
      JOIN customers c ON c.id = v.customer_id
      WHERE v.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    final visit = Visit.fromMap(rows.first);
    visit.services = await getVisitServices(id);
    visit.payments = await getPaymentsForVisit(id);
    return visit;
  }

  Future<List<Visit>> getVisits({
    int? customerId,
    String? startDate,
    String? endDate,
    String? paymentStatus,
  }) async {
    final db = await database;
    final wheres = <String>[];
    final args = <dynamic>[];
    if (customerId != null) { wheres.add('v.customer_id = ?'); args.add(customerId); }
    if (startDate != null) { wheres.add('v.visit_date >= ?'); args.add(startDate); }
    if (endDate != null) { wheres.add('v.visit_date <= ?'); args.add(endDate); }
    if (paymentStatus != null) { wheres.add('v.payment_status = ?'); args.add(paymentStatus); }
    final where = wheres.isEmpty ? '' : 'WHERE ${wheres.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT v.*, c.name as customer_name, c.phone as customer_phone
      FROM visits v
      JOIN customers c ON c.id = v.customer_id
      $where
      ORDER BY v.visit_date DESC, v.id DESC
    ''', args);
    return rows.map((r) => Visit.fromMap(r)).toList();
  }

  Future<List<Visit>> getPendingVisits() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT v.*, c.name as customer_name, c.phone as customer_phone
      FROM visits v
      JOIN customers c ON c.id = v.customer_id
      WHERE v.payment_status IN ('PENDING', 'PARTIALLY_PAID')
      ORDER BY v.visit_date DESC
    ''');
    return rows.map((r) => Visit.fromMap(r)).toList();
  }

  Future<void> updateVisitPayment(int visitId, double totalPaid, double pendingAmount, String paymentStatus) async {
    final db = await database;
    await db.update('visits', {
      'total_paid': totalPaid,
      'pending_amount': pendingAmount,
      'payment_status': paymentStatus,
    }, where: 'id = ?', whereArgs: [visitId]);
  }

  // ═══════════════════════════════════════════════════════════
  // VISIT SERVICES
  // ═══════════════════════════════════════════════════════════

  Future<List<VisitService>> getVisitServices(int visitId) async {
    final db = await database;
    final rows = await db.query('visit_services', where: 'visit_id = ?', whereArgs: [visitId]);
    return rows.map((r) => VisitService.fromMap(r)).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // PAYMENTS
  // ═══════════════════════════════════════════════════════════

  Future<int> insertPayment(Payment payment) async {
    final db = await database;
    return await db.insert('payments', payment.toMap());
  }

  Future<List<Payment>> getPaymentsForVisit(int visitId) async {
    final db = await database;
    final rows = await db.query('payments', where: 'visit_id = ?', whereArgs: [visitId], orderBy: 'payment_date ASC');
    return rows.map((r) => Payment.fromMap(r)).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // WRITE-OFFS
  // ═══════════════════════════════════════════════════════════

  Future<int> insertWriteOff(WriteOff writeOff) async {
    final db = await database;
    return await db.insert('write_offs', writeOff.toMap());
  }

  Future<List<WriteOff>> getWriteOffsForVisit(int visitId) async {
    final db = await database;
    final rows = await db.query('write_offs', where: 'visit_id = ?', whereArgs: [visitId]);
    return rows.map((r) => WriteOff.fromMap(r)).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // EXPENSES
  // ═══════════════════════════════════════════════════════════

  Future<int> insertExpenseCategory(ExpenseCategory cat) async {
    final db = await database;
    return await db.insert('expense_categories', cat.toMap());
  }

  Future<int> updateExpenseCategory(ExpenseCategory cat) async {
    final db = await database;
    return await db.update('expense_categories', cat.toMap(), where: 'id = ?', whereArgs: [cat.id]);
  }

  Future<List<ExpenseCategory>> getExpenseCategories({bool activeOnly = true}) async {
    final db = await database;
    final rows = await db.query(
      'expense_categories',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name ASC',
    );
    return rows.map((r) => ExpenseCategory.fromMap(r)).toList();
  }

  Future<int> insertExpense(Expense expense) async {
    final db = await database;
    return await db.insert('expenses', expense.toMap());
  }

  Future<int> updateExpense(Expense expense) async {
    final db = await database;
    return await db.update('expenses', expense.toMap(), where: 'id = ?', whereArgs: [expense.id]);
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Expense>> getExpenses({
    String? startDate,
    String? endDate,
    int? categoryId,
  }) async {
    final db = await database;
    final wheres = <String>[];
    final args = <dynamic>[];
    if (startDate != null) { wheres.add('e.expense_date >= ?'); args.add(startDate); }
    if (endDate != null) { wheres.add('e.expense_date <= ?'); args.add(endDate); }
    if (categoryId != null) { wheres.add('e.expense_category_id = ?'); args.add(categoryId); }
    final where = wheres.isEmpty ? '' : 'WHERE ${wheres.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT e.*, ec.name as category_name
      FROM expenses e
      JOIN expense_categories ec ON ec.id = e.expense_category_id
      $where
      ORDER BY e.expense_date DESC, e.id DESC
    ''', args);
    return rows.map((r) => Expense.fromMap(r)).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // DASHBOARD & ANALYTICS QUERIES
  // ═══════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> getDashboardStats(String startDate, String endDate) async {
    final db = await database;

    final salesResult = await db.rawQuery('''
      SELECT
        COUNT(*) as visit_count,
        SUM(subtotal) as gross_sales,
        SUM(discount_amount) as total_discounts,
        SUM(final_total) as net_sales,
        SUM(total_paid) as collected,
        SUM(pending_amount) as pending,
        SUM(CASE WHEN payment_status = 'WRITTEN_OFF' THEN pending_amount ELSE 0 END) as written_off
      FROM visits
      WHERE visit_date >= ? AND visit_date <= ?
    ''', [startDate, endDate]);

    final expenseResult = await db.rawQuery('''
      SELECT SUM(amount) as total_expenses
      FROM expenses
      WHERE expense_date >= ? AND expense_date <= ?
    ''', [startDate, endDate]);

    final newCustomers = await db.rawQuery('''
      SELECT COUNT(*) as count FROM customers
      WHERE created_date >= ? AND created_date <= ? AND is_active = 1
    ''', [startDate, endDate]);

    final returningCustomers = await db.rawQuery('''
      SELECT COUNT(DISTINCT customer_id) as count FROM visits
      WHERE visit_date >= ? AND visit_date <= ?
      AND customer_id IN (
        SELECT customer_id FROM visits
        WHERE visit_date < ?
        GROUP BY customer_id
      )
    ''', [startDate, endDate, startDate]);

    final sales = salesResult.first;
    final expenses = expenseResult.first;
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
      'written_off': (sales['written_off'] as num? ?? 0).toDouble(),
      'total_expenses': totalExpenses,
      'profit': collected - totalExpenses,
      'new_customers': newCustomers.first['count'] ?? 0,
      'returning_customers': returningCustomers.first['count'] ?? 0,
    };
  }

  Future<List<Map<String, dynamic>>> getDailySalesTrend(String startDate, String endDate) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        DATE(visit_date) as date,
        SUM(final_total) as sales,
        COUNT(*) as visits
      FROM visits
      WHERE visit_date >= ? AND visit_date <= ?
      GROUP BY DATE(visit_date)
      ORDER BY date ASC
    ''', [startDate, endDate]);
  }

  Future<List<Map<String, dynamic>>> getTopServices(String startDate, String endDate, {int limit = 10}) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT
        vs.service_name_snapshot as name,
        vs.category_name_snapshot as category,
        COUNT(*) as visit_count,
        SUM(vs.total) as revenue
      FROM visit_services vs
      JOIN visits v ON v.id = vs.visit_id
      WHERE v.visit_date >= ? AND v.visit_date <= ?
      GROUP BY vs.service_name_snapshot
      ORDER BY revenue DESC
      LIMIT $limit
    ''', [startDate, endDate]);
  }

  Future<List<Map<String, dynamic>>> getTopCategories(String startDate, String endDate) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT
        vs.category_name_snapshot as name,
        COUNT(*) as visit_count,
        SUM(vs.total) as revenue
      FROM visit_services vs
      JOIN visits v ON v.id = vs.visit_id
      WHERE v.visit_date >= ? AND v.visit_date <= ?
      GROUP BY vs.category_name_snapshot
      ORDER BY revenue DESC
    ''', [startDate, endDate]);
  }

  Future<List<Map<String, dynamic>>> getPaymentMethodBreakdown(String startDate, String endDate) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT payment_method, SUM(amount) as total
      FROM payments p
      JOIN visits v ON v.id = p.visit_id
      WHERE v.visit_date >= ? AND v.visit_date <= ?
      GROUP BY payment_method
      ORDER BY total DESC
    ''', [startDate, endDate]);
  }

  Future<Map<String, dynamic>> getCustomerStats(int customerId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT
        COUNT(*) as total_visits,
        SUM(final_total) as total_billed,
        SUM(total_paid) as total_paid,
        SUM(pending_amount) as total_pending,
        MAX(visit_date) as last_visit
      FROM visits
      WHERE customer_id = ?
    ''', [customerId]);
    return result.first;
  }

  Future<List<Map<String, dynamic>>> getTopCustomers(String startDate, String endDate, {String orderBy = 'revenue'}) async {
    final db = await database;
    final orderCol = orderBy == 'visits' ? 'visit_count' : 'revenue';
    return await db.rawQuery('''
      SELECT
        c.id, c.name, c.phone,
        COUNT(v.id) as visit_count,
        SUM(v.total_paid) as revenue,
        SUM(v.pending_amount) as pending,
        MAX(v.visit_date) as last_visit
      FROM customers c
      JOIN visits v ON v.customer_id = c.id
      WHERE v.visit_date >= ? AND v.visit_date <= ?
      GROUP BY c.id
      ORDER BY $orderCol DESC
      LIMIT 20
    ''', [startDate, endDate]);
  }

  Future<List<Map<String, dynamic>>> getExpenseByCategory(String startDate, String endDate) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT ec.name, SUM(e.amount) as total
      FROM expenses e
      JOIN expense_categories ec ON ec.id = e.expense_category_id
      WHERE e.expense_date >= ? AND e.expense_date <= ?
      GROUP BY ec.name
      ORDER BY total DESC
    ''', [startDate, endDate]);
  }

  Future<List<Map<String, dynamic>>> getBirthdaysInRange(String mmdd1, String mmdd2) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT id, name, phone, birth_date,
             SUBSTR(birth_date, 6) as mm_dd
      FROM customers
      WHERE birth_date IS NOT NULL AND is_active = 1
        AND SUBSTR(birth_date, 6) BETWEEN ? AND ?
      ORDER BY SUBSTR(birth_date, 6) ASC
    ''', [mmdd1, mmdd2]);
  }

  // ═══════════════════════════════════════════════════════════
  // BACKUP / RESTORE
  // ═══════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> exportAllData() async {
    final db = await database;
    return {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'settings': await db.query('settings'),
      'customers': await db.query('customers'),
      'categories': await db.query('categories'),
      'services': await db.query('services'),
      'visits': await db.query('visits'),
      'visit_services': await db.query('visit_services'),
      'payments': await db.query('payments'),
      'write_offs': await db.query('write_offs'),
      'expense_categories': await db.query('expense_categories'),
      'expenses': await db.query('expenses'),
    };
  }

  Future<void> importAllData(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) async {
      // Clear all tables
      await txn.delete('expenses');
      await txn.delete('expense_categories');
      await txn.delete('write_offs');
      await txn.delete('payments');
      await txn.delete('visit_services');
      await txn.delete('visits');
      await txn.delete('services');
      await txn.delete('categories');
      await txn.delete('customers');
      await txn.delete('settings');

      // Restore
      for (final table in ['settings', 'customers', 'categories', 'services',
                           'visits', 'visit_services', 'payments', 'write_offs',
                           'expense_categories', 'expenses']) {
        final rows = data[table] as List<dynamic>? ?? [];
        for (final row in rows) {
          await txn.insert(table, Map<String, dynamic>.from(row as Map),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
