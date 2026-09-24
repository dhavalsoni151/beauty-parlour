import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_repositories.dart';
import 'legacy_migration_mapping.dart';

/// Handles full-database export/import and a full "clean slate" wipe for the
/// Firestore-backed store.
///
/// JSON produced by [exportAllData] uses `format: 'firestore-v1'` and can be
/// re-imported by [importData] on this or another organization.
///
/// [importData] also auto-detects and restores TWO older JSON shapes so
/// backups taken before the Firestore migration keep working:
///  • Normalized SQLite-schema JSON (has a `service_types`/`serviceTypes`
///    table and `schemaVersion`/`version` >= 2) — table rows are mapped
///    directly onto the equivalent Firestore collections/subcollections.
///  • Legacy flat SQLite-schema JSON (categories only, no service types) —
///    routed through the same Category→ServiceType migration heuristics used
///    by the original app, then restored the same way.
class FirestoreBackupService {
  FirestoreBackupService(this.scope);

  final FirestoreScope scope;

  static const String exportFormat = 'firestore-v1';
  static const int schemaVersion = FirestoreModelCodec.schemaVersion;

  /// Top-level collections with no nested subcollections.
  static const List<String> _flatCollections = [
    FirestoreCollectionNames.customers,
    FirestoreCollectionNames.categories,
    FirestoreCollectionNames.serviceTypes,
    FirestoreCollectionNames.services,
    FirestoreCollectionNames.expenseCategories,
    FirestoreCollectionNames.expenses,
    FirestoreCollectionNames.reminders,
  ];

  /// Top-level collections that carry data in named subcollections, keyed by
  /// the subcollection names under each parent document.
  static const Map<String, List<String>> _nestedCollections = {
    FirestoreCollectionNames.visits: ['items', 'payments', 'writeOffs'],
    FirestoreCollectionNames.appointments: ['items'],
    FirestoreCollectionNames.packages: ['items'],
  };

  // ───────────────────────────── export ──────────────────────────────────

  Future<Map<String, dynamic>> exportAllData({
    void Function(String message)? onProgress,
  }) async {
    final data = <String, dynamic>{
      'format': exportFormat,
      'schemaVersion': schemaVersion,
      'exported_at': DateTime.now().toIso8601String(),
    };

    onProgress?.call('Exporting settings...');
    data[FirestoreCollectionNames.settings] = await _exportFlat(
      FirestoreCollectionNames.settings,
    );

    for (final name in _flatCollections) {
      onProgress?.call('Exporting $name...');
      data[name] = await _exportFlat(name);
    }
    for (final entry in _nestedCollections.entries) {
      onProgress?.call('Exporting ${entry.key}...');
      data[entry.key] = await _exportNested(entry.key, entry.value);
    }
    return data;
  }

  Future<List<Map<String, dynamic>>> _exportFlat(String name) async {
    final snap = await scope.collection(name).get();
    return snap.docs.map((d) => _cleanRow(d.data(), d.id)).toList();
  }

