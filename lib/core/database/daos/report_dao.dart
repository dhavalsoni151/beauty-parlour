import '../../firebase/firebase_service.dart';
import '../../firestore/firestore_repositories.dart';
import '../../models/appointment_models.dart';
import '../../models/customer_models.dart';
import '../../models/visit_models.dart';
import '../../providers/firebase_startup_provider.dart';

class ReportDao {
  ReportDao()
      : _scope = FirestoreScope(
          firestore: FirebaseService.instance.firestore,
          organizationId: firebaseOrganizationId,
        );

  final FirestoreScope _scope;

  Future<List<Visit>> _visitsInRange(String startDate, String endDate) async {
    final snap = await _scope
        .collection(FirestoreCollectionNames.visits)
        .where('visit_date', isGreaterThanOrEqualTo: startDate)
        .where('visit_date', isLessThan: endDate)
        .get();
    return snap.docs.map(FirestoreModelCodec.withDocumentId).map(Visit.fromMap).toList();
  }


  Future<double> _writtenOffForVisit(int? visitId) async {
    if (visitId == null) return 0;
    final visitDoc = await _scope
        .collection(FirestoreCollectionNames.visits)
        .where('id', isEqualTo: visitId)
        .limit(1)
        .get();
    if (visitDoc.docs.isEmpty) return 0;
    final writeOffs = await visitDoc.docs.first.reference.collection('writeOffs').get();
    return writeOffs.docs
        .map(FirestoreModelCodec.withDocumentId)
        .map(WriteOff.fromMap)
        .fold<double>(0, (s, w) => s + w.amount);
  }

