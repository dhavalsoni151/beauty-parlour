import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_repositories.dart';

/// Rebuilds a local-schema JSON backup bundle (the same shape produced by
/// `BackupService.exportAllData()`) by reading every collection under the
/// organization back out of Firestore. The returned map can be handed
/// directly to `BackupService().importData(...)` to restore the local
/// SQLite database from the cloud copy.
///
/// This is the read-back counterpart of [FirestoreMigrationExecutor] (which
/// only ever writes SQLite -> Firestore). Document ids mirror the original
/// SQLite integer ids (see `FirestoreModelCodec.documentId`), so relations
/// (customer_id, category_id, visit_id, ...) are preserved without any
/// remapping.
class FirestoreRestoreService {
  FirestoreRestoreService(this.scope);

  final FirestoreScope scope;

  Future<Map<String, dynamic>> downloadBackup({
    void Function(String status)? onProgress,
  }) async {
    void report(String status) => onProgress?.call(status);

    report('Downloading settings...');
    final settingsMap = await FirestoreSettingsRepository(scope).getAll();
    final settings = settingsMap.entries
        .map((e) => {'key': e.key, 'value': e.value})
        .toList();

    report('Downloading customers...');
    final customers = await _listTopLevel(FirestoreCollectionNames.customers);

    report('Downloading categories...');
    final categories = await _listTopLevel(FirestoreCollectionNames.categories);

    report('Downloading service types...');
    final serviceTypes = await _listTopLevel(FirestoreCollectionNames.serviceTypes);

    report('Downloading services...');
    final services = await _listTopLevel(FirestoreCollectionNames.services);

    report('Downloading packages...');
    final packages = await _listTopLevel(FirestoreCollectionNames.packages);
    final packageServices = await _listChildren(
      parentCollection: FirestoreCollectionNames.packages,
      parents: packages,
      childCollection: 'items',
    );

    report('Downloading visits...');
    final visits = await _listTopLevel(FirestoreCollectionNames.visits);
    final visitServices = await _listChildren(
      parentCollection: FirestoreCollectionNames.visits,
      parents: visits,
      childCollection: 'items',
    );
    final payments = await _listChildren(
      parentCollection: FirestoreCollectionNames.visits,
      parents: visits,
      childCollection: 'payments',
    );
    final writeOffs = await _listChildren(
      parentCollection: FirestoreCollectionNames.visits,
      parents: visits,
      childCollection: 'writeOffs',
    );

    report('Downloading appointments...');
    final appointments = await _listTopLevel(FirestoreCollectionNames.appointments);
    final appointmentServices = await _listChildren(
      parentCollection: FirestoreCollectionNames.appointments,
      parents: appointments,
      childCollection: 'items',
    );

    report('Downloading expenses...');
    final expenseCategories = await _listTopLevel(FirestoreCollectionNames.expenseCategories);
    final expenses = await _listTopLevel(FirestoreCollectionNames.expenses);

    report('Downloading reminders...');
    final reminders = await _listTopLevel(FirestoreCollectionNames.reminders);

    report('Download complete.');
    return {
      // A schemaVersion >= 2 tells BackupService.importData to restore this
      // directly (new schema) instead of routing it through the legacy
      // Category -> ServiceType migration mapping.
      'schemaVersion': 2,
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
      'settings': settings,
      'customers': customers,
      'categories': categories,
      'service_types': serviceTypes,
      'services': services,
      'packages': packages,
      'package_services': packageServices,
      'visits': visits,
      'appointments': appointments,
      'appointment_services': appointmentServices,
      'visit_services': visitServices,
      'payments': payments,
      'write_offs': writeOffs,
      'expense_categories': expenseCategories,
      'expenses': expenses,
      'reminders': reminders,
    };
  }

  Future<List<Map<String, dynamic>>> _listTopLevel(String collection) async {
    final snapshot = await scope
        .collection(collection)
        .get(const GetOptions(source: Source.server));
    return snapshot.docs.map(_cleanRow).toList();
  }

  Future<List<Map<String, dynamic>>> _listChildren({
    required String parentCollection,
    required List<Map<String, dynamic>> parents,
    required String childCollection,
  }) async {
    final rows = <Map<String, dynamic>>[];
    for (final parent in parents) {
      final parentId = parent['id'];
      if (parentId == null) continue;
      final snapshot = await scope
          .collection(parentCollection)
          .doc(parentId.toString())
          .collection(childCollection)
          .get(const GetOptions(source: Source.server));
      rows.addAll(snapshot.docs.map(_cleanRow));
    }
    return rows;
  }

  /// Converts a Firestore document into a plain row map matching the local
  /// SQLite column set: resolves the integer `id` and strips the migration
  /// metadata fields (`schema_version`, `legacy_id`, `record_type`) that
  /// Firestore documents carry but the SQLite tables do not have columns for.
  static Map<String, dynamic> _cleanRow(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = FirestoreModelCodec.withDocumentId(snapshot);
    data.remove('schema_version');
    data.remove('legacy_id');
    data.remove('record_type');
    return data;
  }
}
