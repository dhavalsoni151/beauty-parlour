import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/appointment_models.dart';
import '../models/customer_models.dart';
import '../models/package_models.dart';
import '../models/reminder_models.dart';
import '../models/visit_models.dart';

class FirestoreScope {
  FirestoreScope({required this.firestore, required this.organizationId}) {
    validateOrganizationId(organizationId);
  }

  final FirebaseFirestore firestore;
  final String organizationId;

  static void validateOrganizationId(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'organizationId');
    }
  }

  DocumentReference<Map<String, dynamic>> get organization =>
      firestore.collection('organizations').doc(organizationId);

  CollectionReference<Map<String, dynamic>> collection(String name) =>
      organization.collection(name);
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

class FirestoreModelCodec {
  static const int schemaVersion = 2;
  static final Random _random = Random();

  static int deriveIdFromDocumentId(String docId) {
    var hash = 0;
    for (final unit in docId.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static int numericId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return ts * 1000 + _random.nextInt(1000);
  }

  static Map<String, dynamic> withDocumentId(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = Map<String, dynamic>.from(snapshot.data() ?? const {});
    data['firestore_id'] = snapshot.id;
    data['id'] ??= deriveIdFromDocumentId(snapshot.id);
    return data;
  }
}

abstract class _BaseRepository {
  _BaseRepository(this.scope);

  final FirestoreScope scope;

  Future<DocumentReference<Map<String, dynamic>>> upsert({
    required String collection,
    required Map<String, dynamic> fields,
    int? id,
  }) async {
    final payload = Map<String, dynamic>.from(fields);
    payload['schema_version'] = FirestoreModelCodec.schemaVersion;
    int numeric = id ?? (payload['id'] as int?) ?? FirestoreModelCodec.numericId();
    if (id == null && payload['id'] == null) {
      while (await _findDocIdByNumericId(collection, numeric) != null) {
        numeric = FirestoreModelCodec.numericId();
      }
    }
    payload['id'] = numeric;

    final existingDocId = await _findDocIdByNumericId(collection, numeric);
    final docId = existingDocId ?? 'id_$numeric';
    final doc = scope.collection(collection).doc(docId);
    payload['firestore_id'] = doc.id;
    await doc.set(payload, SetOptions(merge: true));
    return doc;
  }

  Stream<List<Map<String, dynamic>>> streamCollection(
    String collection, {
    String? orderBy,
    bool descending = false,
    Map<String, dynamic>? where,
  }) {
    Query<Map<String, dynamic>> query = scope.collection(collection);
    if (where != null) {
      where.forEach((key, value) {
        query = query.where(key, isEqualTo: value);
      });
    }
    if (orderBy != null) {
      query = query.orderBy(orderBy, descending: descending);
    }
    return query.snapshots().map(
          (s) => s.docs.map(FirestoreModelCodec.withDocumentId).toList(),
        );
  }

  Future<String?> _findDocIdByNumericId(String collection, int id) async {
    final q = await scope
        .collection(collection)
        .where('id', isEqualTo: id)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return q.docs.first.id;
  }

  Future<Map<String, dynamic>?> getByNumericId(String collection, int id) async {
    final q = await scope
        .collection(collection)
        .where('id', isEqualTo: id)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return FirestoreModelCodec.withDocumentId(q.docs.first);
  }

  Future<void> deleteByNumericId(String collection, int id) async {
    final docId = await _findDocIdByNumericId(collection, id);
    if (docId == null) return;
    await scope.collection(collection).doc(docId).delete();
  }

  Future<DocumentReference<Map<String, dynamic>>> docByNumericId(
    String collection,
    int id,
  ) async {
    final docId = await _findDocIdByNumericId(collection, id);
    if (docId == null) {
      throw StateError('Document not found for $collection id=$id');
    }
    return scope.collection(collection).doc(docId);
  }
}

class FirestoreCustomerRepository extends _BaseRepository {
  FirestoreCustomerRepository(super.scope);

  Stream<List<Customer>> watchAll({bool activeOnly = true}) {
    return streamCollection(
      FirestoreCollectionNames.customers,
      orderBy: 'name',
      where: activeOnly ? {'is_active': 1} : null,
    ).map((rows) => rows.map(Customer.fromMap).toList());
  }

  Future<Customer?> get(int id) async {
    final row = await getByNumericId(FirestoreCollectionNames.customers, id);
    return row == null ? null : Customer.fromMap(row);
  }

