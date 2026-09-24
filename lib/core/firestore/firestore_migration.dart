import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/migration_mapping.dart';
import 'firestore_repositories.dart';

/// A deterministic Firestore write. [relativePath] is always below the
/// organization document, so a plan cannot target another tenant accidentally.
class FirestoreMigrationOperation {
  const FirestoreMigrationOperation({
    required this.table,
    required this.relativePath,
    required this.data,
    required this.historical,
  });

  final String table;
  final String relativePath;
  final Map<String, dynamic> data;
  final bool historical;
}

class FirestoreMigrationValidation {
  final Map<String, int> sourceCounts = <String, int>{};
  final Map<String, int> destinationCounts = <String, int>{};
  final Map<String, int> excludedSourceCounts = <String, int>{};
  final List<String> errors = <String>[];
  final List<String> warnings = <String>[];
  double sourceVisitsTotal = 0;
  double sourcePaymentsTotal = 0;
  double sourceExpensesTotal = 0;
  double destinationVisitsTotal = 0;
  double destinationPaymentsTotal = 0;
  double destinationExpensesTotal = 0;

  bool get isSafe => errors.isEmpty && countsReconcile && financialsReconcile;

  bool get countsReconcile => sourceCounts.entries.every((entry) {
        final expected = entry.value - (excludedSourceCounts[entry.key] ?? 0);
        return (destinationCounts[entry.key] ?? 0) == expected;
      });

  bool get financialsReconcile =>
      _close(sourceVisitsTotal, destinationVisitsTotal) &&
      _close(sourcePaymentsTotal, destinationPaymentsTotal) &&
      _close(sourceExpensesTotal, destinationExpensesTotal);

  Map<String, dynamic> toJson() => {
    'sourceCounts': sourceCounts,
    'destinationCounts': destinationCounts,
    'excludedSourceCounts': excludedSourceCounts,
    'errors': errors,
    'warnings': warnings,
    'sourceVisitsTotal': sourceVisitsTotal,
    'sourcePaymentsTotal': sourcePaymentsTotal,
    'sourceExpensesTotal': sourceExpensesTotal,
    'destinationVisitsTotal': destinationVisitsTotal,
    'destinationPaymentsTotal': destinationPaymentsTotal,
    'destinationExpensesTotal': destinationExpensesTotal,
    'financialsReconcile': financialsReconcile,
  };

  static bool _close(double a, double b) => (a - b).abs() <= 0.01;
}

class FirestoreMigrationPlan {
  const FirestoreMigrationPlan({
    required this.organizationId,
    required this.sourceFingerprint,
    required this.operations,
    required this.validation,
  });

  final String organizationId;
  final String sourceFingerprint;
  final List<FirestoreMigrationOperation> operations;
  final FirestoreMigrationValidation validation;

  bool get isSafe => validation.isSafe;
  int get writeCount => operations.length;

  bool get requiresReview => validation.warnings.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'organizationId': organizationId,
    'sourceFingerprint': sourceFingerprint,
    'writeCount': writeCount,
    'validation': validation.toJson(),
  };
}

