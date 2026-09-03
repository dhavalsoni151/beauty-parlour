import '../app_database.dart';
import '../../models/reminder_models.dart';
import '../../models/visit_models.dart';

/// Read/marketing queries behind the Customer Reminders screen.
///
/// The core query is set-based (a single SQL statement) — it finds each
/// customer's *latest* completed visit and filters on that visit's date and
/// final bill total. Nothing is loaded into Dart to compute "latest visit"
/// per customer, so it stays fast with thousands of customers / large history.
///
/// `visits` is the source of truth for a "real" visit: a row only exists once
/// a bill is actually saved on the New Visit screen (there are no draft/soft-
/// deleted visit rows), and appointments only link back to a visit after they
/// are completed. So "latest visit" here means the customer's latest actual
/// completed visit — a cancelled/uncompleted appointment never counts.
class ReminderDao {
  /// Finds customers eligible for a reminder.
  ///
  /// When [includeNeverVisited] is false (default) this returns customers whose
  /// latest visit is strictly older than `today - minDaysSinceVisit` and whose
  /// latest visit final total is >= [minAmount]. When [includeNeverVisited] is
  /// true it returns customers with NO visits at all (the other filters are
  /// then ignored).
  ///
  /// [categoryId] further restricts to customers whose latest visit included a
  /// service in that category. [packageUsed] (true/false) restricts to latest
  /// visits that did / did not use a package.
  ///
  /// [suppressContactedWithinDays] hides customers who already have a reminder
  /// recorded within that many days (null/<=0 disables suppression).
  ///
  /// Results are ordered in Dart by [sort] (the heavy lifting — the latest-
  /// visit-per-customer resolution and all filtering — is done in SQL).
  Future<List<ReminderCandidate>> findCandidates({
    required int minDaysSinceVisit,
    double minAmount = 0,
    bool includeNeverVisited = false,
    int? categoryId,
    bool? packageUsed,
    int? suppressContactedWithinDays,
    ReminderSort sort = ReminderSort.daysDesc,
  }) async {
    final db = await AppDatabase.instance.database;

    final args = <dynamic>[];
    String select;
    if (includeNeverVisited) {
      // Customers with no completed visit at all.
      select = '''
        SELECT c.id AS customer_id, c.name AS customer_name, c.phone AS customer_phone,
               NULL AS last_visit_id, NULL AS last_visit_date, NULL AS final_total,
               NULL AS package_id, NULL AS package_name_snapshot,
               NULL AS package_normal_total, NULL AS package_price, NULL AS package_discount,
               NULL AS total_paid, NULL AS pending_amount
        FROM customers c
        WHERE c.is_active = 1
          AND NOT EXISTS (SELECT 1 FROM visits v WHERE v.customer_id = c.id)
      ''';
    } else {
      // Latest visit per customer, resolved in SQL via a correlated subquery.
      // The minimum-amount filter applies to the LATEST visit's final total —
      // it filters results but never decides whether a visit "counts".
      select = '''
        SELECT c.id AS customer_id, c.name AS customer_name, c.phone AS customer_phone,
               lv.id AS last_visit_id, lv.visit_date AS last_visit_date, lv.final_total AS final_total,
               lv.package_id AS package_id, lv.package_name_snapshot AS package_name_snapshot,
               lv.package_normal_total AS package_normal_total, lv.package_price AS package_price,
               lv.package_discount AS package_discount,
               lv.total_paid AS total_paid, lv.pending_amount AS pending_amount
        FROM customers c
        JOIN visits lv ON lv.id = (
          SELECT v2.id FROM visits v2
          WHERE v2.customer_id = c.id
          ORDER BY date(v2.visit_date) DESC, v2.id DESC
          LIMIT 1
        )
        WHERE c.is_active = 1
          AND date(lv.visit_date) < date('now', 'localtime', ?)
      ''';
      args.add('-${minDaysSinceVisit.clamp(0, 100000)} days');

      if (minAmount > 0) {
        select += ' AND lv.final_total >= ?';
        args.add(minAmount);
      }
      if (packageUsed != null) {
        select += packageUsed ? ' AND lv.package_id IS NOT NULL' : ' AND lv.package_id IS NULL';
      }
      if (categoryId != null) {
        select +=
            ' AND EXISTS (SELECT 1 FROM visit_services vs WHERE vs.visit_id = lv.id AND vs.category_id = ?)';
        args.add(categoryId);
      }
    }

    // Suppression: hide customers contacted within the configured window.
    if (suppressContactedWithinDays != null && suppressContactedWithinDays > 0) {
      select += '''
        AND NOT EXISTS (
          SELECT 1 FROM reminders r
          WHERE r.customer_id = c.id
            AND date(r.reminder_date) >= date('now', 'localtime', ?)
        )
      ''';
      args.add('-$suppressContactedWithinDays days');
    }

    final rows = await db.rawQuery(select, args);

    // Compute days-since in Dart (per returned row only — already filtered).
    final today = _today();
    var candidates = rows.map((r) {
      final lastVisitDateStr = r['last_visit_date'] as String?;
      DateTime? lastVisitDate;
      int? daysSince;
      if (lastVisitDateStr != null) {
        lastVisitDate = DateTime.tryParse(lastVisitDateStr);
        if (lastVisitDate != null) {
          daysSince = today
              .difference(DateTime(lastVisitDate.year, lastVisitDate.month, lastVisitDate.day))
              .inDays;
        }
      }
      return ReminderCandidate(
        customer: CustomerInfo(
          id: r['customer_id'] as int,
          name: r['customer_name'] as String,
          phone: r['customer_phone'] as String?,
        ),
        lastVisitId: r['last_visit_id'] as int?,
        lastVisitDate: lastVisitDate,
        lastVisitAmount: (r['final_total'] as num?)?.toDouble(),
        daysSinceVisit: daysSince,
        packageId: r['package_id'] as int?,
        packageName: r['package_name_snapshot'] as String?,
        packageNormalTotal: (r['package_normal_total'] as num?)?.toDouble(),
        packagePrice: (r['package_price'] as num?)?.toDouble(),
        packageDiscount: (r['package_discount'] as num?)?.toDouble(),
        visitTotalPaid: (r['total_paid'] as num?)?.toDouble(),
        visitPendingAmount: (r['pending_amount'] as num?)?.toDouble(),
      );
    }).toList();

    _sort(candidates, sort);
    return candidates;
  }

