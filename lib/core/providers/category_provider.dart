import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;

import '../database/daos/db_exceptions.dart';
import '../firebase/firebase_service.dart';
import '../firestore/firestore_repositories.dart';
import '../models/customer_models.dart';
import 'firebase_startup_provider.dart';

class CategoryProvider extends ChangeNotifier {
  final FirestoreCatalogRepository _repository = FirestoreCatalogRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );

  List<Category> _categories = [];
  bool _isLoading = false;

  final Map<int, List<ServiceType>> _serviceTypesByCategory = {};
  List<ServiceType> _allServiceTypes = [];
  List<Service> _allServices = [];

  StreamSubscription<List<Category>>? _categorySub;
  StreamSubscription<List<ServiceType>>? _serviceTypeSub;
  StreamSubscription<List<Service>>? _servicesSub;

  List<Category> get categories => _categories;
  List<Category> get activeCategories =>
      _categories.where((c) => c.isActive).toList();
  bool get isLoading => _isLoading;

  Future<void> loadCategories() async {
    _isLoading = true;
    notifyListeners();
    await _categorySub?.cancel();
    await _serviceTypeSub?.cancel();
    await _servicesSub?.cancel();

    _categorySub = _repository.watchCategories().listen((items) {
      _categories = items;
      _isLoading = false;
      notifyListeners();
    });

    _serviceTypeSub = _repository.watchServiceTypes().listen((items) {
      _allServiceTypes = items;
      _serviceTypesByCategory
        ..clear()
        ..addEntries(_groupServiceTypes(items).entries);
      notifyListeners();
    });

    _servicesSub = _repository.watchServices().listen((items) {
      _allServices = items;
    });
  }

  Map<int, List<ServiceType>> _groupServiceTypes(List<ServiceType> items) {
    final map = <int, List<ServiceType>>{};
    for (final type in items) {
      map.putIfAbsent(type.categoryId, () => []).add(type);
    }
    return map;
  }

  Future<void> addCategory(Category category) => _repository.saveCategory(category);

  Future<void> updateCategory(Category category) =>
      _repository.saveCategory(category);

  Future<void> toggleActive(Category category) =>
      _repository.saveCategory(category.copyWith(isActive: !category.isActive));

  Future<void> deleteCategory(Category category) async {
    if (_allServiceTypes.any((t) => t.categoryId == category.id) ||
        _allServices.any((s) => s.categoryId == category.id)) {
      throw const InUseException('Category has dependent service data attached.');
    }
    await _repository.deleteCategory(category.id!);
  }

  Future<void> updateDisplayOrder(int id, int displayOrder) async {
    final current = _categories.firstWhere((c) => c.id == id);
    await _repository.saveCategory(current.copyWith(displayOrder: displayOrder));
  }

  Future<bool> categoryNameExists(String name, {int? excludeId}) =>
      _repository.categoryNameExists(name, excludeId: excludeId);

  List<ServiceType> serviceTypesFor(int categoryId) =>
      _serviceTypesByCategory[categoryId] ?? const [];

  Future<List<ServiceType>> loadServiceTypes(int categoryId,
      {bool activeOnly = false}) async {
    final items = serviceTypesFor(categoryId)
        .where((s) => !activeOnly || s.isActive)
        .toList();
    return items;
  }

  Future<List<ServiceType>> getServiceTypesForCategory(int categoryId) async {
    return serviceTypesFor(categoryId).where((s) => s.isActive).toList();
  }

  Future<void> addServiceType(ServiceType type) => _repository.saveServiceType(type);

  Future<void> updateServiceType(ServiceType type) =>
      _repository.saveServiceType(type);

  Future<void> toggleServiceTypeActive(ServiceType type) =>
      _repository.saveServiceType(type.copyWith(isActive: !type.isActive));

  Future<void> deleteServiceType(ServiceType type) =>
      _repository.deleteServiceType(type.id!);

  Future<bool> serviceTypeNameExists(int categoryId, String name,
          {int? excludeId}) =>
      _repository.serviceTypeNameExists(categoryId, name, excludeId: excludeId);

  @override
  void dispose() {
    _categorySub?.cancel();
    _serviceTypeSub?.cancel();
    _servicesSub?.cancel();
    super.dispose();
  }
}

class ServiceProvider extends ChangeNotifier {
  final FirestoreCatalogRepository _repository = FirestoreCatalogRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );

  List<Service> _services = [];
  List<Service> _filteredServices = [];
  bool _isLoading = false;
  String _searchQuery = '';
  int? _selectedCategoryId;
  StreamSubscription<List<Service>>? _sub;

  List<Service> get services => _filteredServices;
  List<Service> get allServices => _services;
  bool get isLoading => _isLoading;
  int? get selectedCategoryId => _selectedCategoryId;

  Future<void> loadServices({int? categoryId}) async {
    _isLoading = true;
    notifyListeners();
    await _sub?.cancel();
    _sub = _repository.watchServices().listen((items) {
      _services = items;
      if (categoryId != null) {
        _selectedCategoryId = categoryId;
      }
      _applyFilter();
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<List<Service>> getServicesForCategory(int categoryId,
      {int? serviceTypeId, bool onlyDirect = false}) async {
    return _services.where((s) {
      if (s.categoryId != categoryId || !s.isActive) return false;
      if (serviceTypeId != null) return s.serviceTypeId == serviceTypeId;
      if (onlyDirect) return s.serviceTypeId == null;
      return true;
    }).toList();
  }

  void filterByCategory(int? categoryId) {
    _selectedCategoryId = categoryId;
    _applyFilter();
    notifyListeners();
  }

  void search(String query) {
    _searchQuery = query;
    _applyFilter();
    notifyListeners();
  }

  void _applyFilter() {
    var list = List<Service>.from(_services);
    if (_selectedCategoryId != null) {
      list = list.where((s) => s.categoryId == _selectedCategoryId).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((s) =>
              s.name.toLowerCase().contains(q) ||
              (s.categoryName?.toLowerCase().contains(q) ?? false) ||
              (s.serviceTypeName?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    _filteredServices = list;
  }

  Future<void> addService(Service service) => _repository.saveService(service);

  Future<void> updateService(Service service) => _repository.saveService(service);

  Future<void> toggleActive(Service service) =>
      _repository.saveService(service.copyWith(isActive: !service.isActive));

  Future<void> toggleFavorite(Service service) =>
      _repository.saveService(service.copyWith(isFavorite: !service.isFavorite));

  Future<void> deleteService(Service service) =>
      _repository.deleteService(service.id!);

  Future<bool> serviceNameExists(
          int categoryId, int? serviceTypeId, String name, {int? excludeId}) =>
      _repository.serviceNameExists(categoryId, serviceTypeId, name,
          excludeId: excludeId);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
