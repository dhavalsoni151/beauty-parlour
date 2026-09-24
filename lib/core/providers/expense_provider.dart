import 'dart:async';

import 'package:flutter/foundation.dart';

import '../firebase/firebase_service.dart';
import '../firestore/firestore_repositories.dart';
import '../models/visit_models.dart';
import 'firebase_startup_provider.dart';

class ExpenseProvider extends ChangeNotifier {
  final FirestoreExpenseRepository _repository = FirestoreExpenseRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );

  List<Expense> _expenses = [];
  List<ExpenseCategory> _categories = [];
  bool _isLoading = false;
  int? _selectedCategoryId;
  String? _startDate;
  String? _endDate;
  StreamSubscription<List<Expense>>? _expensesSub;
  StreamSubscription<List<ExpenseCategory>>? _categoriesSub;

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

    await _expensesSub?.cancel();
    _expensesSub = _repository.watchExpenses().listen((items) {
      _expenses = items.where((e) {
        if (categoryId != null && e.expenseCategoryId != categoryId) return false;
        if (startDate != null && e.expenseDate.compareTo(startDate) < 0) return false;
        if (endDate != null && e.expenseDate.compareTo(endDate) >= 0) return false;
        return true;
      }).toList();
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> loadCategories() async {
    await _categoriesSub?.cancel();
    _categoriesSub = _repository.watchCategories().listen((items) {
      _categories = items;
      notifyListeners();
    });
  }

  double get totalExpenses => _expenses.fold(0, (sum, e) => sum + e.amount);

  Future<void> addExpense(Expense expense) => _repository.saveExpense(expense);

  Future<void> updateExpense(Expense expense) => _repository.saveExpense(expense);

  Future<void> deleteExpense(int id) => _repository.deleteExpense(id);

  Future<void> addCategory(ExpenseCategory cat) => _repository.saveCategory(cat);

  Future<void> updateCategory(ExpenseCategory cat) => _repository.saveCategory(cat);

  Future<List<Map<String, dynamic>>> getExpenseByCategory(
      String startDate, String endDate) async {
    final totals = <int, double>{};
    for (final expense in _expenses.where((e) =>
        e.expenseDate.compareTo(startDate) >= 0 &&
        e.expenseDate.compareTo(endDate) < 0)) {
      totals[expense.expenseCategoryId] =
          (totals[expense.expenseCategoryId] ?? 0) + expense.amount;
    }
    return totals.entries
        .map((entry) => {
              'expense_category_id': entry.key,
              'amount': entry.value,
            })
        .toList();
  }

  @override
  void dispose() {
    _expensesSub?.cancel();
    _categoriesSub?.cancel();
    super.dispose();
  }
}
