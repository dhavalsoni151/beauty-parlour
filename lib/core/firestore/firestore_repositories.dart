import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/appointment_models.dart';
import '../models/customer_models.dart';
import '../models/package_models.dart';
import '../models/reminder_models.dart';
import '../models/visit_models.dart';

/// All Firestore access is rooted below one organization document. Repositories
/// must be constructed with the authenticated organization's id and never use
/// root-level business collections.
class FirestoreScope {
  FirestoreScope({required this._firestore, required this.organizationId}) {
    validateOrganizationId(organizationId);
  }

  final FirebaseFirestore _firestore;
  final String organizationId;

  FirebaseFirestore get firestore => _firestore;

  static void validateOrganizationId(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'organizationId');
    }
  }

  DocumentReference<Map<String, dynamic>> get organization =>
      _firestore.collection('organizations').doc(organizationId);

  CollectionReference<Map<String, dynamic>> collection(String name) =>
      organization.collection(name);

  CollectionReference<Map<String, dynamic>> childCollection(
    String parentCollection,
    String parentId,
    String childCollection,
  ) => collection(parentCollection).doc(parentId).collection(childCollection);
}

class FirestoreCollectionNames {
  static const settings = 'settings';
  static const customers = 'customers';
  static const categories = 'categories';
  static const serviceTypes = 'serviceTypes';
  static const services = 'services';
  static const visits = 'visits';
  static const appointments = 'appointments';
  static const packages = 'packages';
  static const expenseCategories = 'expenseCategories';
  static const expenses = 'expenses';
  static const reminders = 'reminders';
}

/// Converts existing SQLite-shaped model maps into migration-friendly
/// Firestore records without changing business field names or snapshots.
class FirestoreModelCodec {
  static const int schemaVersion = 1;
  static const Uuid _uuid = Uuid();

  static String documentId({int? legacyId}) =>
      legacyId?.toString() ?? _uuid.v4();

  static Map<String, dynamic> record(
    Map<String, dynamic> fields, {
    int? legacyId,
    bool historical = false,
  }) {
    return {
      ...fields,
      'schema_version': schemaVersion,
      if (legacyId != null) 'legacy_id': legacyId,
      'record_type': historical ? 'historical_transaction' : 'master_data',
    };
  }

  static Map<String, dynamic> withDocumentId(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = Map<String, dynamic>.from(snapshot.data() ?? const {});
    final legacyId = data['legacy_id'];
    data['id'] ??= legacyId is num
        ? legacyId.toInt()
        : int.tryParse(snapshot.id);
    return data;
  }

  static Map<String, dynamic> historical(
    Map<String, dynamic> fields, {
    int? legacyId,
  }) => record(fields, legacyId: legacyId, historical: true);
}

abstract class _FirestoreRepository {
  _FirestoreRepository(this.scope);

  final FirestoreScope scope;

  Future<DocumentReference<Map<String, dynamic>>> saveMap({
    required String collection,
    required Map<String, dynamic> fields,
    int? legacyId,
    bool historical = false,
    String? documentId,
  }) async {
    final id = documentId ?? FirestoreModelCodec.documentId(legacyId: legacyId);
    final reference = scope.collection(collection).doc(id);
    await reference.set(
      FirestoreModelCodec.record(
        fields,
        legacyId: legacyId,
        historical: historical,
      ),
    );
    return reference;
  }

  Future<Map<String, dynamic>?> getMap({
    required String collection,
    required String documentId,
  }) async {
    final snapshot = await scope
        .collection(collection)
        .doc(documentId)
        .get(const GetOptions(source: Source.server));
    return snapshot.exists
        ? FirestoreModelCodec.withDocumentId(snapshot)
        : null;
  }

