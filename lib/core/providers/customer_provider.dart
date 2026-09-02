import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/customer_models.dart';

class CustomerProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;
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
    _customers = await _db.getCustomers(activeOnly: activeOnly);
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
      _filteredCustomers = _customers.where((c) =>
        c.name.toLowerCase().contains(q) ||
        (c.phone?.contains(q) ?? false)
      ).toList();
    }
  }

  Future<Customer?> getCustomer(int id) async {
    return await _db.getCustomer(id);
  }

  Future<List<Customer>> searchCustomers(String query) async {
    if (query.isEmpty) return _customers;
    return await _db.searchCustomers(query);
  }

  Future<int> addCustomer(Customer customer) async {
    final id = await _db.insertCustomer(customer);
    await loadCustomers();
    return id;
  }

  Future<void> updateCustomer(Customer customer) async {
    await _db.updateCustomer(customer);
    await loadCustomers();
  }

  Future<void> deactivateCustomer(int id) async {
    final customer = await _db.getCustomer(id);
    if (customer != null) {
      await _db.updateCustomer(customer.copyWith(isActive: false));
      await loadCustomers();
    }
  }

  Future<Map<String, dynamic>> getCustomerStats(int id) async {
    return await _db.getCustomerStats(id);
  }
}