/// Builds a dry-run plan only. It does not initialize Firebase, read Firestore,
/// write Firestore, open SQLite, or import the supplied JSON anywhere.
class FirestoreMigrationPlanner {
  FirestoreMigrationPlan build(
    Map<String, dynamic> source, {
    required String organizationId,
  }) {
    FirestoreScope.validateOrganizationId(organizationId);
    final validation = FirestoreMigrationValidation();
    final operations = <FirestoreMigrationOperation>[];
    final normalized = _normalizeSource(source, validation);

    void addRecord({
      required String table,
      required String collection,
      required Map<String, dynamic> row,
      String? parentPath,
      bool historical = false,
    }) {
      final id = _requiredId(row, table, validation);
      if (id == null) return;
      final path = [
        if (parentPath != null) parentPath,
        collection,
        id.toString(),
      ].join('/');
      final fields = historical
          ? FirestoreModelCodec.historical(row, legacyId: id)
          : FirestoreModelCodec.record(row, legacyId: id);
      operations.add(
        FirestoreMigrationOperation(
          table: table,
          relativePath: path,
          data: fields,
          historical: historical,
        ),
      );
      validation.destinationCounts[table] =
          (validation.destinationCounts[table] ?? 0) + 1;
      if (table == 'visits') {
        validation.destinationVisitsTotal += _number(row['final_total']);
      } else if (table == 'payments') {
        validation.destinationPaymentsTotal += _number(row['amount']);
      } else if (table == 'expenses') {
        validation.destinationExpensesTotal += _number(row['amount']);
      }
    }

    for (final row in _rows(normalized['settings'])) {
      final key = row['key']?.toString();
      if (key == null || key.isEmpty || key.contains('/')) {
        validation.errors.add('Invalid settings key: $key');
      } else {
        if (key == 'pin_hash' || key == 'pin_enabled') {
          validation.excludedSourceCounts['settings'] =
              (validation.excludedSourceCounts['settings'] ?? 0) + 1;
          validation.warnings.add(
            'Skipped local PIN setting "$key"; Firebase Authentication is primary.',
          );
          continue;
        }
        operations.add(
          FirestoreMigrationOperation(
            table: 'settings',
            relativePath: '${FirestoreCollectionNames.settings}/$key',
            data: FirestoreModelCodec.record(row),
            historical: false,
          ),
        );
        validation.destinationCounts['settings'] =
            (validation.destinationCounts['settings'] ?? 0) + 1;
      }
    }
    _addTable(
      normalized,
      addRecord,
      'customers',
      FirestoreCollectionNames.customers,
    );
    _addTable(
      normalized,
      addRecord,
      'categories',
      FirestoreCollectionNames.categories,
    );
    _addTable(
      normalized,
      addRecord,
      'service_types',
      FirestoreCollectionNames.serviceTypes,
    );
    _addTable(
      normalized,
      addRecord,
      'services',
      FirestoreCollectionNames.services,
    );
    _addTable(
      normalized,
      addRecord,
      'expense_categories',
      FirestoreCollectionNames.expenseCategories,
    );
    _addTable(
      normalized,
      addRecord,
      'expenses',
      FirestoreCollectionNames.expenses,
    );
    _addTable(
      normalized,
      addRecord,
      'reminders',
      FirestoreCollectionNames.reminders,
    );
    _addTable(
      normalized,
      addRecord,
      'packages',
      FirestoreCollectionNames.packages,
    );
    _addTable(
      normalized,
      addRecord,
      'visits',
      FirestoreCollectionNames.visits,
      historicalWhen: (_) => true,
    );
    _addTable(
      normalized,
      addRecord,
      'appointments',
      FirestoreCollectionNames.appointments,
      historicalWhen: (row) => row['status'] == 'COMPLETED',
    );

    for (final row in _rows(normalized['package_services'])) {
      final parentId = _requiredId(row, 'package_services', validation);
      final packageId = _numberOrNull(row['package_id']);
      if (parentId == null || packageId == null) continue;
      addRecord(
        table: 'package_services',
        collection: 'items',
        parentPath: '${FirestoreCollectionNames.packages}/$packageId',
        row: row,
      );
    }
    for (final row in _rows(normalized['visit_services'])) {
      final id = _requiredId(row, 'visit_services', validation);
      final visitId = _numberOrNull(row['visit_id']);
      if (id == null || visitId == null) continue;
      addRecord(
        table: 'visit_services',
        collection: 'items',
        parentPath: '${FirestoreCollectionNames.visits}/$visitId',
        row: row,
        historical: true,
      );
    }
    for (final row in _rows(normalized['payments'])) {
      final id = _requiredId(row, 'payments', validation);
      final visitId = _numberOrNull(row['visit_id']);
      if (id == null || visitId == null) continue;
      addRecord(
        table: 'payments',
        collection: 'payments',
        parentPath: '${FirestoreCollectionNames.visits}/$visitId',
        row: row,
        historical: true,
      );
    }
    for (final row in _rows(normalized['write_offs'])) {
      final id = _requiredId(row, 'write_offs', validation);
      final visitId = _numberOrNull(row['visit_id']);
      if (id == null || visitId == null) continue;
      addRecord(
        table: 'write_offs',
        collection: 'writeOffs',
        parentPath: '${FirestoreCollectionNames.visits}/$visitId',
        row: row,
        historical: true,
      );
    }
    for (final row in _rows(normalized['appointments'])) {
      final appointmentId = _numberOrNull(row['id']);
      if (appointmentId == null) continue;
      for (final item in _rows(normalized['appointment_services'])) {
        if (_numberOrNull(item['appointment_id']) != appointmentId) continue;
        final itemId = _requiredId(item, 'appointment_services', validation);
        if (itemId == null) continue;
        addRecord(
          table: 'appointment_services',
          collection: 'items',
          parentPath: '${FirestoreCollectionNames.appointments}/$appointmentId',
          row: item,
          historical: row['status'] == 'COMPLETED',
        );
      }
    }

    _validateRelationships(normalized, validation);
    _calculateSourceTotals(normalized, validation);
    final fingerprint = sha256
        .convert(utf8.encode(jsonEncode(_canonicalize(source))))
        .toString();
    return FirestoreMigrationPlan(
      organizationId: organizationId,
      sourceFingerprint: fingerprint,
      operations: List.unmodifiable(operations),
      validation: validation,
    );
  }

