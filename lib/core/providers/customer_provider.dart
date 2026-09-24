import 'dart:async';

import 'package:flutter/foundation.dart';

import '../firebase/firebase_service.dart';
import '../firestore/firestore_repositories.dart';
import '../models/customer_models.dart';
import 'firebase_startup_provider.dart';

class CustomerProvider extends ChangeNotifier {
  final FirestoreCustomerRepository _repository = FirestoreCustomerRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );

  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  bool _isLoading = false;
  String _searchQuery = '';
  bool _activeOnly = true;
  StreamSubscription<List<Customer>>? _subscription;

  List<Customer> get customers => _filteredCustomers;
  List<Customer> get allCustomers => _customers;
  bool get isLoading => _isLoading;

  Future<void> loadCustomers({bool activeOnly = true}) async {
    _activeOnly = activeOnly;
    _isLoading = true;
    notifyListeners();
    await _subscription?.cancel();
    _subscription = _repository.watchAll(activeOnly: activeOnly).listen((items) {
      _customers = items;
      _applyFilter();
      _isLoading = false;
      notifyListeners();
    });
  }

  void search(String query) {
    _searchQuery = query;
    _applyFilter();
    notifyListeners();
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredCustomers = List.from(_customers);
      return;
    }
    final q = _searchQuery.toLowerCase();
    _filteredCustomers = _customers
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            (c.phone?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  Future<Customer?> getCustomer(int id) => _repository.get(id);

  Future<List<Customer>> searchCustomers(String query) async {
    if (query.isEmpty) return _customers;
    final q = query.toLowerCase();
    return _customers
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            (c.phone?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  Future<int> addCustomer(Customer customer) => _repository.save(customer);

  Future<void> updateCustomer(Customer customer) => _repository.save(customer);

  Future<void> deactivateCustomer(int id) async {
    await _repository.deactivate(id);
    if (!_activeOnly) {
      await loadCustomers(activeOnly: false);
    }
  }

  Future<Map<String, dynamic>> getCustomerStats(int id) async {
    final visitsSnapshot = await FirebaseService.instance.firestore
        .collection('organizations')
        .doc(firebaseOrganizationId)
        .collection(FirestoreCollectionNames.visits)
        .where('customer_id', isEqualTo: id)
        .get();

    double totalBilled = 0;
    double totalPaid = 0;
    double totalPending = 0;
    String? firstVisit;
    String? lastVisit;
    for (final doc in visitsSnapshot.docs) {
      final data = doc.data();
      totalBilled += (data['final_total'] as num? ?? 0).toDouble();
      totalPaid += (data['total_paid'] as num? ?? 0).toDouble();
      totalPending += (data['pending_amount'] as num? ?? 0).toDouble();
      final visitDate = data['visit_date'] as String?;
      if (visitDate != null && (lastVisit == null || visitDate.compareTo(lastVisit) > 0)) {
        lastVisit = visitDate;
      }
      if (visitDate != null && (firstVisit == null || visitDate.compareTo(firstVisit) < 0)) {
        firstVisit = visitDate;
      }
    }

    return {
      'customer_id': id,
      'total_visits': visitsSnapshot.docs.length,
      'total_billed': totalBilled,
      'total_paid': totalPaid,
      'total_pending': totalPending,
      'first_visit': firstVisit,
      'last_visit': lastVisit,
    };
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