  Future<int> save(Customer customer) async {
    final doc = await upsert(
      collection: FirestoreCollectionNames.customers,
      fields: customer.toMap(),
      id: customer.id,
    );
    final snapshot = await doc.get();
    return (snapshot.data()?['id'] as num).toInt();
  }

  Future<void> deactivate(int id) async {
    final doc = await docByNumericId(FirestoreCollectionNames.customers, id);
    await doc.update({'is_active': 0, 'updated_date': DateTime.now().toIso8601String()});
  }
}

class FirestoreCatalogRepository extends _BaseRepository {
  FirestoreCatalogRepository(super.scope);

  Stream<List<Category>> watchCategories() =>
      streamCollection(FirestoreCollectionNames.categories, orderBy: 'display_order')
          .map((rows) => rows.map(Category.fromMap).toList());

  Stream<List<ServiceType>> watchServiceTypes() =>
      streamCollection(FirestoreCollectionNames.serviceTypes, orderBy: 'display_order')
          .map((rows) => rows.map(ServiceType.fromMap).toList());

  Stream<List<Service>> watchServices() =>
      streamCollection(FirestoreCollectionNames.services, orderBy: 'name')
          .map((rows) => rows.map(Service.fromMap).toList());

  Future<int> saveCategory(Category value) async {
    final doc = await upsert(
      collection: FirestoreCollectionNames.categories,
      fields: value.toMap(),
      id: value.id,
    );
    return ((await doc.get()).data()?['id'] as num).toInt();
  }

  Future<int> saveServiceType(ServiceType value) async {
    final doc = await upsert(
      collection: FirestoreCollectionNames.serviceTypes,
      fields: value.toMap(),
      id: value.id,
    );
    return ((await doc.get()).data()?['id'] as num).toInt();
  }

  Future<int> saveService(Service value) async {
    final doc = await upsert(
      collection: FirestoreCollectionNames.services,
      fields: value.toMap(),
      id: value.id,
    );
    return ((await doc.get()).data()?['id'] as num).toInt();
  }

  Future<void> deleteCategory(int id) => deleteByNumericId(FirestoreCollectionNames.categories, id);
  Future<void> deleteServiceType(int id) => deleteByNumericId(FirestoreCollectionNames.serviceTypes, id);
  Future<void> deleteService(int id) => deleteByNumericId(FirestoreCollectionNames.services, id);

  Future<bool> categoryNameExists(String name, {int? excludeId}) async {
    final q = await scope
        .collection(FirestoreCollectionNames.categories)
        .where('name', isEqualTo: name)
        .where('is_active', isEqualTo: 1)
        .get();
    return q.docs.any((d) => (d.data()['id'] as int?) != excludeId);
  }

  Future<bool> serviceTypeNameExists(int categoryId, String name,
      {int? excludeId}) async {
    final q = await scope
        .collection(FirestoreCollectionNames.serviceTypes)
        .where('category_id', isEqualTo: categoryId)
        .where('name', isEqualTo: name)
        .get();
    return q.docs.any((d) => (d.data()['id'] as int?) != excludeId);
  }

  Future<bool> serviceNameExists(int categoryId, int? serviceTypeId, String name,
      {int? excludeId}) async {
    Query<Map<String, dynamic>> q = scope
        .collection(FirestoreCollectionNames.services)
        .where('category_id', isEqualTo: categoryId)
        .where('name', isEqualTo: name);
    if (serviceTypeId == null) {
      q = q.where('service_type_id', isNull: true);
    } else {
      q = q.where('service_type_id', isEqualTo: serviceTypeId);
    }
    final result = await q.get();
    return result.docs.any((d) => (d.data()['id'] as int?) != excludeId);
  }
}

class FirestoreVisitRepository extends _BaseRepository {
  FirestoreVisitRepository(super.scope);

  Stream<List<Visit>> watchVisits() {
    return streamCollection(
      FirestoreCollectionNames.visits,
      orderBy: 'visit_date',
      descending: true,
    ).map((rows) => rows.map(Visit.fromMap).toList());
  }