  Map<String, dynamic> _normalizeSource(
    Map<String, dynamic> source,
    FirestoreMigrationValidation validation,
  ) {
    final result = <String, dynamic>{
      for (final key in _tableKeys) key: _rows(source[key]),
    };
    final serviceTypes = _rows(source['service_types']);
    final schemaVersion = (source['schemaVersion'] as num?)?.toInt() ?? 1;
    if (serviceTypes.isNotEmpty || schemaVersion >= 2) return result;

    validation.warnings.add(
      'Legacy flat category data detected; applying category/service-type mapping.',
    );
    final categories = _rows(source['categories']);
    final categoryByName = <String, Map<String, dynamic>>{};
    final targetByLegacyCategory =
        <int, (int categoryId, int? serviceTypeId)>{};
    var nextGeneratedId =
        categories
            .map((row) => _numberOrNull(row['id']) ?? 0)
            .fold<int>(0, (max, id) => id > max ? id : max) +
        1;
    final mappedCategories = <Map<String, dynamic>>[];
    final mappedTypes = <Map<String, dynamic>>[];
    for (final category in categories) {
      final legacyId = _numberOrNull(category['id']);
      final name = category['name']?.toString() ?? '';
      final resolution = resolveLegacyCategory(name);
      if (!resolution.isServiceType) {
        mappedCategories.add(category);
        if (legacyId != null) {
          targetByLegacyCategory[legacyId] = (legacyId, null);
        }
        categoryByName[name.toLowerCase()] = category;
        continue;
      }
      var parent = categoryByName[resolution.parentCategoryName.toLowerCase()];
      if (parent == null) {
        final parentId = nextGeneratedId++;
        parent = {
          'id': parentId,
          'name': resolution.parentCategoryName,
          'is_active': 1,
          'display_order': 0,
          'created_date': DateTime.now().toIso8601String(),
        };
        mappedCategories.add(parent);
        categoryByName[resolution.parentCategoryName.toLowerCase()] = parent;
      }
      final parentId = _numberOrNull(parent['id']);
      if (legacyId == null || parentId == null) continue;
      mappedTypes.add({
        'id': legacyId,
        'category_id': parentId,
        'name': resolution.serviceTypeName,
        'is_active': 1,
        'display_order': 0,
        'created_date': category['created_date'],
      });
      targetByLegacyCategory[legacyId] = (parentId, legacyId);
    }
    result['categories'] = mappedCategories;
    result['service_types'] = mappedTypes;
    result['services'] = _rows(source['services']).map((row) {
      final copy = Map<String, dynamic>.from(row);
      final target = targetByLegacyCategory[_numberOrNull(row['category_id'])];
      if (target != null) {
        copy['category_id'] = target.$1;
        copy['service_type_id'] = target.$2;
      }
      return copy;
    }).toList();
    return result;
  }

