import 'package:sqflite/sqflite.dart';
import '../app_database.dart';
import '../migration_mapping.dart';

/// Handles JSON backup/export and restore/import. JSON is used ONLY here (for
/// backup and migration) — never as the live store.
///
/// Import auto-detects the schema:
///   • New schema (has a `service_types`/`serviceTypes` key or schemaVersion>=2)
///     is restored directly.
///   • Legacy flat schema (no service types) is routed through the same
///     Category→ServiceType migration mapping used for the sqflite upgrade path,
///     producing a [MigrationReport].
class BackupService {
  static const int schemaVersion = AppDatabase.schemaVersion;

  /// Tables in dependency order (parents first) for restore.
  static const List<String> _tables = [
    'settings',
    'customers',
    'categories',
    'service_types',
    'services',
    'visits',
    'appointments',
    'appointment_services',
    'visit_services',
    'payments',
    'write_offs',
    'expense_categories',
    'expenses',
  ];

  Future<Map<String, dynamic>> exportAllData() async {
    final db = await AppDatabase.instance.database;
    final data = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'version': schemaVersion,
      'exported_at': DateTime.now().toIso8601String(),
    };
    for (final table in _tables) {
      data[table] = await db.query(table);
    }
    return data;
  }

  bool _isNewSchema(Map<String, dynamic> data) {
    final v = data['schemaVersion'];
    if (v is int && v >= 2) return true;
    return data.containsKey('service_types') || data.containsKey('serviceTypes');
  }

  /// Restores from a backup. Returns a [MigrationReport] describing the result
  /// (for legacy backups it includes flagged records and reconciliation).
  Future<MigrationReport> importData(Map<String, dynamic> data) async {
    if (_isNewSchema(data)) {
      return _restoreNewSchema(data);
    }
    return migrateLegacyJson(data);
  }

  Future<void> _clearAll(Transaction txn) async {
    // Children first.
    for (final table in _tables.reversed) {
      await txn.delete(table);
    }
  }

  Future<MigrationReport> _restoreNewSchema(Map<String, dynamic> data) async {
    final db = await AppDatabase.instance.database;
    final report = MigrationReport();
    await db.transaction((txn) async {
      await _clearAll(txn);
      for (final table in _tables) {
        final rows = (data[table] as List<dynamic>? ?? const []);
        for (final row in rows) {
          await txn.insert(table, Map<String, dynamic>.from(row as Map),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
    report.customers = _len(data['customers']);
    report.categories = _len(data['categories']);
    report.serviceTypes = _len(data['service_types']);
    report.services = _len(data['services']);
    report.visits = _len(data['visits']);
    report.visitItems = _len(data['visit_services']);
    report.payments = _len(data['payments']);
    report.writeOffs = _len(data['write_offs']);
    report.expenseCategories = _len(data['expense_categories']);
    report.expenses = _len(data['expenses']);
    report.appointments = _len(data['appointments']);
    report.appointmentServices = _len(data['appointment_services']);
    final t = _sums(data);
    report.sourceVisitsTotal = report.migratedVisitsTotal = t.$1;
    report.sourcePaymentsTotal = report.migratedPaymentsTotal = t.$2;
    report.sourceExpensesTotal = report.migratedExpensesTotal = t.$3;
    return report;
  }

  /// Transforms legacy flat-schema JSON into the normalized schema, fixing the
  /// Category→ServiceType hierarchy while preserving ids, prices, bills,
  /// discounts, payments, expenses and the ORIGINAL visit_services snapshots.
  Future<MigrationReport> migrateLegacyJson(Map<String, dynamic> data) async {
    final db = await AppDatabase.instance.database;
    final report = MigrationReport();
    final now = DateTime.now().toIso8601String();

    final legacyCategories = _rows(data['categories']);
    final legacyServices = _rows(data['services']);
    final legacyVisitServices = _rows(data['visit_services']);

    // Legacy category id -> resolved target.
    final Map<int, _CategoryTarget> targetByLegacyCat = {};
    // name(lower) -> new category id (kept categories & created parents).
    final Map<String, int> categoryIdByName = {};

    await db.transaction((txn) async {
      await _clearAll(txn);

      // settings / customers / expense categories & expenses / write-offs: 1:1.
      for (final r in _rows(data['settings'])) {
        await txn.insert('settings', _map(r),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final r in _rows(data['customers'])) {
        await txn.insert('customers', _map(r),
            conflictAlgorithm: ConflictAlgorithm.replace);
        report.customers++;
      }
      for (final r in _rows(data['expense_categories'])) {
        await txn.insert('expense_categories', _map(r),
            conflictAlgorithm: ConflictAlgorithm.replace);
        report.expenseCategories++;
      }
      for (final r in _rows(data['expenses'])) {
        await txn.insert('expenses', _map(r),
            conflictAlgorithm: ConflictAlgorithm.replace);
        report.expenses++;
      }

      // Phase 1: insert kept categories (canonical + unmapped) preserving ids.
      final mappedCategories = <Map<String, dynamic>>[];
      for (final c in legacyCategories) {
        final id = (c['id'] as num).toInt();
        final name = (c['name'] as String).trim();
        final res = resolveLegacyCategory(name);
        if (res.isServiceType) {
          mappedCategories.add(c);
          continue;
        }
        final map = _map(c);
        map.remove('service_count');
        map.remove('service_type_count');
        await txn.insert('categories', map,
            conflictAlgorithm: ConflictAlgorithm.replace);
        categoryIdByName[name.toLowerCase()] = id;
        targetByLegacyCat[id] = _CategoryTarget(categoryId: id);
        report.categories++;
        if (res.flaggedUnmapped) {
          report.addFlag('Category "$name" kept as category (unmapped)');
        }
      }

      Future<int> ensureCategory(String parentName) async {
        final existing = categoryIdByName[parentName.toLowerCase()];
        if (existing != null) return existing;
        final id = await txn.insert('categories', {
          'name': parentName,
          'is_active': 1,
          'display_order': 0,
          'created_date': now,
        });
        categoryIdByName[parentName.toLowerCase()] = id;
        report.categories++;
        return id;
      }

      // Phase 2: mapped categories become service types under a parent.
      for (final c in mappedCategories) {
        final legacyId = (c['id'] as num).toInt();
        final name = (c['name'] as String).trim();
        final res = resolveLegacyCategory(name);
        final parentId = await ensureCategory(res.parentCategoryName);
        final serviceTypeId = await txn.insert('service_types', {
          'category_id': parentId,
          'name': res.serviceTypeName,
          'is_active': 1,
          'display_order': 0,
          'created_date': now,
        });
        report.serviceTypes++;
        targetByLegacyCat[legacyId] =
            _CategoryTarget(categoryId: parentId, serviceTypeId: serviceTypeId);
        report.addFlag(res.reason);
      }

      // Services: re-point onto the resolved category (+ service type).
      final Map<int, _CategoryTarget> targetByServiceId = {};
      for (final s in legacyServices) {
        final id = (s['id'] as num).toInt();
        final legacyCatId = (s['category_id'] as num).toInt();
        final target = targetByLegacyCat[legacyCatId] ??
            _CategoryTarget(categoryId: legacyCatId);
        final map = _map(s);
        map.remove('category_name');
        map.remove('service_type_name');
        map['category_id'] = target.categoryId;
        map['service_type_id'] = target.serviceTypeId;
        map['display_order'] = map['display_order'] ?? 0;
        await txn.insert('services', map,
            conflictAlgorithm: ConflictAlgorithm.replace);
        targetByServiceId[id] = target;
        report.services++;
      }

      // Visits: 1:1.
      for (final v in _rows(data['visits'])) {
        final map = _map(v);
        map.remove('customer_name');
        map.remove('customer_phone');
        await txn.insert('visits', map,
            conflictAlgorithm: ConflictAlgorithm.replace);
        report.visits++;
      }

      // Visit services: keep ORIGINAL snapshot text; only fill the id columns
      // (category_id/service_type_id) for aggregation. Never recompute names.
      for (final vs in legacyVisitServices) {
        final map = _map(vs);
        final serviceId = (vs['service_id'] as num?)?.toInt();
        final target = serviceId != null ? targetByServiceId[serviceId] : null;
        map['category_id'] = map['category_id'] ?? target?.categoryId;
        map['service_type_id'] = map['service_type_id'] ?? target?.serviceTypeId;
        // Legacy rows have no service type snapshot — keep it null (unchanged bill).
        map['service_type_name_snapshot'] = map['service_type_name_snapshot'];
        map['category_name_snapshot'] = map['category_name_snapshot'] ?? '';
        map['created_at'] = map['created_at'];
        await txn.insert('visit_services', map,
            conflictAlgorithm: ConflictAlgorithm.replace);
        report.visitItems++;
      }

      // Appointments: 1:1, re-pointing category/service-type ids the same
      // way as visit_services so upcoming appointments still resolve.
      for (final a in _rows(data['appointments'])) {
        final map = _map(a);
        map.remove('customer_name');
        map.remove('customer_phone');
        map.remove('category_name');
        map.remove('service_type_name');
        final serviceId = (a['service_id'] as num?)?.toInt();
        final target = serviceId != null ? targetByServiceId[serviceId] : null;
        map['category_id'] = map['category_id'] ?? target?.categoryId;
        map['service_type_id'] = map['service_type_id'] ?? target?.serviceTypeId;
        await txn.insert('appointments', map,
            conflictAlgorithm: ConflictAlgorithm.replace);
        report.appointments++;
      }

      // Appointment services (multi-service appointments): same re-pointing.
      for (final aps in _rows(data['appointment_services'])) {
        final map = _map(aps);
        map.remove('customer_name');
        map.remove('customer_phone');
        final serviceId = (aps['service_id'] as num?)?.toInt();
        final target = serviceId != null ? targetByServiceId[serviceId] : null;
        map['category_id'] = map['category_id'] ?? target?.categoryId;
        map['service_type_id'] = map['service_type_id'] ?? target?.serviceTypeId;
        map['category_name_snapshot'] = map['category_name_snapshot'] ?? '';
        await txn.insert('appointment_services', map,
            conflictAlgorithm: ConflictAlgorithm.replace);
        report.appointmentServices++;
      }

      // Payments: 1:1 (never collapsed).
      for (final p in _rows(data['payments'])) {
        await txn.insert('payments', _map(p),
            conflictAlgorithm: ConflictAlgorithm.replace);
        report.payments++;
      }

      // Write-offs: 1:1.
      for (final w in _rows(data['write_offs'])) {
        await txn.insert('write_offs', _map(w),
            conflictAlgorithm: ConflictAlgorithm.replace);
        report.writeOffs++;
      }
    });

    // Financial reconciliation: source (legacy JSON) vs migrated (DB).
    final srcTotals = _sums(data);
    report.sourceVisitsTotal = srcTotals.$1;
    report.sourcePaymentsTotal = srcTotals.$2;
    report.sourceExpensesTotal = srcTotals.$3;

    final db2 = await AppDatabase.instance.database;
    report.migratedVisitsTotal = Sqlite.firstDouble(
        await db2.rawQuery('SELECT COALESCE(SUM(final_total),0) FROM visits'));
    report.migratedPaymentsTotal = Sqlite.firstDouble(
        await db2.rawQuery('SELECT COALESCE(SUM(amount),0) FROM payments'));
    report.migratedExpensesTotal = Sqlite.firstDouble(
        await db2.rawQuery('SELECT COALESCE(SUM(amount),0) FROM expenses'));

    if (!report.financialMatches) {
      report.addFlag('Financial totals did not reconcile after migration — '
          'please review before deleting your backup.');
    }
    return report;
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _rows(dynamic v) =>
      (v as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  static Map<String, dynamic> _map(Map<String, dynamic> row) =>
      Map<String, dynamic>.from(row);

  static int _len(dynamic v) => (v as List<dynamic>? ?? const []).length;

  /// Returns (visitsTotal, paymentsTotal, expensesTotal) from raw JSON lists.
  static (double, double, double) _sums(Map<String, dynamic> data) {
    double sum(dynamic list, String key) {
      double t = 0;
      for (final r in _rows(list)) {
        t += (r[key] as num? ?? 0).toDouble();
      }
      return t;
    }

    return (
      sum(data['visits'], 'final_total'),
      sum(data['payments'], 'amount'),
      sum(data['expenses'], 'amount'),
    );
  }
}

class _CategoryTarget {
  final int categoryId;
  final int? serviceTypeId;
  const _CategoryTarget({required this.categoryId, this.serviceTypeId});
}
