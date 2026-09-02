import 'package:flutter/foundation.dart';
import '../database/database.dart';
import '../utils/formatters.dart';

class DashboardProvider extends ChangeNotifier {
  final _reportDao = ReportDao();

  Map<String, dynamic> _todayStats = {};
  Map<String, dynamic> _monthStats = {};
  List<Map<String, dynamic>> _salesTrend = [];
  List<Map<String, dynamic>> _topServices = [];
  List<Map<String, dynamic>> _paymentBreakdown = [];
  bool _isLoading = false;

  Map<String, dynamic> get todayStats => _todayStats;
  Map<String, dynamic> get monthStats => _monthStats;
  List<Map<String, dynamic>> get salesTrend => _salesTrend;
  List<Map<String, dynamic>> get topServices => _topServices;
  List<Map<String, dynamic>> get paymentBreakdown => _paymentBreakdown;
  bool get isLoading => _isLoading;

  Future<void> loadDashboard() async {
    _isLoading = true;
    notifyListeners();

    final today = DateRange.today();
    final month = DateRange.thisMonth();

    _todayStats = await _reportDao.getDashboardStats(
      today.start.toIso8601String(),
      today.endExclusive.toIso8601String(),
    );
    _monthStats = await _reportDao.getDashboardStats(
      month.start.toIso8601String(),
      month.endExclusive.toIso8601String(),
    );
    _salesTrend = await _reportDao.getDailySalesTrend(
      month.start.toIso8601String(),
      month.endExclusive.toIso8601String(),
    );
    _topServices = await _reportDao.getTopServices(
      month.start.toIso8601String(),
      month.endExclusive.toIso8601String(),
      limit: 5,
    );
    _paymentBreakdown = await _reportDao.getPaymentMethodBreakdown(
      month.start.toIso8601String(),
      month.endExclusive.toIso8601String(),
    );

    _isLoading = false;
    notifyListeners();
  }
}
