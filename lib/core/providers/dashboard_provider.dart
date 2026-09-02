import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../utils/formatters.dart';

class DashboardProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;
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

    _todayStats = await _db.getDashboardStats(
      today.start.toIso8601String(),
      today.end.toIso8601String(),
    );
    _monthStats = await _db.getDashboardStats(
      month.start.toIso8601String(),
      month.end.toIso8601String(),
    );
    _salesTrend = await _db.getDailySalesTrend(
      month.start.toIso8601String(),
      month.end.toIso8601String(),
    );
    _topServices = await _db.getTopServices(
      month.start.toIso8601String(),
      month.end.toIso8601String(),
      limit: 5,
    );
    _paymentBreakdown = await _db.getPaymentMethodBreakdown(
      month.start.toIso8601String(),
      month.end.toIso8601String(),
    );

    _isLoading = false;
    notifyListeners();
  }
}
