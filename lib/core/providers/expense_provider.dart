import 'package:flutter/foundation.dart';
import '../database/database.dart';
import '../models/visit_models.dart';

class ExpenseProvider extends ChangeNotifier {
  final _expenseDao = ExpenseDao();
  final _reportDao = ReportDao();

  List<Expense> _expenses = [];
  List<ExpenseCategory> _categories = [];
  bool _isLoading = false;
  int? _selectedCategoryId;
  String? _startDate;
  String? _endDate;

  List<Expense> get expenses => _expenses;
  List<ExpenseCategory> get categories => _categories;
  bool get isLoading => _isLoading;

  Future<void> loadExpenses(
      {String? startDate, String? endDate, int? categoryId}) async {
    _isLoading = true;
    notifyListeners();
    _selectedCategoryId = categoryId;
    _startDate = startDate;
    _endDate = endDate;
    _expenses = await _expenseDao.getExpenses(
      startDate: startDate,
      endDate: endDate,
      categoryId: categoryId,
    );
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadCategories() async {
    _categories = await _expenseDao.getCategories();
    notifyListeners();
  }

  double get totalExpenses => _expenses.fold(0, (sum, e) => sum + e.amount);

  Future<void> addExpense(Expense expense) async {
    await _expenseDao.insert(expense);
    await loadExpenses(
        startDate: _startDate, endDate: _endDate, categoryId: _selectedCategoryId);
  }

  Future<void> updateExpense(Expense expense) async {
    await _expenseDao.update(expense);
    await loadExpenses(
        startDate: _startDate, endDate: _endDate, categoryId: _selectedCategoryId);
  }

  Future<void> deleteExpense(int id) async {
    await _expenseDao.delete(id);
    await loadExpenses(
        startDate: _startDate, endDate: _endDate, categoryId: _selectedCategoryId);
  }

  Future<void> addCategory(ExpenseCategory cat) async {
    await _expenseDao.insertCategory(cat);
    await loadCategories();
  }

  Future<void> updateCategory(ExpenseCategory cat) async {
    await _expenseDao.updateCategory(cat);
    await loadCategories();
  }

  Future<List<Map<String, dynamic>>> getExpenseByCategory(
      String startDate, String endDate) async {
    return _reportDao.getExpenseByCategory(startDate, endDate);
  }
}