  void _validateRelationships(
    Map<String, dynamic> source,
    FirestoreMigrationValidation validation,
  ) {
    final ids = <String, Set<int>>{
      for (final key in _idTables)
        key: _rows(
          source[key],
        ).map((row) => _numberOrNull(row['id'])).whereType<int>().toSet(),
    };
    final serviceTypeCategories = <int, int>{
      for (final row in _rows(source['service_types']))
        if (_numberOrNull(row['id']) != null &&
            _numberOrNull(row['category_id']) != null)
          _numberOrNull(row['id'])!: _numberOrNull(row['category_id'])!,
    };
    void requireId(String table, dynamic id, String context) {
      final value = _numberOrNull(id);
      if (value == null || !ids[table]!.contains(value)) {
        validation.errors.add('$context references missing $table id=$id');
      }
    }

    for (final row in _rows(source['service_types'])) {
      requireId('categories', row['category_id'], 'service_type:${row['id']}');
    }
    for (final row in _rows(source['services'])) {
      requireId('categories', row['category_id'], 'service:${row['id']}');
      if (row['service_type_id'] != null) {
        requireId(
          'service_types',
          row['service_type_id'],
          'service:${row['id']}',
        );
        final serviceTypeId = _numberOrNull(row['service_type_id']);
        final categoryId = _numberOrNull(row['category_id']);
        if (serviceTypeId != null &&
            categoryId != null &&
            serviceTypeCategories[serviceTypeId] != categoryId) {
          validation.errors.add(
            'service:${row['id']} service type $serviceTypeId belongs to a different category',
          );
        }
      }
    }
    for (final row in _rows(source['visits'])) {
      requireId('customers', row['customer_id'], 'visit:${row['id']}');
      final total = _number(row['final_total']);
      final paid = _number(row['total_paid']);
      if (_number(row['pending_amount']) < -0.01 || paid - total > 0.01) {
        validation.errors.add(
          'visit:${row['id']} has an invalid paid/pending balance',
        );
      }
    }
    for (final row in _rows(source['visit_services'])) {
      requireId('visits', row['visit_id'], 'visit_service:${row['id']}');
      if (row['service_id'] != null) {
        requireId('services', row['service_id'], 'visit_service:${row['id']}');
      }
    }
    for (final row in _rows(source['payments'])) {
      requireId('visits', row['visit_id'], 'payment:${row['id']}');
    }
    for (final row in _rows(source['write_offs'])) {
      requireId('visits', row['visit_id'], 'write_off:${row['id']}');
    }
    for (final row in _rows(source['package_services'])) {
      requireId('packages', row['package_id'], 'package_service:${row['id']}');
      if (row['service_id'] != null) {
        requireId(
          'services',
          row['service_id'],
          'package_service:${row['id']}',
        );
      }
      if (row['category_id'] != null) {
        requireId(
          'categories',
          row['category_id'],
          'package_service:${row['id']}',
        );
      }
      if (row['service_type_id'] != null) {
        requireId(
          'service_types',
          row['service_type_id'],
          'package_service:${row['id']}',
        );
      }
    }
    for (final row in _rows(source['expenses'])) {
      requireId(
        'expense_categories',
        row['expense_category_id'],
        'expense:${row['id']}',
      );
    }
    for (final row in _rows(source['reminders'])) {
      requireId('customers', row['customer_id'], 'reminder:${row['id']}');
      if (row['last_visit_id'] != null) {
        requireId('visits', row['last_visit_id'], 'reminder:${row['id']}');
      }
    }
    for (final row in _rows(source['appointments'])) {
      requireId('customers', row['customer_id'], 'appointment:${row['id']}');
      if (row['service_id'] != null) {
        requireId('services', row['service_id'], 'appointment:${row['id']}');
      }
    }
    for (final row in _rows(source['appointment_services'])) {
      requireId(
        'appointments',
        row['appointment_id'],
        'appointment_service:${row['id']}',
      );
      if (row['service_id'] != null) {
        requireId(
          'services',
          row['service_id'],
          'appointment_service:${row['id']}',
        );
      }
    }
  }

  void _calculateSourceTotals(
    Map<String, dynamic> source,
    FirestoreMigrationValidation validation,
  ) {
    for (final table in _tableKeys) {
      validation.sourceCounts[table] = _rows(source[table]).length;
    }
    validation.sourceVisitsTotal = _sum(source['visits'], 'final_total');
    validation.sourcePaymentsTotal = _sum(source['payments'], 'amount');
    validation.sourceExpensesTotal = _sum(source['expenses'], 'amount');
  }