  Future<Map<String, dynamic>> getDashboardStats(
      String startDate, String endDate) async {
    final visits = await _visitsInRange(startDate, endDate);
    final expenses = await _scope
        .collection(FirestoreCollectionNames.expenses)
        .where('expense_date', isGreaterThanOrEqualTo: startDate)
        .where('expense_date', isLessThan: endDate)
        .get();

    final gross = visits.fold<double>(0, (s, v) => s + v.subtotal);
    final discounts = visits.fold<double>(0, (s, v) => s + v.discountAmount);
    final net = visits.fold<double>(0, (s, v) => s + v.finalTotal);
    final collected = visits.fold<double>(0, (s, v) => s + v.totalPaid);
    final pending = visits.fold<double>(0, (s, v) => s + v.pendingAmount);
    double writtenOff = 0;
    for (final visit in visits.where((v) => v.paymentStatus == PaymentStatus.writtenOff)) {
      writtenOff += await _writtenOffForVisit(visit.id);
    }
    final totalExpenses = expenses.docs
        .map(FirestoreModelCodec.withDocumentId)
        .map(Expense.fromMap)
        .fold<double>(0, (s, e) => s + e.amount);

    final priorVisits = await _scope
        .collection(FirestoreCollectionNames.visits)
        .where('visit_date', isLessThan: startDate)
        .get();
    final priorCustomerIds = priorVisits.docs
        .map((d) => (d.data()['customer_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();

    final customersSeen = <int, int>{};
    for (final visit in visits) {
      customersSeen[visit.customerId] = (customersSeen[visit.customerId] ?? 0) + 1;
    }

    return {
      'gross_sales': gross,
      'total_discounts': discounts,
      'net_sales': net,
      'collected': collected,
      'pending': pending,
      'written_off': writtenOff,
      'total_expenses': totalExpenses,
      'profit': collected - totalExpenses,
      'visit_count': visits.length,
      'new_customers': customersSeen.keys.where((id) => !priorCustomerIds.contains(id)).length,
      'returning_customers': customersSeen.keys.where((id) => priorCustomerIds.contains(id)).length,
    };
  }

  Future<List<Map<String, dynamic>>> getTopServices(
    String startDate,
    String endDate, {
    String? categoryName,
    String? serviceTypeName,
    bool serviceTypeIsNull = false,
    String sort = 'revenue',
    int limit = 20,
  }) async {
    final visits = await _visitsInRange(startDate, endDate);
    final out = <String, Map<String, dynamic>>{};

    for (final visit in visits) {
      final doc = await _scope
          .collection(FirestoreCollectionNames.visits)
          .where('id', isEqualTo: visit.id)
          .limit(1)
          .get();
      if (doc.docs.isEmpty) continue;
      final items = await doc.docs.first.reference.collection('items').get();
      for (final d in items.docs) {
        final item = VisitService.fromMap(FirestoreModelCodec.withDocumentId(d));
        if (categoryName != null && item.categoryNameSnapshot != categoryName) continue;
        if (serviceTypeName != null && item.serviceTypeNameSnapshot != serviceTypeName) continue;
        if (serviceTypeIsNull && item.serviceTypeNameSnapshot != null) continue;
        final key = '${item.categoryNameSnapshot}|${item.serviceTypeNameSnapshot}|${item.serviceNameSnapshot}';
        final row = out.putIfAbsent(
          key,
          () => {
            'name': item.serviceNameSnapshot,
            'category': item.categoryNameSnapshot,
            'service_type': item.serviceTypeNameSnapshot,
            'visits': 0,
            'transactions': 0,
            'quantity': 0,
            'revenue': 0.0,
            'avg_price': 0.0,
          },
        );
        row['transactions'] = (row['transactions'] as int) + 1;
        row['visits'] = (row['visits'] as int) + 1;
        row['quantity'] = (row['quantity'] as int) + item.quantity;
        row['revenue'] = (row['revenue'] as double) + item.total;
      }
    }

    final rows = out.values.toList();
    for (final row in rows) {
      final q = row['quantity'] as int;
      row['avg_price'] = q == 0 ? 0.0 : (row['revenue'] as double) / q;
    }

    rows.sort((a, b) => (b[sort] as num).compareTo(a[sort] as num));
    return rows.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> getTopCategories(
    String startDate,
    String endDate, {
    String sort = 'revenue',
    int limit = 50,
  }) async {
    final services = await getTopServices(startDate, endDate, limit: 10000);
    final out = <String, Map<String, dynamic>>{};
    for (final s in services) {
      final name = (s['category'] ?? '') as String;
      final row = out.putIfAbsent(
          name, () => {'name': name, 'visits': 0, 'transactions': 0, 'quantity': 0, 'revenue': 0.0, 'avg_price': 0.0});
      row['visits'] = (row['visits'] as int) + (s['visits'] as int? ?? 0);
      row['transactions'] = (row['transactions'] as int) + (s['transactions'] as int? ?? 0);
      row['quantity'] = (row['quantity'] as int) + (s['quantity'] as int? ?? 0);
      row['revenue'] = (row['revenue'] as double) + (s['revenue'] as double? ?? 0);
    }
    final rows = out.values.toList();
    for (final row in rows) {
      final q = row['quantity'] as int;
      row['avg_price'] = q == 0 ? 0.0 : (row['revenue'] as double) / q;
    }
    rows.sort((a, b) => (b[sort] as num).compareTo(a[sort] as num));
    return rows.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> getTopServiceTypes(
    String startDate,
    String endDate,
    String categoryName, {
    String sort = 'revenue',
    int limit = 50,
  }) async {
    final services = await getTopServices(
      startDate,
      endDate,
      categoryName: categoryName,
      limit: 10000,
    );
    final out = <String, Map<String, dynamic>>{};
    for (final s in services) {
      final name = (s['service_type'] ?? 'Direct Services / No Type') as String;
      final row = out.putIfAbsent(
        name,
        () => {
          'name': name,
          'is_no_type': s['service_type'] == null ? 1 : 0,
          'visits': 0,
          'transactions': 0,
          'quantity': 0,
          'revenue': 0.0,
          'avg_price': 0.0,
        },
      );
      row['visits'] = (row['visits'] as int) + (s['visits'] as int? ?? 0);
      row['transactions'] = (row['transactions'] as int) + (s['transactions'] as int? ?? 0);
      row['quantity'] = (row['quantity'] as int) + (s['quantity'] as int? ?? 0);
      row['revenue'] = (row['revenue'] as double) + (s['revenue'] as double? ?? 0);
    }
    final rows = out.values.toList();
    for (final row in rows) {
      final q = row['quantity'] as int;
      row['avg_price'] = q == 0 ? 0.0 : (row['revenue'] as double) / q;
    }
    rows.sort((a, b) => (b[sort] as num).compareTo(a[sort] as num));
    return rows.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> getPaymentMethodBreakdown(
      String startDate, String endDate) async {
    final visits = await _visitsInRange(startDate, endDate);
    final totals = <String, double>{};
    for (final visit in visits) {
      final doc = await _scope
          .collection(FirestoreCollectionNames.visits)
          .where('id', isEqualTo: visit.id)
          .limit(1)
          .get();
      if (doc.docs.isEmpty) continue;
      final payments = await doc.docs.first.reference.collection('payments').get();
      for (final paymentDoc in payments.docs) {
        final payment = Payment.fromMap(FirestoreModelCodec.withDocumentId(paymentDoc));
        totals[payment.paymentMethod.dbValue] =
            (totals[payment.paymentMethod.dbValue] ?? 0) + payment.amount;
      }
    }
    return totals.entries
        .map((e) => {'payment_method': e.key, 'total': e.value})
        .toList();
  }

  Future<List<Map<String, dynamic>>> getTopCustomers(
    String startDate,
    String endDate, {
    String orderBy = 'revenue',
    int limit = 20,
  }) async {
    final visits = await _visitsInRange(startDate, endDate);
    final map = <int, Map<String, dynamic>>{};
    for (final visit in visits) {
      final row = map.putIfAbsent(
        visit.customerId,
        () => {
          'id': visit.customerId,
          'name': visit.customerName ?? 'Customer #${visit.customerId}',
          'visit_count': 0,
          'gross': 0.0,
          'discount': 0.0,
          'revenue': 0.0,
          'collected': 0.0,
          'pending': 0.0,
          'written_off': 0.0,
          'last_visit': null,
        },
      );
      row['visit_count'] = (row['visit_count'] as int) + 1;
      row['gross'] = (row['gross'] as double) + visit.subtotal;
      row['discount'] = (row['discount'] as double) + visit.discountAmount;
      row['revenue'] = (row['revenue'] as double) + visit.finalTotal;
      row['collected'] = (row['collected'] as double) + visit.totalPaid;
      row['pending'] = (row['pending'] as double) + visit.pendingAmount;
      if (visit.paymentStatus == PaymentStatus.writtenOff) {
        row['written_off'] = (row['written_off'] as double) + await _writtenOffForVisit(visit.id);
      }
      final lastVisit = row['last_visit'] as String?;
      if (lastVisit == null || visit.visitDate.compareTo(lastVisit) > 0) {
        row['last_visit'] = visit.visitDate;
      }
    }
    final rows = map.values.toList();
    rows.sort((a, b) {
      final key = orderBy == 'visits' ? 'visit_count' : orderBy;
      if (key == 'last_visit') {
        final av = (a[key] as String?) ?? '';
        final bv = (b[key] as String?) ?? '';
        return bv.compareTo(av);
      }
      return (b[key] as num).compareTo(a[key] as num);
    });
    return rows.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> getExpenseByCategory(
      String startDate, String endDate) async {
    final categories = await _scope.collection(FirestoreCollectionNames.expenseCategories).get();
    final names = {
      for (final d in categories.docs)
        (d.data()['id'] as int?): (d.data()['name'] ?? '').toString(),
    };
    final expenses = await _scope
        .collection(FirestoreCollectionNames.expenses)
        .where('expense_date', isGreaterThanOrEqualTo: startDate)
        .where('expense_date', isLessThan: endDate)
        .get();

    final totals = <int, double>{};
    for (final d in expenses.docs) {
      final expense = Expense.fromMap(FirestoreModelCodec.withDocumentId(d));
      totals[expense.expenseCategoryId] =
          (totals[expense.expenseCategoryId] ?? 0) + expense.amount;
    }
    return totals.entries
        .map((e) => {'name': names[e.key] ?? 'Category #${e.key}', 'total': e.value})
        .toList();
  }

  Future<List<Map<String, dynamic>>> getBirthdaysInRange(
      String mmddStart, String mmddEnd) async {
    final snap = await _scope.collection(FirestoreCollectionNames.customers).where('is_active', isEqualTo: 1).get();
    final rows = <Map<String, dynamic>>[];
    for (final d in snap.docs) {
      final customer = Customer.fromMap(FirestoreModelCodec.withDocumentId(d));
      final birth = customer.birthDate;
      if (birth == null || birth.length < 10) continue;
      final mmdd = birth.substring(5, 10);
      if (mmdd.compareTo(mmddStart) >= 0 && mmdd.compareTo(mmddEnd) <= 0) {
        rows.add({
          'name': customer.name,
          'phone': customer.phone,
          'birth_date': birth,
          'mm_dd': mmdd,
        });
      }
    }
    rows.sort((a, b) => (a['mm_dd'] as String).compareTo(b['mm_dd'] as String));
    return rows;
  }

  Future<Map<String, dynamic>> getAppointmentStats(
      String startDate, String endDate) async {
    final snap = await _scope
        .collection(FirestoreCollectionNames.appointments)
        .where('appointment_date', isGreaterThanOrEqualTo: startDate)
        .where('appointment_date', isLessThan: endDate)
        .get();
    int pending = 0, completed = 0, notAttended = 0, cancelled = 0;
    for (final d in snap.docs) {
      final a = Appointment.fromMap(FirestoreModelCodec.withDocumentId(d));
      switch (a.status) {
        case AppointmentStatus.pending:
          pending++;
          break;
        case AppointmentStatus.completed:
          completed++;
          break;
        case AppointmentStatus.notAttended:
          notAttended++;
          break;
        case AppointmentStatus.cancelled:
          cancelled++;
          break;
      }
    }
    final total = pending + completed + notAttended + cancelled;
    final resolved = completed + notAttended + cancelled;
    return {
      'total_appointments': total,
      'pending_count': pending,
      'completed_count': completed,
      'not_attended_count': notAttended,
      'cancelled_count': cancelled,
      'completion_rate': total == 0 ? 0.0 : completed / total,
      'resolved_completion_rate': resolved == 0 ? 0.0 : completed / resolved,
      'cancellation_rate': total == 0 ? 0.0 : cancelled / total,
    };
  }
}
