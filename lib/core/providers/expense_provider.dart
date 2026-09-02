import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/visit_models.dart';

class ExpenseProvider extends ChangeNotifier {
  final _db = DatabaseHelper.instance;
  List<Expense> _expenses = [];
  List<ExpenseCategory> _categories = [];
  bool _isLoading = false;
  int? _selectedCategoryId;
  String? _startDate;
  String? _endDate;

  List<Expense> get expenses => _expenses;
  List<ExpenseCategory> get categories => _categories;
  bool get isLoading => _isLoading;

  Future<void> loadExpenses({String? startDate, String? endDate, int? categoryId}) async {
    _isLoading = true;
    notifyListeners();
    _selectedCategoryId = categoryId;
    _startDate = startDate;
    _endDate = endDate;
    _expenses = await _db.getExpenses(
      startDate: startDate,
      endDate: endDate,
      categoryId: categoryId,
    );
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadCategories() async {
    _categories = await _db.getExpenseCategories();
    notifyListeners();
  }

  double get totalExpenses => _expenses.fold(0, (sum, e) => sum + e.amount);

  Future<void> addExpense(Expense expense) async {
    await _db.insertExpense(expense);
    await loadExpenses(startDate: _startDate, endDate: _endDate, categoryId: _selectedCategoryId);
  }

  Future<void> updateExpense(Expense expense) async {
    await _db.updateExpense(expense);
    await loadExpenses(startDate: _startDate, endDate: _endDate, categoryId: _selectedCategoryId);
  }

  Future<void> deleteExpense(int id) async {
    await _db.deleteExpense(id);
    await loadExpenses(startDate: _startDate, endDate: _endDate, categoryId: _selectedCategoryId);
  }

  Future<void> addCategory(ExpenseCategory cat) async {
    await _db.insertExpenseCategory(cat);
    await loadCategories();
  }

  Future<void> updateCategory(ExpenseCategory cat) async {
    await _db.updateExpenseCategory(cat);
    await loadCategories();
  }

  Future<List<Map<String, dynamic>>> getExpenseByCategory(String startDate, String endDate) async {
    return await _db.getExpenseByCategory(startDate, endDate);
  }
}
