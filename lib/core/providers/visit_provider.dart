import 'package:flutter/foundation.dart';
import '../database/database.dart';
import '../models/visit_models.dart';
import '../utils/formatters.dart';

class VisitProvider extends ChangeNotifier {
  final _visitDao = VisitDao();
  final _paymentDao = PaymentDao();
  final _writeOffDao = WriteOffDao();
  final _reportDao = ReportDao();

  List<Visit> _visits = [];
  List<Visit> _pendingVisits = [];
  bool _isLoading = false;

  List<Visit> get visits => _visits;
  List<Visit> get pendingVisits => _pendingVisits;
  bool get isLoading => _isLoading;

  Future<void> loadVisits(
      {int? customerId, String? startDate, String? endDate}) async {
    _isLoading = true;
    notifyListeners();
    _visits = await _visitDao.getVisits(
      customerId: customerId,
      startDate: startDate,
      endDate: endDate,
    );
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadPendingVisits() async {
    _pendingVisits = await _visitDao.getPendingVisits();
    notifyListeners();
  }

  Future<Visit?> getVisit(int id) async {
    return _visitDao.get(id);
  }

  Future<List<Visit>> getVisitsForCustomer(int customerId) async {
    return _visitDao.getVisits(customerId: customerId);
  }

  Future<int> saveVisit(
      Visit visit, List<VisitService> services, List<Payment> payments) async {
    final id = await _visitDao.insertVisit(visit, services, payments);
    await loadVisits();
    return id;
  }

  Future<void> recordPayment(
      int visitId, Payment payment, double newTotalPaid, double newPending) async {
    await _paymentDao.insert(payment);
    final status = _calculateStatus(newTotalPaid, newPending);
    await _visitDao.updateVisitPayment(
        visitId, newTotalPaid, newPending, status.dbValue);
    await loadVisits();
    await loadPendingVisits();
    notifyListeners();
  }

  Future<void> writeOffVisit(
      int visitId, WriteOff writeOff, double newPending) async {
    await _writeOffDao.insert(writeOff);
    // The visit's own paid total is unchanged; the pending balance is cleared
    // and the status becomes WRITTEN_OFF. Written-off amounts are tracked in
    // the write_offs table and never counted as collected cash.
    final visit = await _visitDao.get(visitId);
    final totalPaid = visit?.totalPaid ?? 0;
    await _visitDao.updateVisitPayment(
        visitId, totalPaid, 0, PaymentStatus.writtenOff.dbValue);
    await loadPendingVisits();
    notifyListeners();
  }

  PaymentStatus _calculateStatus(double totalPaid, double pending) {
    if (pending <= 0) return PaymentStatus.paid;
    if (totalPaid > 0) return PaymentStatus.partiallyPaid;
    return PaymentStatus.pending;
  }

  // ── Report passthroughs (used by dashboards/report screens) ────────────────

  Future<List<Map<String, dynamic>>> getDailySalesTrend(DateRange range) {
    return _reportDao.getDailySalesTrend(
        range.start.toIso8601String(), range.endExclusive.toIso8601String());
  }

  Future<List<Map<String, dynamic>>> getTopServices(DateRange range,
      {String? categoryName,
      String? serviceTypeName,
      bool serviceTypeIsNull = false,
      String sort = 'revenue',
      int limit = 20}) {
    return _reportDao.getTopServices(
      range.start.toIso8601String(),
      range.endExclusive.toIso8601String(),
      categoryName: categoryName,
      serviceTypeName: serviceTypeName,
      serviceTypeIsNull: serviceTypeIsNull,
      sort: sort,
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getTopCategories(DateRange range,
      {String sort = 'revenue', int limit = 50}) {
    return _reportDao.getTopCategories(
      range.start.toIso8601String(),
      range.endExclusive.toIso8601String(),
      sort: sort,
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getTopServiceTypes(
      DateRange range, String categoryName,
      {String sort = 'revenue', int limit = 50}) {
    return _reportDao.getTopServiceTypes(
      range.start.toIso8601String(),
      range.endExclusive.toIso8601String(),
      categoryName: categoryName,
      sort: sort,
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getPaymentMethodBreakdown(DateRange range) {
    return _reportDao.getPaymentMethodBreakdown(
        range.start.toIso8601String(), range.endExclusive.toIso8601String());
  }

  Future<List<Map<String, dynamic>>> getTopCustomers(DateRange range,
      {String orderBy = 'revenue', int limit = 20}) {
    return _reportDao.getTopCustomers(
      range.start.toIso8601String(),
      range.endExclusive.toIso8601String(),
      orderBy: orderBy,
      limit: limit,
    );
  }

  Future<Map<String, dynamic>> getDashboardStats(DateRange range) {
    return _reportDao.getDashboardStats(
        range.start.toIso8601String(), range.endExclusive.toIso8601String());
  }

  Future<List<Map<String, dynamic>>> getExpenseByCategory(DateRange range) {
    return _reportDao.getExpenseByCategory(
        range.start.toIso8601String(), range.endExclusive.toIso8601String());
  }
}