  Future<List<Map<String, dynamic>>> _exportNested(
    String name,
    List<String> subNames,
  ) async {
    final snap = await scope.collection(name).get();
    final rows = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final row = _cleanRow(doc.data(), doc.id);
      for (final sub in subNames) {
        final subSnap = await doc.reference.collection(sub).get();
        row[sub] = subSnap.docs.map((d) => _cleanRow(d.data(), d.id)).toList();
      }
      rows.add(row);
    }
    return rows;
  }

  Map<String, dynamic> _cleanRow(Map<String, dynamic>? data, String docId) {
    final row = Map<String, dynamic>.from(data ?? const {});
    row['firestore_id'] = docId;
    return row;
  }

  // ───────────────────────────── clear ───────────────────────────────────

  /// Deletes every document (and subcollection document) belonging to this
  /// organization. Requires the signed-in user to be an organization
  /// owner/admin under the current Firestore security rules.
  Future<void> clearAllData({void Function(String message)? onProgress}) async {
    for (final entry in _nestedCollections.entries) {
      onProgress?.call('Clearing ${entry.key}...');
      await _clearNested(entry.key, entry.value);
    }
    onProgress?.call('Clearing settings...');
    await _clearSettings();
    for (final name in _flatCollections) {
      onProgress?.call('Clearing $name...');
      await _clearFlat(name);
    }
  }

  Future<void> _clearFlat(String name) async {
    final snap = await scope.collection(name).get();
    await _deleteInBatches(snap.docs.map((d) => d.reference).toList());
  }

  /// Clears settings except the app PIN lock (`pin_hash`/`pin_enabled`),
  /// which are device/app preferences rather than business data and are
  /// also protected from deletion by the Firestore security rules.
  Future<void> _clearSettings() async {
    final snap = await scope.collection(FirestoreCollectionNames.settings).get();
    final refs = snap.docs
        .where((d) => d.id != 'pin_hash' && d.id != 'pin_enabled')
        .map((d) => d.reference)
        .toList();
    await _deleteInBatches(refs);
  }

  Future<void> _clearNested(String name, List<String> subNames) async {
    final parents = await scope.collection(name).get();
    final refs = <DocumentReference<Map<String, dynamic>>>[];
    for (final doc in parents.docs) {
      for (final sub in subNames) {
        final subDocs = await doc.reference.collection(sub).get();
        refs.addAll(subDocs.docs.map((d) => d.reference));
      }
      refs.add(doc.reference);
    }
    await _deleteInBatches(refs);
  }

  Future<void> _deleteInBatches(
    List<DocumentReference<Map<String, dynamic>>> refs,
  ) async {
    const chunkSize = 400; // stay comfortably under Firestore's 500-op limit
    for (var i = 0; i < refs.length; i += chunkSize) {
      final chunk = refs.skip(i).take(chunkSize);
      final batch = scope.firestore.batch();
      for (final ref in chunk) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  // ───────────────────────────── import ──────────────────────────────────

  /// Restores [data], first wiping all existing data for this organization
  /// (matching the "restore replaces everything" behaviour of the previous
  /// SQLite backup feature). Returns a [MigrationReport] describing what was
  /// restored.
  Future<MigrationReport> importData(
    Map<String, dynamic> data, {
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('Clearing existing data...');
    await clearAllData(onProgress: onProgress);

    if (_isFirestoreExport(data)) {
      onProgress?.call('Restoring backup...');
      return _importFirestoreExport(data);
    }

    final normalized =
        _isNormalizedSqlSchema(data) ? data : _migrateLegacyFlatSchema(data);
    onProgress?.call('Restoring data...');
    return _importNormalizedSqlSchema(normalized);
  }

  bool _isFirestoreExport(Map<String, dynamic> data) =>
      data['format'] == exportFormat;

  bool _isNormalizedSqlSchema(Map<String, dynamic> data) {
    final v = data['schemaVersion'] ?? data['version'];
    if (v is num && v.toInt() >= 2) return true;
    return data.containsKey('service_types') || data.containsKey('serviceTypes');
  }

  // ── restore: native Firestore export ────────────────────────────────────

  Future<MigrationReport> _importFirestoreExport(
    Map<String, dynamic> data,
  ) async {
    final report = MigrationReport();

    for (final row in _rows(data[FirestoreCollectionNames.settings])) {
      final map = _map(row)..remove('firestore_id');
      final key = (map['key'] ?? '').toString();
      if (key.isEmpty) continue;
      await scope.collection(FirestoreCollectionNames.settings).doc(key).set({
        ...map,
        'schema_version': schemaVersion,
      });
    }

    for (final name in _flatCollections) {
      for (final row in _rows(data[name])) {
        await _writeDoc(name, _map(row)..remove('firestore_id'));
        _bumpFlatCount(report, name);
      }
    }

    for (final row in _rows(data[FirestoreCollectionNames.visits])) {
      final map = _map(row)..remove('firestore_id');
      final items = _rows(map.remove('items'));
      final payments = _rows(map.remove('payments'));
      final writeOffs = _rows(map.remove('writeOffs'));
      await _writeVisit(map, items, payments, writeOffs);
      report.visits++;
      report.visitItems += items.length;
      report.payments += payments.length;
      report.writeOffs += writeOffs.length;
    }

    for (final row in _rows(data[FirestoreCollectionNames.appointments])) {
      final map = _map(row)..remove('firestore_id');
      final items = _rows(map.remove('items'));
      await _writeAppointment(map, items);
      report.appointments++;
      report.appointmentServices += items.length;
    }

    for (final row in _rows(data[FirestoreCollectionNames.packages])) {
      final map = _map(row)..remove('firestore_id');
      final items = _rows(map.remove('items'));
      await _writePackage(map, items);
      report.packages++;
      report.packageServices += items.length;
    }

    final totals = _sumsFromFirestoreExport(data);
    report.sourceVisitsTotal = report.migratedVisitsTotal = totals.$1;
    report.sourcePaymentsTotal = report.migratedPaymentsTotal = totals.$2;
    report.sourceExpensesTotal = report.migratedExpensesTotal = totals.$3;
    return report;
  }

  void _bumpFlatCount(MigrationReport report, String collection) {
    switch (collection) {
      case FirestoreCollectionNames.customers:
        report.customers++;
        break;
      case FirestoreCollectionNames.categories:
        report.categories++;
        break;
      case FirestoreCollectionNames.serviceTypes:
        report.serviceTypes++;
        break;
      case FirestoreCollectionNames.services:
        report.services++;
        break;
      case FirestoreCollectionNames.expenseCategories:
        report.expenseCategories++;
        break;
      case FirestoreCollectionNames.expenses:
        report.expenses++;
        break;
      case FirestoreCollectionNames.reminders:
        report.reminders++;
        break;
    }
  }

  // ── restore: normalized SQLite-shaped JSON (tables) ─────────────────────

  Future<MigrationReport> _importNormalizedSqlSchema(
    Map<String, dynamic> data,
  ) async {
    final report = MigrationReport();

    for (final row in _rows(data['settings'])) {
      final map = _map(row);
      final key = (map['key'] ?? '').toString();
      if (key.isEmpty) continue;
      await scope.collection(FirestoreCollectionNames.settings).doc(key).set({
        'key': key,
        'value': map['value'],
        'schema_version': schemaVersion,
      });
    }

    for (final row in _rows(data['customers'])) {
      await _writeDoc(FirestoreCollectionNames.customers, _map(row));
      report.customers++;
    }

    for (final row in _rows(data['categories'])) {
      final map = _map(row)
        ..remove('service_count')
        ..remove('service_type_count');
      await _writeDoc(FirestoreCollectionNames.categories, map);
      report.categories++;
    }

    for (final row in _rows(data['service_types'] ?? data['serviceTypes'])) {
      await _writeDoc(FirestoreCollectionNames.serviceTypes, _map(row));
      report.serviceTypes++;
    }

    for (final row in _rows(data['services'])) {
      final map = _map(row)
        ..remove('category_name')
        ..remove('service_type_name');
      await _writeDoc(FirestoreCollectionNames.services, map);
      report.services++;
    }

    for (final row
        in _rows(data['expense_categories'] ?? data['expenseCategories'])) {
      await _writeDoc(FirestoreCollectionNames.expenseCategories, _map(row));
      report.expenseCategories++;
    }

    for (final row in _rows(data['expenses'])) {
      await _writeDoc(FirestoreCollectionNames.expenses, _map(row));
      report.expenses++;
    }

    for (final row in _rows(data['reminders'])) {
      await _writeDoc(FirestoreCollectionNames.reminders, _map(row));
      report.reminders++;
    }

    final visitServicesByVisit = _groupBy(_rows(data['visit_services']), 'visit_id');
    final paymentsByVisit = _groupBy(_rows(data['payments']), 'visit_id');
    final writeOffsByVisit = _groupBy(_rows(data['write_offs']), 'visit_id');
    for (final row in _rows(data['visits'])) {
      final map = _map(row)
        ..remove('customer_name')
        ..remove('customer_phone');
      final visitId = map['id'];
      final items = visitServicesByVisit[visitId] ?? const [];
      final payments = paymentsByVisit[visitId] ?? const [];
      final writeOffs = writeOffsByVisit[visitId] ?? const [];
      await _writeVisit(map, items, payments, writeOffs);
      report.visits++;
      report.visitItems += items.length;
      report.payments += payments.length;
      report.writeOffs += writeOffs.length;
    }

    final appointmentServicesByAppointment =
        _groupBy(_rows(data['appointment_services']), 'appointment_id');
    for (final row in _rows(data['appointments'])) {
      final map = _map(row)
        ..remove('customer_name')
        ..remove('customer_phone')
        ..remove('category_name')
        ..remove('service_type_name');
      final appointmentId = map['id'];
      final items = appointmentServicesByAppointment[appointmentId] ?? const [];
      await _writeAppointment(map, items);
      report.appointments++;
      report.appointmentServices += items.length;
    }

    final packageServicesByPackage =
        _groupBy(_rows(data['package_services']), 'package_id');
    for (final row in _rows(data['packages'])) {
      final map = _map(row);
      final packageId = map['id'];
      final items = packageServicesByPackage[packageId] ?? const [];
      await _writePackage(map, items);
      report.packages++;
      report.packageServices += items.length;
    }

    for (final flag in (data['_flagged'] as List<dynamic>? ?? const [])) {
      report.addFlag(flag.toString());
    }

    final totals = _sums(data);
    report.sourceVisitsTotal = report.migratedVisitsTotal = totals.$1;
    report.sourcePaymentsTotal = report.migratedPaymentsTotal = totals.$2;
    report.sourceExpensesTotal = report.migratedExpensesTotal = totals.$3;
    if (!report.financialMatches) {
      report.addFlag('Financial totals did not reconcile after import — '
          'please review before deleting your backup.');
    }
    return report;
  }

  // ── restore: legacy flat SQLite JSON (Category, no ServiceType) ─────────

  /// Transforms legacy flat-schema JSON into the same table shape consumed
  /// by [_importNormalizedSqlSchema], fixing the Category→ServiceType
  /// hierarchy while preserving ids, prices, bills, discounts, payments,
  /// expenses and the ORIGINAL visit_services/appointment_services snapshots.
  Map<String, dynamic> _migrateLegacyFlatSchema(Map<String, dynamic> data) {
    final now = DateTime.now().toIso8601String();
    final legacyCategories = _rows(data['categories']);
    final legacyServices = _rows(data['services']);
    final flagged = <String>[];

    // Legacy category id -> resolved target.
    final Map<int, _CategoryTarget> targetByLegacyCat = {};
    // name(lower) -> new/kept category id.
    final Map<String, int> categoryIdByName = {};
    final newCategories = <Map<String, dynamic>>[];
    final newServiceTypes = <Map<String, dynamic>>[];

    var nextCategoryId = _maxId(legacyCategories) + 1;
    var nextServiceTypeId = 1;

    // Phase 1: kept categories (canonical + unmapped) preserve their ids.
    final mappedCategories = <Map<String, dynamic>>[];
    for (final c in legacyCategories) {
      final id = (c['id'] as num).toInt();
      final name = (c['name'] as String).trim();
      final res = resolveLegacyCategory(name);
      if (res.isServiceType) {
        mappedCategories.add(c);
        continue;
      }
      final map = _map(c)
        ..remove('service_count')
        ..remove('service_type_count');
      newCategories.add(map);
      categoryIdByName[name.toLowerCase()] = id;
      targetByLegacyCat[id] = _CategoryTarget(categoryId: id);
      if (res.flaggedUnmapped) {
        flagged.add('Category "$name" kept as category (unmapped)');
      }
    }

    int ensureCategory(String parentName) {
      final existing = categoryIdByName[parentName.toLowerCase()];
      if (existing != null) return existing;
      final id = nextCategoryId++;
      newCategories.add({
        'id': id,
        'name': parentName,
        'is_active': 1,
        'display_order': 0,
        'created_date': now,
      });
      categoryIdByName[parentName.toLowerCase()] = id;
      return id;
    }

    // Phase 2: mapped categories become service types under a parent.
    for (final c in mappedCategories) {
      final legacyId = (c['id'] as num).toInt();
      final name = (c['name'] as String).trim();
      final res = resolveLegacyCategory(name);
      final parentId = ensureCategory(res.parentCategoryName);
      final serviceTypeId = nextServiceTypeId++;
      newServiceTypes.add({
        'id': serviceTypeId,
        'category_id': parentId,
        'name': res.serviceTypeName,
        'is_active': 1,
        'display_order': 0,
        'created_date': now,
      });
      targetByLegacyCat[legacyId] =
          _CategoryTarget(categoryId: parentId, serviceTypeId: serviceTypeId);
      flagged.add(res.reason);
    }

    // Services: re-point onto the resolved category (+ service type).
    final Map<int, _CategoryTarget> targetByServiceId = {};
    final newServices = <Map<String, dynamic>>[];
    for (final s in legacyServices) {
      final id = (s['id'] as num).toInt();
      final legacyCatId = (s['category_id'] as num).toInt();
      final target =
          targetByLegacyCat[legacyCatId] ?? _CategoryTarget(categoryId: legacyCatId);
      final map = _map(s)
        ..remove('category_name')
        ..remove('service_type_name');
      map['category_id'] = target.categoryId;
      map['service_type_id'] = target.serviceTypeId;
      map['display_order'] = map['display_order'] ?? 0;
      newServices.add(map);
      targetByServiceId[id] = target;
    }

    Map<String, dynamic> repointService(Map<String, dynamic> row) {
      final map = _map(row);
      final serviceId = (row['service_id'] as num?)?.toInt();
      final target = serviceId != null ? targetByServiceId[serviceId] : null;
      map['category_id'] = map['category_id'] ?? target?.categoryId;
      map['service_type_id'] = map['service_type_id'] ?? target?.serviceTypeId;
      map['category_name_snapshot'] = map['category_name_snapshot'] ?? '';
      return map;
    }

    final newVisits = _rows(data['visits'])
        .map((v) => _map(v)
          ..remove('customer_name')
          ..remove('customer_phone'))
        .toList();
    final newVisitServices =
        _rows(data['visit_services']).map(repointService).toList();

    final newAppointments = _rows(data['appointments']).map((a) {
      final map = _map(a)
        ..remove('customer_name')
        ..remove('customer_phone')
        ..remove('category_name')
        ..remove('service_type_name');
      final serviceId = (a['service_id'] as num?)?.toInt();
      final target = serviceId != null ? targetByServiceId[serviceId] : null;
      map['category_id'] = map['category_id'] ?? target?.categoryId;
      map['service_type_id'] = map['service_type_id'] ?? target?.serviceTypeId;
      return map;
    }).toList();
    final newAppointmentServices = _rows(data['appointment_services']).map((aps) {
      final map = repointService(aps);
      map.remove('customer_name');
      map.remove('customer_phone');
      return map;
    }).toList();

    return {
      'settings': _rows(data['settings']),
      'customers': _rows(data['customers']),
      'categories': newCategories,
      'service_types': newServiceTypes,
      'services': newServices,
      'visits': newVisits,
      'visit_services': newVisitServices,
      'payments': _rows(data['payments']),
      'write_offs': _rows(data['write_offs']),
      'expense_categories': _rows(data['expense_categories']),
      'expenses': _rows(data['expenses']),
      'appointments': newAppointments,
      'appointment_services': newAppointmentServices,
      'packages': _rows(data['packages']),
      'package_services': _rows(data['package_services']),
      'reminders': _rows(data['reminders']),
      '_flagged': flagged,
    };
  }

  // ── shared write helpers ─────────────────────────────────────────────────

  Future<void> _writeDoc(String collection, Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) return;
    final docId = 'id_$id';
    final payload = Map<String, dynamic>.from(row);
    payload['schema_version'] = schemaVersion;
    payload['firestore_id'] = docId;
    await scope.collection(collection).doc(docId).set(payload);
  }

  Future<void> _writeSubDoc(
    DocumentReference<Map<String, dynamic>> parent,
    String sub,
    Map<String, dynamic> row, {
    Map<String, dynamic>? extra,
  }) async {
    final ref = parent.collection(sub).doc();
    final payload = Map<String, dynamic>.from(row)..remove('firestore_id');
    payload['id'] ??= FirestoreModelCodec.numericId();
    payload['schema_version'] = schemaVersion;
    if (extra != null) payload.addAll(extra);
    payload['firestore_id'] = ref.id;
    await ref.set(payload);
  }

  /// Marks a row as a write-once historical record, satisfying the
  /// `historicalCreateOnly()` Firestore rule used for restored bills.
  Map<String, dynamic> _historicalTag(Map<String, dynamic> row) {
    final seed = '${row['id']}|json-import|${DateTime.now().microsecondsSinceEpoch}';
    return {
      'record_type': 'historical_transaction',
      '_migration_fingerprint': seed.hashCode.toString(),
      '_migration_path': 'json-import',
    };
  }

  Future<void> _writeVisit(
    Map<String, dynamic> visit,
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> payments,
    List<Map<String, dynamic>> writeOffs,
  ) async {
    final visitId = visit['id'];
    if (visitId == null) return;
    final docId = 'id_$visitId';
    final ref = scope.collection(FirestoreCollectionNames.visits).doc(docId);
    final payload = Map<String, dynamic>.from(visit)..remove('firestore_id');
    payload['schema_version'] = schemaVersion;
    payload['firestore_id'] = docId;
    payload.addAll(_historicalTag(visit));
    await ref.set(payload);

    for (final item in items) {
      final m = _map(item)..['visit_id'] = visitId;
      await _writeSubDoc(ref, 'items', m, extra: _historicalTag(m));
    }
    for (final payment in payments) {
      final m = _map(payment)..['visit_id'] = visitId;
      await _writeSubDoc(ref, 'payments', m, extra: _historicalTag(m));
    }
    for (final writeOff in writeOffs) {
      final m = _map(writeOff)..['visit_id'] = visitId;
      await _writeSubDoc(ref, 'writeOffs', m, extra: _historicalTag(m));
    }
  }

  Future<void> _writeAppointment(
    Map<String, dynamic> appointment,
    List<Map<String, dynamic>> items,
  ) async {
    final appointmentId = appointment['id'];
    if (appointmentId == null) return;
    final docId = 'id_$appointmentId';
    final ref = scope.collection(FirestoreCollectionNames.appointments).doc(docId);
    final payload = Map<String, dynamic>.from(appointment)..remove('firestore_id');
    payload['schema_version'] = schemaVersion;
    payload['firestore_id'] = docId;
    await ref.set(payload);

    for (final item in items) {
      final m = _map(item)..['appointment_id'] = appointmentId;
      await _writeSubDoc(ref, 'items', m);
    }
  }

  Future<void> _writePackage(
    Map<String, dynamic> package,
    List<Map<String, dynamic>> items,
  ) async {
    final packageId = package['id'];
    if (packageId == null) return;
    final docId = 'id_$packageId';
    final ref = scope.collection(FirestoreCollectionNames.packages).doc(docId);
    final payload = Map<String, dynamic>.from(package)..remove('firestore_id');
    payload['schema_version'] = schemaVersion;
    payload['firestore_id'] = docId;
    await ref.set(payload);

    for (final item in items) {
      final m = _map(item)..['package_id'] = packageId;
      await _writeSubDoc(ref, 'items', m);
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _rows(dynamic v) =>
      (v as List<dynamic>? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  static Map<String, dynamic> _map(Map<String, dynamic> row) =>
      Map<String, dynamic>.from(row);

  static Map<dynamic, List<Map<String, dynamic>>> _groupBy(
    List<Map<String, dynamic>> rows,
    String key,
  ) {
    final result = <dynamic, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      result.putIfAbsent(row[key], () => []).add(row);
    }
    return result;
  }

  static int _maxId(List<Map<String, dynamic>> rows) {
    var max = 0;
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt() ?? 0;
      if (id > max) max = id;
    }
    return max;
  }

  /// Returns (visitsTotal, paymentsTotal, expensesTotal) from raw table JSON.
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

  /// Same as [_sums] but for a native Firestore export, where visits already
  /// carry their nested payments list.
  static (double, double, double) _sumsFromFirestoreExport(
    Map<String, dynamic> data,
  ) {
    double visitsTotal = 0;
    double paymentsTotal = 0;
    for (final v in _rows(data[FirestoreCollectionNames.visits])) {
      visitsTotal += (v['final_total'] as num? ?? 0).toDouble();
      for (final p in _rows(v['payments'])) {
        paymentsTotal += (p['amount'] as num? ?? 0).toDouble();
      }
    }
    double expensesTotal = 0;
    for (final e in _rows(data[FirestoreCollectionNames.expenses])) {
      expensesTotal += (e['amount'] as num? ?? 0).toDouble();
    }
    return (visitsTotal, paymentsTotal, expensesTotal);
  }
}

class _CategoryTarget {
  final int categoryId;
  final int? serviceTypeId;
  const _CategoryTarget({required this.categoryId, this.serviceTypeId});
}