  void _addTable(
    Map<String, dynamic> source,
    void Function({
      required String table,
      required String collection,
      required Map<String, dynamic> row,
      String? parentPath,
      bool historical,
    })
    addRecord,
    String table,
    String collection, {
    bool Function(Map<String, dynamic>)? historicalWhen,
  }) {
    for (final row in _rows(source[table])) {
      addRecord(
        table: table,
        collection: collection,
        row: row,
        historical: historicalWhen?.call(row) == true,
      );
    }
  }

  static int? _requiredId(
    Map<String, dynamic> row,
    String table,
    FirestoreMigrationValidation validation,
  ) {
    final id = _numberOrNull(row['id']);
    if (id == null) validation.errors.add('$table has a missing or invalid id');
    return id;
  }

  static List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List<dynamic>? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

  static double _sum(dynamic rows, String key) =>
      _rows(rows).fold(0, (total, row) => total + _number(row[key]));

  static double _number(dynamic value) => (value as num? ?? 0).toDouble();
  static int? _numberOrNull(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  static Map<String, dynamic> _canonicalize(Map<String, dynamic> source) {
    final keys = source.keys.toList()..sort();
    return {
      for (final key in keys)
        key: source[key] is List ? _rows(source[key]) : source[key],
    };
  }

  static const _tableKeys = [
    'settings',
    'customers',
    'categories',
    'service_types',
    'services',
    'packages',
    'package_services',
    'visits',
    'visit_services',
    'payments',
    'write_offs',
    'expense_categories',
    'expenses',
    'appointments',
    'appointment_services',
    'reminders',
  ];

  static const _idTables = [
    'customers',
    'categories',
    'service_types',
    'services',
    'packages',
    'expense_categories',
    'visits',
    'appointments',
  ];
}

class FirestoreMigrationReadback {
  const FirestoreMigrationReadback({
    required this.completed,
    required this.missingPaths,
    required this.mismatchedPaths,
    required this.counts,
    required this.visitsTotal,
    required this.paymentsTotal,
    required this.expensesTotal,
  });

  final bool completed;
  final List<String> missingPaths;
  final List<String> mismatchedPaths;
  final Map<String, int> counts;
  final double visitsTotal;
  final double paymentsTotal;
  final double expensesTotal;

  bool get matches =>
      completed && missingPaths.isEmpty && mismatchedPaths.isEmpty;

  bool matchesPlan(FirestoreMigrationPlan plan) {
    if (!matches) return false;
    final countsMatch = plan.validation.destinationCounts.entries.every(
      (entry) => counts[entry.key] == entry.value,
    );
    return countsMatch &&
        _close(visitsTotal, plan.validation.destinationVisitsTotal) &&
        _close(paymentsTotal, plan.validation.destinationPaymentsTotal) &&
        _close(expensesTotal, plan.validation.destinationExpensesTotal);
  }

  static bool _close(double left, double right) =>
      (left - right).abs() <= 0.01;
}

/// Applies a previously validated plan only when the caller explicitly opts
/// in. This class is intentionally not used by the app yet.
class FirestoreMigrationExecutor {
  FirestoreMigrationExecutor(this.scope);

  final FirestoreScope scope;