  /// Dashboard counts using the exact same business rule as [findCandidates]
  /// (latest visit older than the given bucket, no amount filter), returned in
  /// one grouped query so the dashboard does not re-implement the logic.
  Future<Map<int, int>> getDueCounts(List<int> dayBuckets) async {
    if (dayBuckets.isEmpty) return {};
    final db = await AppDatabase.instance.database;
    final result = <int, int>{};
    for (final days in dayBuckets) {
      final rows = await db.rawQuery('''
        SELECT COUNT(*) AS cnt
        FROM customers c
        JOIN visits lv ON lv.id = (
          SELECT v2.id FROM visits v2
          WHERE v2.customer_id = c.id
          ORDER BY date(v2.visit_date) DESC, v2.id DESC
          LIMIT 1
        )
        WHERE c.is_active = 1
          AND date(lv.visit_date) < date('now', 'localtime', ?)
      ''', ['-${days.clamp(0, 100000)} days']);
      result[days] = (rows.first['cnt'] as num?)?.toInt() ?? 0;
    }
    return result;
  }

  /// Attaches the latest visit's service lines to each candidate (batch —
  /// one query for all visits, not one per customer).
  Future<List<ReminderCandidate>> attachServices(List<ReminderCandidate> candidates) async {
    final visitIds = candidates
        .where((c) => c.lastVisitId != null)
        .map((c) => c.lastVisitId!)
        .toSet()
        .toList();
    if (visitIds.isEmpty) return candidates;

    final db = await AppDatabase.instance.database;
    final placeholders = List.filled(visitIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM visit_services WHERE visit_id IN ($placeholders) ORDER BY id ASC',
      visitIds,
    );
    final byVisit = <int, List<VisitService>>{};
    for (final row in rows) {
      final vs = VisitService.fromMap(row);
      byVisit.putIfAbsent(vs.visitId, () => []).add(vs);
    }
    return candidates
        .map((c) => c.copyWithServices(byVisit[c.lastVisitId] ?? const []))
        .toList();
  }

  /// Records a reminder action (suggested/previewed/opened/dismissed).
  Future<int> insertReminder(Reminder reminder) async {
    final db = await AppDatabase.instance.database;
    return db.insert('reminders', reminder.toMap());
  }

  Future<void> updateStatus(int id, ReminderStatus status) async {
    final db = await AppDatabase.instance.database;
    await db.update('reminders', {'status': status.dbValue},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Reminder activity for a customer (newest first) — used by the profile.
  Future<List<Reminder>> getForCustomer(int customerId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT r.*, c.name AS customer_name
      FROM reminders r
      JOIN customers c ON c.id = r.customer_id
      WHERE r.customer_id = ?
      ORDER BY r.reminder_date DESC, r.id DESC
    ''', [customerId]);
    return rows.map((r) => Reminder.fromMap(r)).toList();
  }

  /// Simple funnel statistics (see ReminderStats note — never "delivered").
  Future<Map<String, int>> getStats() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN status = 'PREVIEWED' THEN 1 ELSE 0 END) AS previewed,
        SUM(CASE WHEN status = 'WHATSAPP_OPENED' THEN 1 ELSE 0 END) AS opened,
        SUM(CASE WHEN status = 'DISMISSED' THEN 1 ELSE 0 END) AS dismissed,
        COUNT(DISTINCT customer_id) AS customers
      FROM reminders
    ''');
    final r = rows.first;
    return {
      'total': (r['total'] as num?)?.toInt() ?? 0,
      'previewed': (r['previewed'] as num?)?.toInt() ?? 0,
      'opened': (r['opened'] as num?)?.toInt() ?? 0,
      'dismissed': (r['dismissed'] as num?)?.toInt() ?? 0,
      'customers': (r['customers'] as num?)?.toInt() ?? 0,
    };
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _sort(List<ReminderCandidate> list, ReminderSort sort) {
    int byName(ReminderCandidate a, ReminderCandidate b) =>
        a.customer.name.toLowerCase().compareTo(b.customer.name.toLowerCase());
    switch (sort) {
      case ReminderSort.daysDesc:
        list.sort((a, b) {
          final c = (b.daysSinceVisit ?? -1).compareTo(a.daysSinceVisit ?? -1);
          return c != 0 ? c : byName(a, b);
        });
        break;
      case ReminderSort.dateAsc:
        list.sort((a, b) {
          final ad = a.lastVisitDate;
          final bd = b.lastVisitDate;
          if (ad == null && bd == null) return byName(a, b);
          if (ad == null) return 1;
          if (bd == null) return -1;
          final c = ad.compareTo(bd);
          return c != 0 ? c : byName(a, b);
        });
        break;
      case ReminderSort.amountDesc:
        list.sort((a, b) {
          final c = (b.lastVisitAmount ?? -1).compareTo(a.lastVisitAmount ?? -1);
          return c != 0 ? c : byName(a, b);
        });
        break;
      case ReminderSort.nameAsc:
        list.sort(byName);
        break;
    }
  }
}

enum ReminderSort { daysDesc, dateAsc, amountDesc, nameAsc }