  Future<List<Map<String, dynamic>>> listMaps({
    required String collection,
    bool? activeOnly,
    String? orderBy,
  }) async {
    Query<Map<String, dynamic>> query = scope.collection(collection);
    if (activeOnly != null) {
      query = query.where('is_active', isEqualTo: activeOnly ? 1 : 0);
    }
    if (orderBy != null) {
      query = query.orderBy(orderBy);
    }
    final result = await query.get(const GetOptions(source: Source.server));
    return result.docs.map(FirestoreModelCodec.withDocumentId).toList();
  }
}

class FirestoreCustomerRepository extends _FirestoreRepository {
  FirestoreCustomerRepository(super.scope);

  Future<List<Customer>> getAll({bool activeOnly = true}) async {
    final rows = await listMaps(
      collection: FirestoreCollectionNames.customers,
      activeOnly: activeOnly ? true : null,
      orderBy: 'name',
    );
    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer?> get(String documentId) async {
    final row = await getMap(
      collection: FirestoreCollectionNames.customers,
      documentId: documentId,
    );
    return row == null ? null : Customer.fromMap(row);
  }

  Future<DocumentReference<Map<String, dynamic>>> save(Customer customer) =>
      saveMap(
        collection: FirestoreCollectionNames.customers,
        fields: customer.toMap(),
        legacyId: customer.id,
      );
}

class FirestoreCatalogRepository extends _FirestoreRepository {
  FirestoreCatalogRepository(super.scope);