  Future<List<Visit>> listVisits({
    int? customerId,
    String? startDate,
    String? endDate,
  }) async {
    Query<Map<String, dynamic>> query = scope.collection(FirestoreCollectionNames.visits);
    if (customerId != null) {
      query = query.where('customer_id', isEqualTo: customerId);
    }
    if (startDate != null) {
      query = query.where('visit_date', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('visit_date', isLessThan: endDate);
    }
    query = query.orderBy('visit_date', descending: true);
    final snap = await query.get();
    return snap.docs.map(FirestoreModelCodec.withDocumentId).map(Visit.fromMap).toList();
  }

  Stream<List<Visit>> watchPendingVisits() {
    return watchVisits().map(
      (visits) => visits
          .where(
            (v) => v.paymentStatus == PaymentStatus.pending ||
                v.paymentStatus == PaymentStatus.partiallyPaid,
          )
          .toList(),
    );
  }

  Future<Visit?> get(int id) async {
    final row = await getByNumericId(FirestoreCollectionNames.visits, id);
    if (row == null) return null;
    final visit = Visit.fromMap(row);
    final visitDocId = row['firestore_id'] as String;
    final doc = scope.collection(FirestoreCollectionNames.visits).doc(visitDocId);

    final itemSnap = await doc.collection('items').get();
    visit.services = itemSnap.docs
        .map((d) => FirestoreModelCodec.withDocumentId(d))
        .map(VisitService.fromMap)
        .toList();

    final paymentSnap = await doc.collection('payments').get();
    visit.payments = paymentSnap.docs
        .map((d) => FirestoreModelCodec.withDocumentId(d))
        .map(Payment.fromMap)
        .toList();

    final customer = await getByNumericId(FirestoreCollectionNames.customers, visit.customerId);
    visit.customerName = customer?['name'] as String?;
    visit.customerPhone = customer?['phone'] as String?;
    return visit;
  }

  Future<int> save(
    Visit visit,
    List<VisitService> services,
    List<Payment> payments,
  ) async {
    final visitRef = await upsert(
      collection: FirestoreCollectionNames.visits,
      fields: visit.toMap(),
      id: visit.id,
    );
    final saved = await visitRef.get();
    final visitId = (saved.data()?['id'] as num).toInt();

    final oldItems = await visitRef.collection('items').get();
    final oldPayments = await visitRef.collection('payments').get();
    final batch = scope.firestore.batch();
    for (final d in oldItems.docs) {
      batch.delete(d.reference);
    }
    for (final d in oldPayments.docs) {
      batch.delete(d.reference);
    }
    for (final service in services) {
      final ref = visitRef.collection('items').doc();
      final map = service.toMap();
      map['id'] ??= FirestoreModelCodec.numericId();
      map['visit_id'] = visitId;
      batch.set(ref, map);
    }
    for (final payment in payments) {
      final ref = visitRef.collection('payments').doc();
      final map = payment.toMap();
      map['id'] ??= FirestoreModelCodec.numericId();
      map['visit_id'] = visitId;
      batch.set(ref, map);
    }
    await batch.commit();
    return visitId;
  }

  Future<void> updateVisit(Visit visit, List<VisitService> services) async {
    final doc = await docByNumericId(FirestoreCollectionNames.visits, visit.id!);
    await doc.set(visit.toMap(), SetOptions(merge: true));

    final oldItems = await doc.collection('items').get();
    final batch = scope.firestore.batch();
    for (final item in oldItems.docs) {
      batch.delete(item.reference);
    }
    for (final service in services) {
      final ref = doc.collection('items').doc();
      final map = service.toMap();
      map['id'] ??= FirestoreModelCodec.numericId();
      map['visit_id'] = visit.id;
      batch.set(ref, map);
    }
    await batch.commit();
  }

  Future<void> recordPayment(int visitId, Payment payment, double totalPaid,
      double pendingAmount, PaymentStatus paymentStatus) async {
    final doc = await docByNumericId(FirestoreCollectionNames.visits, visitId);
    final paymentRef = doc.collection('payments').doc();
    final payload = payment.toMap();
    payload['id'] ??= FirestoreModelCodec.numericId();
    payload['visit_id'] = visitId;
    await paymentRef.set(payload);
    await doc.update({
      'total_paid': totalPaid,
      'pending_amount': pendingAmount,
      'payment_status': paymentStatus.dbValue,
      'updated_date': DateTime.now().toIso8601String(),
    });
  }

  Future<void> writeOff(int visitId, WriteOff writeOff, {double pendingAmount = 0}) async {
    final doc = await docByNumericId(FirestoreCollectionNames.visits, visitId);
    final ref = doc.collection('writeOffs').doc();
    final payload = writeOff.toMap();
    payload['id'] ??= FirestoreModelCodec.numericId();
    payload['visit_id'] = visitId;
    await ref.set(payload);
    await doc.update({
      'pending_amount': pendingAmount,
      'payment_status': PaymentStatus.writtenOff.dbValue,
      'updated_date': DateTime.now().toIso8601String(),
    });
  }
}

class FirestoreAppointmentRepository extends _BaseRepository {
  FirestoreAppointmentRepository(super.scope);

