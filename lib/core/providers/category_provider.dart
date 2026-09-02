import 'package:flutter/foundation.dart' hide Category;
import '../database/database.dart';
import '../models/customer_models.dart';

class CategoryProvider extends ChangeNotifier {
  final _categoryDao = CategoryDao();
  final _serviceTypeDao = ServiceTypeDao();

  List<Category> _categories = [];
  bool _isLoading = false;

  // Service types for the currently-inspected category.
  final Map<int, List<ServiceType>> _serviceTypesByCategory = {};

  List<Category> get categories => _categories;
  List<Category> get activeCategories =>
      _categories.where((c) => c.isActive).toList();
  bool get isLoading => _isLoading;

  Future<void> loadCategories() async {
    _isLoading = true;
    notifyListeners();
    _categories = await _categoryDao.getAll();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addCategory(Category category) async {
    await _categoryDao.insert(category);
    await loadCategories();
  }

  Future<void> updateCategory(Category category) async {
    await _categoryDao.update(category);
    await loadCategories();
  }

  Future<void> toggleActive(Category category) async {
    await _categoryDao.update(category.copyWith(isActive: !category.isActive));
    await loadCategories();
  }

  Future<void> updateDisplayOrder(int id, int displayOrder) async {
    await _categoryDao.updateDisplayOrder(id, displayOrder);
    await loadCategories();
  }

  /// True if an active category with [name] already exists.
  Future<bool> categoryNameExists(String name, {int? excludeId}) =>
      _categoryDao.nameExists(name, excludeId: excludeId);

  // ── Service types ─────────────────────────────────────────────────────────

  List<ServiceType> serviceTypesFor(int categoryId) =>
      _serviceTypesByCategory[categoryId] ?? const [];

  Future<List<ServiceType>> loadServiceTypes(int categoryId,
      {bool activeOnly = false}) async {
    final types =
        await _serviceTypeDao.getForCategory(categoryId, activeOnly: activeOnly);
    _serviceTypesByCategory[categoryId] = types;
    notifyListeners();
    return types;
  }

  Future<List<ServiceType>> getServiceTypesForCategory(int categoryId) =>
      _serviceTypeDao.getForCategory(categoryId, activeOnly: true);

  Future<void> addServiceType(ServiceType type) async {
    await _serviceTypeDao.insert(type);
    await loadServiceTypes(type.categoryId);
  }

  Future<void> updateServiceType(ServiceType type) async {
    await _serviceTypeDao.update(type);
    await loadServiceTypes(type.categoryId);
  }

  Future<void> toggleServiceTypeActive(ServiceType type) async {
    await _serviceTypeDao.update(type.copyWith(isActive: !type.isActive));
    await loadServiceTypes(type.categoryId);
  }

  Future<bool> serviceTypeNameExists(int categoryId, String name,
          {int? excludeId}) =>
      _serviceTypeDao.nameExists(categoryId, name, excludeId: excludeId);
}

class ServiceProvider extends ChangeNotifier {
  final _serviceDao = ServiceDao();

  List<Service> _services = [];
  List<Service> _filteredServices = [];
  bool _isLoading = false;
  String _searchQuery = '';
  int? _selectedCategoryId;

  List<Service> get services => _filteredServices;
  List<Service> get allServices => _services;
  bool get isLoading => _isLoading;
  int? get selectedCategoryId => _selectedCategoryId;

  Future<void> loadServices({int? categoryId}) async {
    _isLoading = true;
    notifyListeners();
    _services =
        await _serviceDao.getServices(categoryId: categoryId, activeOnly: false);
    _applyFilter();
    _isLoading = false;
    notifyListeners();
  }

  Future<List<Service>> getServicesForCategory(int categoryId,
      {int? serviceTypeId, bool onlyDirect = false}) async {
    return _serviceDao.getServices(
      categoryId: categoryId,
      serviceTypeId: serviceTypeId,
      onlyDirect: onlyDirect,
      activeOnly: true,
    );
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

  Future<void> addService(Service service) async {
    await _serviceDao.insert(service);
    await loadServices();
  }

  Future<void> updateService(Service service) async {
    await _serviceDao.update(service);
    await loadServices();
  }

  Future<void> toggleActive(Service service) async {
    await _serviceDao.update(service.copyWith(isActive: !service.isActive));
    await loadServices();
  }

  Future<bool> serviceNameExists(
          int categoryId, int? serviceTypeId, String name, {int? excludeId}) =>
      _serviceDao.nameExists(categoryId, serviceTypeId, name,
          excludeId: excludeId);
}