  Future<List<Category>> getCategories({bool activeOnly = false}) async {
    final rows = await listMaps(
      collection: FirestoreCollectionNames.categories,
      activeOnly: activeOnly ? true : null,
      orderBy: 'display_order',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<List<ServiceType>> getServiceTypes({
    int? categoryId,
    bool activeOnly = false,
  }) async {
    final rows = await _queryCatalog(
      FirestoreCollectionNames.serviceTypes,
      categoryId: categoryId,
      activeOnly: activeOnly,
    );
    return rows.map(ServiceType.fromMap).toList();
  }

  Future<List<Service>> getServices({
    int? categoryId,
    int? serviceTypeId,
    bool onlyDirect = false,
    bool activeOnly = true,
  }) async {
    Query<Map<String, dynamic>> query = scope.collection(
      FirestoreCollectionNames.services,
    );
    if (activeOnly) {
      query = query.where('is_active', isEqualTo: 1);
    }
    if (categoryId != null) {
      query = query.where('category_id', isEqualTo: categoryId);
    }
    if (serviceTypeId != null) {
      query = query.where('service_type_id', isEqualTo: serviceTypeId);
    } else if (onlyDirect) {
      query = query.where('service_type_id', isNull: true);
    }
    final result = await query.get(const GetOptions(source: Source.server));
    final rows = result.docs.map(FirestoreModelCodec.withDocumentId).toList();
    rows.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return rows.map(Service.fromMap).toList();
  }

  Future<DocumentReference<Map<String, dynamic>>> saveCategory(
    Category value,
  ) => saveMap(
    collection: FirestoreCollectionNames.categories,
    fields: value.toMap(),
    legacyId: value.id,
  );

  Future<DocumentReference<Map<String, dynamic>>> saveServiceType(
    ServiceType value,
  ) => saveMap(
    collection: FirestoreCollectionNames.serviceTypes,
    fields: value.toMap(),
    legacyId: value.id,
  );

  Future<DocumentReference<Map<String, dynamic>>> saveService(Service value) =>
      saveMap(
        collection: FirestoreCollectionNames.services,
        fields: value.toMap(),
        legacyId: value.id,
      );

  Future<List<Map<String, dynamic>>> _queryCatalog(
    String collection, {
    int? categoryId,
    bool activeOnly = false,
  }) async {
    Query<Map<String, dynamic>> query = scope.collection(collection);
    if (categoryId != null) {
      query = query.where('category_id', isEqualTo: categoryId);
    }
    if (activeOnly) {
      query = query.where('is_active', isEqualTo: 1);
    }
    final result = await query.get(const GetOptions(source: Source.server));
    return result.docs.map(FirestoreModelCodec.withDocumentId).toList();
  }
}

class FirestoreVisitRepository extends _FirestoreRepository {
  FirestoreVisitRepository(super.scope);

  Future<Visit?> get(String documentId) async {
    final row = await getMap(
      collection: FirestoreCollectionNames.visits,
      documentId: documentId,
    );
    if (row == null) return null;
    final visit = Visit.fromMap(row);
    final visitReference = scope
        .collection(FirestoreCollectionNames.visits)
        .doc(documentId);
    final itemSnapshot = await visitReference
        .collection('items')
        .get(const GetOptions(source: Source.server));
    final paymentSnapshot = await visitReference
        .collection('payments')
        .get(const GetOptions(source: Source.server));
    visit.services = itemSnapshot.docs
        .map(FirestoreModelCodec.withDocumentId)
        .map(VisitService.fromMap)
        .toList();
    visit.payments = paymentSnapshot.docs
        .map(FirestoreModelCodec.withDocumentId)
        .map(Payment.fromMap)
        .toList();
    final customer = await getMap(
      collection: FirestoreCollectionNames.customers,
      documentId: visit.customerId.toString(),
    );
    if (customer != null) {
      visit.customerName = customer['name'] as String?;
      visit.customerPhone = customer['phone'] as String?;
    }
    return visit;
  }

  Future<List<Visit>> getVisits({
    int? customerId,
    String? startDate,
    String? endDate,
    String? paymentStatus,
    List<String>? paymentStatuses,
  }) async {
    Query<Map<String, dynamic>> query = scope.collection(
      FirestoreCollectionNames.visits,
    );
    if (customerId != null) {
      query = query.where('customer_id', isEqualTo: customerId);
    }
    if (startDate != null) {
      query = query.where('visit_date', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('visit_date', isLessThan: endDate);
    }
    if (paymentStatus != null) {
      query = query.where('payment_status', isEqualTo: paymentStatus);
    } else if (paymentStatuses != null && paymentStatuses.isNotEmpty) {
      query = query.where('payment_status', whereIn: paymentStatuses);
    }
    query = query.orderBy('visit_date', descending: true);
    final snapshot = await query.get(const GetOptions(source: Source.server));
    final visits = <Visit>[];
    for (final document in snapshot.docs) {
      final visit = await get(document.id);
      if (visit != null) visits.add(visit);
    }
    return visits;
  }

  Future<List<Visit>> getPendingVisits() =>
      getVisits(paymentStatuses: const ['PENDING', 'PARTIALLY_PAID']);

  Future<void> updatePayment({
    required String documentId,
    required double totalPaid,
    required double pendingAmount,
    required String paymentStatus,
  }) async {
    await scope
        .collection(FirestoreCollectionNames.visits)
        .doc(documentId)
        .update({
          'total_paid': totalPaid,
          'pending_amount': pendingAmount,
          'payment_status': paymentStatus,
          'updated_date': DateTime.now().toIso8601String(),
        });
  }

  Future<void> save({
    required String documentId,
    required Visit visit,
    required List<VisitService> services,
    required List<Payment> payments,
    List<WriteOff> writeOffs = const [],
  }) async {
    final batch = scope.firestore.batch();
    final visitReference = scope
        .collection(FirestoreCollectionNames.visits)
        .doc(documentId);
    batch.set(
      visitReference,
      FirestoreModelCodec.historical(visit.toMap(), legacyId: visit.id),
    );
    for (final service in services) {
      final childId = FirestoreModelCodec.documentId(legacyId: service.id);
      batch.set(
        visitReference.collection('items').doc(childId),
        FirestoreModelCodec.historical(service.toMap(), legacyId: service.id),
      );
    }
    for (final payment in payments) {
      final childId = FirestoreModelCodec.documentId(legacyId: payment.id);
      batch.set(
        visitReference.collection('payments').doc(childId),
        FirestoreModelCodec.historical(payment.toMap(), legacyId: payment.id),
      );
    }
    for (final writeOff in writeOffs) {
      final childId = FirestoreModelCodec.documentId(legacyId: writeOff.id);
      batch.set(
        visitReference.collection('writeOffs').doc(childId),
        FirestoreModelCodec.historical(writeOff.toMap(), legacyId: writeOff.id),
      );
    }
    await batch.commit();
  }
}

class FirestoreAppointmentRepository extends _FirestoreRepository {
  FirestoreAppointmentRepository(super.scope);

  Future<void> save(Appointment appointment) async {
    final documentId = FirestoreModelCodec.documentId(legacyId: appointment.id);
    final reference = scope
        .collection(FirestoreCollectionNames.appointments)
        .doc(documentId);
    final batch = scope.firestore.batch();
    batch.set(
      reference,
      FirestoreModelCodec.record(
        appointment.toMap(),
        legacyId: appointment.id,
        historical: appointment.status == AppointmentStatus.completed,
      ),
    );
    for (final service in appointment.services) {
      final childId = FirestoreModelCodec.documentId(legacyId: service.id);
      batch.set(
        reference.collection('items').doc(childId),
        FirestoreModelCodec.record(
          service.toMap(),
          legacyId: service.id,
          historical: appointment.status == AppointmentStatus.completed,
        ),
      );
    }
    await batch.commit();
  }
}

class FirestorePackageRepository extends _FirestoreRepository {
  FirestorePackageRepository(super.scope);

  Future<DocumentReference<Map<String, dynamic>>> save(Package package) async {
    final reference = await saveMap(
      collection: FirestoreCollectionNames.packages,
      fields: package.toMap(),
      legacyId: package.id,
    );
    final batch = scope.firestore.batch();
    for (final service in package.services) {
      final childId = FirestoreModelCodec.documentId(legacyId: service.id);
      batch.set(
        reference.collection('items').doc(childId),
        FirestoreModelCodec.record(service.toMap(), legacyId: service.id),
      );
    }
    await batch.commit();
    return reference;
  }
}

class FirestoreExpenseRepository extends _FirestoreRepository {
  FirestoreExpenseRepository(super.scope);

  Future<List<ExpenseCategory>> getCategories({bool activeOnly = true}) async {
    final rows = await listMaps(
      collection: FirestoreCollectionNames.expenseCategories,
      activeOnly: activeOnly ? true : null,
      orderBy: 'name',
    );
    return rows.map(ExpenseCategory.fromMap).toList();
  }

  Future<DocumentReference<Map<String, dynamic>>> saveCategory(
    ExpenseCategory category,
  ) => saveMap(
    collection: FirestoreCollectionNames.expenseCategories,
    fields: category.toMap(),
    legacyId: category.id,
  );

  Future<DocumentReference<Map<String, dynamic>>> save(Expense expense) =>
      saveMap(
        collection: FirestoreCollectionNames.expenses,
        fields: expense.toMap(),
        legacyId: expense.id,
      );
}

class FirestoreReminderRepository extends _FirestoreRepository {
  FirestoreReminderRepository(super.scope);

  Future<DocumentReference<Map<String, dynamic>>> save(Reminder reminder) =>
      saveMap(
        collection: FirestoreCollectionNames.reminders,
        fields: reminder.toMap(),
        legacyId: reminder.id,
      );
}

class FirestoreSettingsRepository extends _FirestoreRepository {
  FirestoreSettingsRepository(super.scope);

  Future<void> set(String key, String value) async {
    await scope.collection(FirestoreCollectionNames.settings).doc(key).set({
      'key': key,
      'value': value,
      'schema_version': FirestoreModelCodec.schemaVersion,
    });
  }

  Future<Map<String, String>> getAll() async {
    final snapshot = await scope
        .collection(FirestoreCollectionNames.settings)
        .get(const GetOptions(source: Source.server));
    return {
      for (final document in snapshot.docs)
        document.id: (document.data()['value'] ?? '').toString(),
    };
  }
}