  Stream<List<Appointment>> watchAppointments() {
    return streamCollection(
      FirestoreCollectionNames.appointments,
      orderBy: 'appointment_date',
      descending: true,
    ).asyncMap((rows) async {
      final list = <Appointment>[];
      for (final row in rows) {
        final appointment = Appointment.fromMap(row);
        final doc = scope
            .collection(FirestoreCollectionNames.appointments)
            .doc(row['firestore_id'] as String);
        final services = await doc.collection('items').get();
        appointment.services = services.docs
            .map(FirestoreModelCodec.withDocumentId)
            .map(AppointmentService.fromMap)
            .toList();
        list.add(appointment);
      }
      return list;
    });
  }

  Future<List<Appointment>> getUpcoming({int limit = 5}) async {
    final today = DateTime.now();
    final dateKey = '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final snap = await scope
        .collection(FirestoreCollectionNames.appointments)
        .where('status', isEqualTo: AppointmentStatus.pending.dbValue)
        .where('appointment_date', isGreaterThanOrEqualTo: dateKey)
        .orderBy('appointment_date')
        .limit(limit * 3)
        .get();
    final items = snap.docs
        .map(FirestoreModelCodec.withDocumentId)
        .map(Appointment.fromMap)
        .toList();
    return items.take(limit).toList();
  }

  Future<bool> isSlotTaken(DateTime date, String startTime, {int? excludeId}) async {
    final day = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final snap = await scope
        .collection(FirestoreCollectionNames.appointments)
        .where('appointment_date', isEqualTo: day)
        .where('start_time', isEqualTo: startTime)
        .where('status', isEqualTo: AppointmentStatus.pending.dbValue)
        .get();
    return snap.docs.any((doc) => (doc.data()['id'] as int?) != excludeId);
  }

  Future<List<Appointment>> getForCustomer(int customerId) async {
    final snap = await scope
        .collection(FirestoreCollectionNames.appointments)
        .where('customer_id', isEqualTo: customerId)
        .orderBy('appointment_date', descending: true)
        .get();
    final list = <Appointment>[];
    for (final d in snap.docs) {
      final row = FirestoreModelCodec.withDocumentId(d);
      final appointment = Appointment.fromMap(row);
      final services = await d.reference.collection('items').get();
      appointment.services = services.docs
          .map(FirestoreModelCodec.withDocumentId)
          .map(AppointmentService.fromMap)
          .toList();
      list.add(appointment);
    }
    return list;
  }

  Future<Appointment?> get(int id) async {
    final row = await getByNumericId(FirestoreCollectionNames.appointments, id);
    if (row == null) return null;
    final a = Appointment.fromMap(row);
    final doc = scope
        .collection(FirestoreCollectionNames.appointments)
        .doc(row['firestore_id'] as String);
    final items = await doc.collection('items').get();
    a.services = items.docs
        .map(FirestoreModelCodec.withDocumentId)
        .map(AppointmentService.fromMap)
        .toList();
    return a;
  }

  Future<int> save(Appointment appointment) async {
    final doc = await upsert(
      collection: FirestoreCollectionNames.appointments,
      fields: appointment.toMap(),
      id: appointment.id,
    );
    final snap = await doc.get();
    final id = (snap.data()?['id'] as num).toInt();
    final oldItems = await doc.collection('items').get();
    final batch = scope.firestore.batch();
    for (final d in oldItems.docs) {
      batch.delete(d.reference);
    }
    for (final service in appointment.services) {
      final ref = doc.collection('items').doc();
      final payload = service.toMap();
      payload['id'] ??= FirestoreModelCodec.numericId();
      payload['appointment_id'] = id;
      batch.set(ref, payload);
    }
    await batch.commit();
    return id;
  }

  Future<void> delete(int id) => deleteByNumericId(FirestoreCollectionNames.appointments, id);

