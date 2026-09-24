import 'dart:async';

import 'package:flutter/foundation.dart';

import '../firebase/firebase_service.dart';
import '../firestore/firestore_repositories.dart';
import '../models/visit_models.dart';
import '../utils/formatters.dart';
import 'firebase_startup_provider.dart';

class DashboardProvider extends ChangeNotifier {
  final FirestoreVisitRepository _visitRepository = FirestoreVisitRepository(
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

  Map<String, dynamic> _todayStats = {};
  Map<String, dynamic> _monthStats = {};
  List<Map<String, dynamic>> _salesTrend = [];
  List<Map<String, dynamic>> _topServices = [];
  List<Map<String, dynamic>> _paymentBreakdown = [];
  Map<String, dynamic> _monthPackageStats = {};
  bool _isLoading = false;

  List<Visit> _visits = [];
  List<Expense> _expenses = [];
  StreamSubscription<List<Visit>>? _visitSub;
  StreamSubscription<List<Expense>>? _expenseSub;

  Map<String, dynamic> get todayStats => _todayStats;
  Map<String, dynamic> get monthStats => _monthStats;
  List<Map<String, dynamic>> get salesTrend => _salesTrend;
  List<Map<String, dynamic>> get topServices => _topServices;
  List<Map<String, dynamic>> get paymentBreakdown => _paymentBreakdown;
  Map<String, dynamic> get monthPackageStats => _monthPackageStats;
  bool get isLoading => _isLoading;

  Future<void> loadDashboard() async {
    _isLoading = true;
    notifyListeners();

    await _visitSub?.cancel();
    await _expenseSub?.cancel();

    _visitSub = _visitRepository.watchVisits().listen((visits) async {
      _visits = visits;
      await _recalculate();
    });
    _expenseSub = _expenseRepository.watchExpenses().listen((expenses) async {
      _expenses = expenses;
      await _recalculate();
    });
  }

  Future<void> _recalculate() async {
    final today = DateRange.today();
    final month = DateRange.thisMonth();
    final todayVisits = _visits.where((v) => _inRange(v.visitDate, today)).toList();
    final monthVisits = _visits.where((v) => _inRange(v.visitDate, month)).toList();

    _todayStats = {
      'visits': todayVisits.length,
      'revenue': todayVisits.fold<double>(0, (s, v) => s + v.finalTotal),
      'pending_amount': todayVisits.fold<double>(0, (s, v) => s + v.pendingAmount),
    };

    final monthExpenses = _expenses.where((e) => _inRange(e.expenseDate, month)).toList();
    _monthStats = {
      'visits': monthVisits.length,
      'revenue': monthVisits.fold<double>(0, (s, v) => s + v.finalTotal),
      'pending_amount': monthVisits.fold<double>(0, (s, v) => s + v.pendingAmount),
      'expenses': monthExpenses.fold<double>(0, (s, e) => s + e.amount),
    };

    final trend = <String, double>{};
    for (final visit in monthVisits) {
      final day = visit.visitDate.substring(0, 10);
      trend[day] = (trend[day] ?? 0) + visit.finalTotal;
    }
    _salesTrend = trend.entries
        .map((e) => {'date': e.key, 'revenue': e.value})
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    final top = <String, Map<String, dynamic>>{};
    for (final visit in monthVisits) {
      final full = await _visitRepository.get(visit.id!);
      if (full == null) continue;
      for (final service in full.services) {
        final key = service.pathLabel;
        final row = top.putIfAbsent(
          key,
          () => {
            'service_name': service.serviceNameSnapshot,
            'transactions': 0,
            'visits': 0,
            'quantity': 0,
            'revenue': 0.0,
            'avg_price': 0.0,
          },
        );
        row['transactions'] = (row['transactions'] as int) + 1;
        row['visits'] = (row['visits'] as int) + 1;
        row['quantity'] = (row['quantity'] as int) + service.quantity;
        row['revenue'] = (row['revenue'] as double) + service.total;
      }
    }
    _topServices = top.values.toList()
      ..forEach((row) {
        final q = row['quantity'] as int;
        row['avg_price'] = q == 0 ? 0.0 : (row['revenue'] as double) / q;
      })
      ..sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));
    if (_topServices.length > 5) {
      _topServices = _topServices.take(5).toList();
    }

    final payment = <String, double>{};
    for (final visit in monthVisits) {
      final full = await _visitRepository.get(visit.id!);
      if (full == null) continue;
      for (final p in full.payments) {
        payment[p.paymentMethod.dbValue] =
            (payment[p.paymentMethod.dbValue] ?? 0) + p.amount;
      }
    }
    _paymentBreakdown = payment.entries
        .map((e) => {'payment_method': e.key, 'amount': e.value})
        .toList();

    final packageVisits = monthVisits.where((v) => v.packageId != null).toList();
    _monthPackageStats = {
      'packages_sold': packageVisits.length,
      'package_revenue': packageVisits.fold<double>(0, (s, v) => s + (v.packagePrice ?? 0)),
      'package_discount': packageVisits.fold<double>(0, (s, v) => s + (v.packageDiscount ?? 0)),
    };

    _isLoading = false;
    notifyListeners();
  }

  bool _inRange(String iso, DateRange range) {
    final date = DateTime.tryParse(iso);
    if (date == null) return false;
    return !date.isBefore(range.start) && date.isBefore(range.endExclusive);
  }

  @override
  void dispose() {
    _visitSub?.cancel();
    _expenseSub?.cancel();
    super.dispose();
  }
}
