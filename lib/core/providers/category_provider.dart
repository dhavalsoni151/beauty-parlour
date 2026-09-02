import 'package:flutter/foundation.dart' hide Category;
import '../database/database_helper.dart';
import '../models/customer_models.dart';

class CategoryProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;
  List<Category> _categories = [];
  bool _isLoading = false;

  List<Category> get categories => _categories;
  List<Category> get activeCategories => _categories.where((c) => c.isActive).toList();
  bool get isLoading => _isLoading;

  Future<void> loadCategories() async {
    _isLoading = true;
    notifyListeners();
    _categories = await _db.getCategories();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addCategory(Category category) async {
    await _db.insertCategory(category);
    await loadCategories();
  }

  Future<void> updateCategory(Category category) async {
    await _db.updateCategory(category);
    await loadCategories();
  }

  Future<void> toggleActive(Category category) async {
    await _db.updateCategory(category.copyWith(isActive: !category.isActive));
    await loadCategories();
  }
}

class ServiceProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;
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
    _services = await _db.getServices(categoryId: categoryId, activeOnly: false);
    _applyFilter();
    _isLoading = false;
    notifyListeners();
  }

  Future<List<Service>> getServicesForCategory(int categoryId) async {
    return await _db.getServices(categoryId: categoryId, activeOnly: true);
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
      list = list.where((s) =>
        s.name.toLowerCase().contains(q) ||
        (s.categoryName?.toLowerCase().contains(q) ?? false)
      ).toList();
    }
    _filteredServices = list;
  }

  Future<void> addService(Service service) async {
    await _db.insertService(service);
    await loadServices();
  }

  Future<void> updateService(Service service) async {
    await _db.updateService(service);
    await loadServices();
  }

  Future<void> toggleActive(Service service) async {
    await _db.updateService(service.copyWith(isActive: !service.isActive));
    await loadServices();
  }
}