  Future<void> updateStatus(int id, AppointmentStatus status, {int? visitId}) async {
    final doc = await docByNumericId(FirestoreCollectionNames.appointments, id);
    await doc.update({
      'status': status.dbValue,
      'visit_id': visitId,
      'updated_date': DateTime.now().toIso8601String(),
    });
  }
}

class FirestoreExpenseRepository extends _BaseRepository {
  FirestoreExpenseRepository(super.scope);

  Stream<List<ExpenseCategory>> watchCategories() =>
      streamCollection(FirestoreCollectionNames.expenseCategories, orderBy: 'name')
          .map((rows) => rows.map(ExpenseCategory.fromMap).toList());

  Stream<List<Expense>> watchExpenses() =>
      streamCollection(FirestoreCollectionNames.expenses, orderBy: 'expense_date', descending: true)
          .map((rows) => rows.map(Expense.fromMap).toList());

  Future<int> saveCategory(ExpenseCategory value) async {
    final doc = await upsert(
      collection: FirestoreCollectionNames.expenseCategories,
      fields: value.toMap(),
      id: value.id,
    );
    return ((await doc.get()).data()?['id'] as num).toInt();
  }

  Future<int> saveExpense(Expense value) async {
    final doc = await upsert(
      collection: FirestoreCollectionNames.expenses,
      fields: value.toMap(),
      id: value.id,
    );
    return ((await doc.get()).data()?['id'] as num).toInt();
  }

  Future<void> deleteExpense(int id) => deleteByNumericId(FirestoreCollectionNames.expenses, id);
}

class FirestorePackageRepository extends _BaseRepository {
  FirestorePackageRepository(super.scope);

  Stream<List<Package>> watchPackages() {
    return streamCollection(FirestoreCollectionNames.packages, orderBy: 'name')
        .asyncMap((rows) async {
      final packages = <Package>[];
      for (final row in rows) {
        final p = Package.fromMap(row);
        final doc = scope.collection(FirestoreCollectionNames.packages).doc(row['firestore_id'] as String);
        final services = await doc.collection('items').get();
        p.services = services.docs
            .map(FirestoreModelCodec.withDocumentId)
            .map(PackageService.fromMap)
            .toList();
        packages.add(p);
      }
      return packages;
    });
  }

  Future<int> save(Package package) async {
    final doc = await upsert(collection: FirestoreCollectionNames.packages, fields: package.toMap(), id: package.id);
    final saved = await doc.get();
    final packageId = (saved.data()?['id'] as num).toInt();

    final oldItems = await doc.collection('items').get();
    final batch = scope.firestore.batch();
    for (final item in oldItems.docs) {
      batch.delete(item.reference);
    }
    for (final service in package.services) {
      final ref = doc.collection('items').doc();
      final payload = service.toMap();
      payload['id'] ??= FirestoreModelCodec.numericId();
      payload['package_id'] = packageId;
      batch.set(ref, payload);
    }
    await batch.commit();
    return packageId;
  }

  Future<void> delete(int id) => deleteByNumericId(FirestoreCollectionNames.packages, id);
}

class FirestoreReminderRepository extends _BaseRepository {
  FirestoreReminderRepository(super.scope);

  Future<int> save(Reminder reminder) async {
    final doc = await upsert(
      collection: FirestoreCollectionNames.reminders,
      fields: reminder.toMap(),
      id: reminder.id,
    );
    return ((await doc.get()).data()?['id'] as num).toInt();
  }
}

class FirestoreSettingsRepository extends _BaseRepository {
  FirestoreSettingsRepository(super.scope);

  Future<void> set(String key, String value) async {
    await scope.collection(FirestoreCollectionNames.settings).doc(key).set({
      'key': key,
      'value': value,
      'schema_version': FirestoreModelCodec.schemaVersion,
    }, SetOptions(merge: true));
  }

  Future<void> delete(String key) async {
    await scope.collection(FirestoreCollectionNames.settings).doc(key).delete();
  }

  Stream<Map<String, String>> watchAll() {
    return scope
        .collection(FirestoreCollectionNames.settings)
        .snapshots()
        .map((snapshot) => {
              for (final document in snapshot.docs)
                document.id: (document.data()['value'] ?? '').toString(),
            });
  }

  Future<Map<String, String>> getAll() async {
    final snap = await scope.collection(FirestoreCollectionNames.settings).get();
    return {
      for (final d in snap.docs) d.id: (d.data()['value'] ?? '').toString(),
    };
  }
}
