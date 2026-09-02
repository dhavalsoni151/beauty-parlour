import 'package:flutter/foundation.dart';
import '../database/database.dart';
import '../models/customer_models.dart';

class CustomerProvider extends ChangeNotifier {
  final _customerDao = CustomerDao();
  final _reportDao = ReportDao();

  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  bool _isLoading = false;
  String _searchQuery = '';

  List<Customer> get customers => _filteredCustomers;
  List<Customer> get allCustomers => _customers;
  bool get isLoading => _isLoading;

  Future<void> loadCustomers({bool activeOnly = true}) async {
    _isLoading = true;
    notifyListeners();
    _customers = await _customerDao.getAll(activeOnly: activeOnly);
    _applyFilter();
    _isLoading = false;
    notifyListeners();
  }

  void search(String query) {
    _searchQuery = query;
    _applyFilter();
    notifyListeners();
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredCustomers = List.from(_customers);
    } else {
      final q = _searchQuery.toLowerCase();
      _filteredCustomers = _customers
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              (c.phone?.contains(q) ?? false))
          .toList();
    }
  }

  Future<Customer?> getCustomer(int id) async {
    return _customerDao.get(id);
  }

  Future<List<Customer>> searchCustomers(String query) async {
    if (query.isEmpty) return _customers;
    return _customerDao.search(query);
  }

  Future<int> addCustomer(Customer customer) async {
    final id = await _customerDao.insert(customer);
    await loadCustomers();
    return id;
  }

  Future<void> updateCustomer(Customer customer) async {
    await _customerDao.update(customer);
    await loadCustomers();
  }

  Future<void> deactivateCustomer(int id) async {
    final customer = await _customerDao.get(id);
    if (customer != null) {
      await _customerDao.update(customer.copyWith(isActive: false));
      await loadCustomers();
    }
  }

  Future<Map<String, dynamic>> getCustomerStats(int id) async {
    return _reportDao.getCustomerStats(id);
  }
}
