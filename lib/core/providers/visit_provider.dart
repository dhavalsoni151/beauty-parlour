import 'dart:async';

import 'package:flutter/foundation.dart';

import '../firebase/firebase_service.dart';
import '../firestore/firestore_repositories.dart';
import '../models/visit_models.dart';
import '../utils/formatters.dart';
import 'firebase_startup_provider.dart';

class VisitProvider extends ChangeNotifier {
  final FirestoreVisitRepository _repository = FirestoreVisitRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );
  final FirestoreExpenseRepository _expenseRepository = FirestoreExpenseRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );

  List<Visit> _visits = [];
  List<Visit> _pendingVisits = [];
  bool _isLoading = false;
  StreamSubscription<List<Visit>>? _visitsSub;
  StreamSubscription<List<Visit>>? _pendingSub;

  List<Visit> get visits => _visits;
  List<Visit> get pendingVisits => _pendingVisits;
  bool get isLoading => _isLoading;

  Future<void> loadVisits(
      {int? customerId, String? startDate, String? endDate}) async {
    _isLoading = true;
    notifyListeners();
    await _visitsSub?.cancel();
    _visitsSub = _repository.watchVisits().listen((items) {
      _visits = items.where((visit) {
        if (customerId != null && visit.customerId != customerId) return false;
        if (startDate != null && visit.visitDate.compareTo(startDate) < 0) {
          return false;
        }
        if (endDate != null && visit.visitDate.compareTo(endDate) >= 0) {
          return false;
        }
        return true;
      }).toList();
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> loadPendingVisits() async {
    await _pendingSub?.cancel();
    _pendingSub = _repository.watchPendingVisits().listen((items) {
      _pendingVisits = items;
      notifyListeners();
    });
  }

  Future<Visit?> getVisit(int id) => _repository.get(id);

  Future<List<Visit>> getVisitsForCustomer(int customerId) =>
      _repository.listVisits(customerId: customerId);

  Future<int> saveVisit(
      Visit visit, List<VisitService> services, List<Payment> payments) async {
    return _repository.save(visit, services, payments);
  }

  Future<void> updateVisit(Visit visit, List<VisitService> services) async {
    await _repository.updateVisit(visit, services);
  }

  Future<void> recordPayment(
      int visitId, Payment payment, double newTotalPaid, double newPending) async {
    final status = _calculateStatus(newTotalPaid, newPending);
    await _repository.recordPayment(
      visitId,
      payment,
      newTotalPaid,
      newPending,
      status,
    );
  }

  Future<void> writeOffVisit(
      int visitId, WriteOff writeOff, double newPending) async {
    await _repository.writeOff(visitId, writeOff, pendingAmount: newPending);
  }

  PaymentStatus _calculateStatus(double totalPaid, double pending) {
    if (pending <= 0) return PaymentStatus.paid;
    if (totalPaid > 0) return PaymentStatus.partiallyPaid;
    return PaymentStatus.pending;
  }

  Future<List<Map<String, dynamic>>> getDailySalesTrend(DateRange range) async {
    final byDate = <String, double>{};
    for (final visit in _inRange(range)) {
      final date = visit.visitDate.substring(0, 10);
      byDate[date] = (byDate[date] ?? 0) + visit.finalTotal;
    }
    return byDate.entries
        .map((e) => {'date': e.key, 'revenue': e.value})
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  }

  Future<List<Map<String, dynamic>>> getTopServices(DateRange range,
      {String? categoryName,
      String? serviceTypeName,
      bool serviceTypeIsNull = false,
      String sort = 'revenue',
      int limit = 20}) async {
    final metrics = <String, Map<String, dynamic>>{};
    for (final visit in _inRange(range)) {
      final full = await _repository.get(visit.id!);
      if (full == null) continue;
      for (final item in full.services) {
        if (categoryName != null && item.categoryNameSnapshot != categoryName) {
          continue;
        }
        if (serviceTypeName != null &&
            item.serviceTypeNameSnapshot != serviceTypeName) {
          continue;
        }
        if (serviceTypeIsNull && item.serviceTypeNameSnapshot != null) continue;
        final key = item.pathLabel;
        final row = metrics.putIfAbsent(
          key,
          () => {
            'service_name': item.serviceNameSnapshot,
            'category_name': item.categoryNameSnapshot,
            'service_type_name': item.serviceTypeNameSnapshot,
            'transactions': 0,
            'visits': 0,
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
    final rows = metrics.values.toList();
    for (final row in rows) {
      final quantity = row['quantity'] as int;
      row['avg_price'] = quantity == 0 ? 0.0 : (row['revenue'] as double) / quantity;
    }
    rows.sort((a, b) => (b[sort] as num).compareTo(a[sort] as num));
    return rows.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> getTopCategories(DateRange range,
      {String sort = 'revenue', int limit = 50}) async {
    final metrics = <String, Map<String, dynamic>>{};
    for (final visit in _inRange(range)) {
      final full = await _repository.get(visit.id!);
      if (full == null) continue;
      for (final item in full.services) {
        final key = item.categoryNameSnapshot;
        final row = metrics.putIfAbsent(
          key,
          () => {'category_name': key, 'revenue': 0.0, 'quantity': 0},
        );
        row['revenue'] = (row['revenue'] as double) + item.total;
        row['quantity'] = (row['quantity'] as int) + item.quantity;
      }
    }
    final rows = metrics.values.toList();
    rows.sort((a, b) => (b[sort] as num).compareTo(a[sort] as num));
    return rows.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> getTopServiceTypes(
      DateRange range, String categoryName,
      {String sort = 'revenue', int limit = 50}) async {
    final metrics = <String, Map<String, dynamic>>{};
    for (final visit in _inRange(range)) {
      final full = await _repository.get(visit.id!);
      if (full == null) continue;
      for (final item in full.services.where((i) => i.categoryNameSnapshot == categoryName)) {
        final key = item.serviceTypeNameSnapshot ?? '(Direct)';
        final row = metrics.putIfAbsent(
          key,
          () => {'service_type_name': key, 'revenue': 0.0, 'quantity': 0},
        );
        row['revenue'] = (row['revenue'] as double) + item.total;
        row['quantity'] = (row['quantity'] as int) + item.quantity;
      }
    }
    final rows = metrics.values.toList();
    rows.sort((a, b) => (b[sort] as num).compareTo(a[sort] as num));
    return rows.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> getPaymentMethodBreakdown(DateRange range) async {
    final out = <String, double>{};
    for (final visit in _inRange(range)) {
      final full = await _repository.get(visit.id!);
      if (full == null) continue;
      for (final p in full.payments) {
        out[p.paymentMethod.dbValue] = (out[p.paymentMethod.dbValue] ?? 0) + p.amount;
      }
    }
    return out.entries.map((e) => {'payment_method': e.key, 'amount': e.value}).toList();
  }

  Future<List<Map<String, dynamic>>> getTopCustomers(DateRange range,
      {String orderBy = 'revenue', int limit = 20}) async {
    final out = <int, Map<String, dynamic>>{};
    for (final visit in _inRange(range)) {
      final row = out.putIfAbsent(
        visit.customerId,
        () => {
          'customer_id': visit.customerId,
          'customer_name': visit.customerName ?? 'Customer #${visit.customerId}',
          'visits': 0,
          'revenue': 0.0,
        },
      );
      row['visits'] = (row['visits'] as int) + 1;
      row['revenue'] = (row['revenue'] as double) + visit.finalTotal;
    }
    final rows = out.values.toList();
    rows.sort((a, b) => (b[orderBy] as num).compareTo(a[orderBy] as num));
    return rows.take(limit).toList();
  }

  Future<Map<String, dynamic>> getDashboardStats(DateRange range) async {
    final inRange = _inRange(range);
    final revenue = inRange.fold<double>(0, (s, v) => s + v.finalTotal);
    final pending = inRange.fold<double>(0, (s, v) => s + v.pendingAmount);
    return {
      'visits': inRange.length,
      'revenue': revenue,
      'pending_amount': pending,
    };
  }

  Future<List<Map<String, dynamic>>> getExpenseByCategory(DateRange range) async {
    final expenses = await _expenseRepository.watchExpenses().first;
    final categories = await _expenseRepository.watchCategories().first;
    final categoryNameById = {for (final c in categories) c.id: c.name};
    final totals = <int, double>{};
    for (final expense in expenses) {
      final date = DateTime.tryParse(expense.expenseDate);
      if (date == null) continue;
      if (date.isBefore(range.start) || !date.isBefore(range.endExclusive)) {
        continue;
      }
      totals[expense.expenseCategoryId] =
          (totals[expense.expenseCategoryId] ?? 0) + expense.amount;
    }
    return totals.entries
        .map((e) => {
              'category_name': categoryNameById[e.key] ?? 'Category #${e.key}',
              'amount': e.value,
            })
        .toList();
  }

  List<Visit> _inRange(DateRange range) {
    final start = range.start;
    final end = range.endExclusive;
    return _visits.where((visit) {
      final date = DateTime.tryParse(visit.visitDate);
      if (date == null) return false;
      return !date.isBefore(start) && date.isBefore(end);
    }).toList();
  }

  @override
  void dispose() {
    _visitsSub?.cancel();
    _pendingSub?.cancel();
    super.dispose();
  }
}
