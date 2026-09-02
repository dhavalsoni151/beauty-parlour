import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/visit_models.dart';
import '../utils/formatters.dart';

class VisitProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;
  List<Visit> _visits = [];
  List<Visit> _pendingVisits = [];
  bool _isLoading = false;

  List<Visit> get visits => _visits;
  List<Visit> get pendingVisits => _pendingVisits;
  bool get isLoading => _isLoading;

  Future<void> loadVisits({int? customerId, String? startDate, String? endDate}) async {
    _isLoading = true;
    notifyListeners();
    _visits = await _db.getVisits(
      customerId: customerId,
      startDate: startDate,
      endDate: endDate,
    );
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadPendingVisits() async {
    _pendingVisits = await _db.getPendingVisits();
    notifyListeners();
  }

  Future<Visit?> getVisit(int id) async {
    return await _db.getVisit(id);
  }

  Future<List<Visit>> getVisitsForCustomer(int customerId) async {
    return await _db.getVisits(customerId: customerId);
  }

  Future<int> saveVisit(Visit visit, List<VisitService> services, List<Payment> payments) async {
    final id = await _db.insertVisit(visit, services, payments);
    await loadVisits();
    return id;
  }

  Future<void> recordPayment(int visitId, Payment payment, double newTotalPaid, double newPending) async {
    await _db.insertPayment(payment);
    final status = _calculateStatus(newTotalPaid, newPending);
    await _db.updateVisitPayment(visitId, newTotalPaid, newPending, status.dbValue);
    await loadVisits();
    await loadPendingVisits();
    notifyListeners();
  }

  Future<void> writeOffVisit(int visitId, WriteOff writeOff, double newPending) async {
    await _db.insertWriteOff(writeOff);
    await _db.updateVisitPayment(visitId, writeOff.amount == 0 ? 0 : writeOff.amount, 0, PaymentStatus.writtenOff.dbValue);
    await loadPendingVisits();
    notifyListeners();
  }

  PaymentStatus _calculateStatus(double totalPaid, double pending) {
    if (pending <= 0) return PaymentStatus.paid;
    if (totalPaid > 0) return PaymentStatus.partiallyPaid;
    return PaymentStatus.pending;
  }

  Future<List<Map<String, dynamic>>> getDailySalesTrend(DateRange range) async {
    return await _db.getDailySalesTrend(
      range.start.toIso8601String(),
      range.end.toIso8601String(),
    );
  }

  Future<List<Map<String, dynamic>>> getTopServices(DateRange range) async {
    return await _db.getTopServices(
      range.start.toIso8601String(),
      range.end.toIso8601String(),
    );
  }

  Future<List<Map<String, dynamic>>> getTopCategories(DateRange range) async {
    return await _db.getTopCategories(
      range.start.toIso8601String(),
      range.end.toIso8601String(),
    );
  }

  Future<List<Map<String, dynamic>>> getPaymentMethodBreakdown(DateRange range) async {
    return await _db.getPaymentMethodBreakdown(
      range.start.toIso8601String(),
      range.end.toIso8601String(),
    );
  }

  Future<List<Map<String, dynamic>>> getTopCustomers(DateRange range, {String orderBy = 'revenue'}) async {
    return await _db.getTopCustomers(
      range.start.toIso8601String(),
      range.end.toIso8601String(),
      orderBy: orderBy,
    );
  }
}