  Future<void> apply(
    FirestoreMigrationPlan plan, {
    required bool confirm,
    void Function(int completed, int total, String status)? onProgress,
  }) async {
    if (!confirm) throw StateError('Migration requires explicit confirmation.');
    if (plan.organizationId != scope.organizationId) {
      throw StateError(
        'Migration organization does not match Firestore scope.',
      );
    }
    if (!plan.isSafe) throw StateError('Migration plan failed validation.');

    final checkpoint = scope.collection('_migrations').doc(plan.sourceFingerprint);
    final checkpointSnapshot = await checkpoint.get(
      const GetOptions(source: Source.server),
    );
    final storedPaths = checkpointSnapshot.data()?['completed_paths'];
    final completedPaths = <String>{
      ...((storedPaths is List<dynamic>)
          ? storedPaths.map((path) => path.toString())
          : const <String>[]),
    };
    await checkpoint.set({
      'source_fingerprint': plan.sourceFingerprint,
      'status': 'running',
      'updated_at': FieldValue.serverTimestamp(),
      'total_operations': plan.operations.length,
    }, SetOptions(merge: true));
    onProgress?.call(completedPaths.length, plan.operations.length, 'Resuming migration');

    WriteBatch batch = scope.firestore.batch();
    final batchPaths = <String>[];
    var writes = 0;
    for (final operation in plan.operations) {
      if (completedPaths.contains(operation.relativePath)) continue;
      final reference = scope.firestore.doc(
        'organizations/${scope.organizationId}/${operation.relativePath}',
      );
      final existing = await reference.get(
        const GetOptions(source: Source.server),
      );
      if (existing.exists) {
        final existingData = existing.data() ?? const <String, dynamic>{};
        if (existingData['_migration_fingerprint'] != plan.sourceFingerprint ||
            existingData['_migration_path'] != operation.relativePath ||
            !_mapsContainPlannedFields(existingData, operation.data)) {
          throw StateError(
            'Existing document conflicts with migration path ${operation.relativePath}.',
          );
        }
        completedPaths.add(operation.relativePath);
        onProgress?.call(completedPaths.length, plan.operations.length, 'Verified existing record');
        continue;
      }
      batch.set(reference, {
        ...operation.data,
        '_migration_fingerprint': plan.sourceFingerprint,
        '_migration_path': operation.relativePath,
      });
      batchPaths.add(operation.relativePath);
      writes++;
      if (writes == 400) {
        await batch.commit();
        completedPaths.addAll(batchPaths);
        await checkpoint.set({
          'completed_paths': completedPaths.toList(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        onProgress?.call(completedPaths.length, plan.operations.length, 'Committed batch');
        batch = scope.firestore.batch();
        batchPaths.clear();
        writes = 0;
      }
    }
    if (writes > 0) {
      await batch.commit();
      completedPaths.addAll(batchPaths);
      await checkpoint.set({
        'completed_paths': completedPaths.toList(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      onProgress?.call(completedPaths.length, plan.operations.length, 'Committed final batch');
    }
    await checkpoint.set({
      'status': 'completed',
      'completed_paths': completedPaths.toList(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    onProgress?.call(completedPaths.length, plan.operations.length, 'Migration complete');
  }

  Future<FirestoreMigrationReadback> reconcile(
    FirestoreMigrationPlan plan,
  ) async {
    final missing = <String>[];
    final mismatched = <String>[];
    final counts = <String, int>{};
    var visitsTotal = 0.0;
    var paymentsTotal = 0.0;
    var expensesTotal = 0.0;
    for (final operation in plan.operations) {
      final reference = scope.firestore.doc(
        'organizations/${scope.organizationId}/${operation.relativePath}',
      );
      final snapshot = await reference.get(
        const GetOptions(source: Source.server),
      );
      if (!snapshot.exists) {
        missing.add(operation.relativePath);
        continue;
      }
      final data = snapshot.data() ?? const <String, dynamic>{};
        if (data['_migration_fingerprint'] != plan.sourceFingerprint ||
          data['_migration_path'] != operation.relativePath ||
          !_mapsContainPlannedFields(data, operation.data)) {
        mismatched.add(operation.relativePath);
        continue;
      }
      counts[operation.table] = (counts[operation.table] ?? 0) + 1;
      if (operation.table == 'visits') {
        visitsTotal += (data['final_total'] as num? ?? 0).toDouble();
      } else if (operation.table == 'payments') {
        paymentsTotal += (data['amount'] as num? ?? 0).toDouble();
      } else if (operation.table == 'expenses') {
        expensesTotal += (data['amount'] as num? ?? 0).toDouble();
      }
    }
    return FirestoreMigrationReadback(
      completed: missing.isEmpty && mismatched.isEmpty,
      missingPaths: missing,
      mismatchedPaths: mismatched,
      counts: counts,
      visitsTotal: visitsTotal,
      paymentsTotal: paymentsTotal,
      expensesTotal: expensesTotal,
    );
  }

}

bool _mapsContainPlannedFields(
  Map<String, dynamic> actual,
  Map<String, dynamic> planned,
) {
  for (final entry in planned.entries) {
    if (jsonEncode(actual[entry.key]) != jsonEncode(entry.value)) return false;
  }
  return true;
}
