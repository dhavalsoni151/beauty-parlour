import '../app_database.dart';
import '../../models/visit_models.dart';

class ExpenseDao {
  // ── Expense categories ────────────────────────────────────────────────────

  Future<int> insertCategory(ExpenseCategory cat) async {
    final db = await AppDatabase.instance.database;
    return db.insert('expense_categories', {
      ...cat.toMap(),
      'created_date': DateTime.now().toIso8601String(),
    });
  }

  Future<int> updateCategory(ExpenseCategory cat) async {
    final db = await AppDatabase.instance.database;
    return db.update('expense_categories', cat.toMap(),
        where: 'id = ?', whereArgs: [cat.id]);
  }

  Future<List<ExpenseCategory>> getCategories({bool activeOnly = true}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'expense_categories',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name ASC',
    );
    return rows.map((r) => ExpenseCategory.fromMap(r)).toList();
  }

  // ── Expenses ──────────────────────────────────────────────────────────────

  Future<int> insert(Expense expense) async {
    final db = await AppDatabase.instance.database;
    return db.insert('expenses', expense.toMap());
  }

  Future<int> update(Expense expense) async {
    final db = await AppDatabase.instance.database;
    return db.update(
      'expenses',
      {...expense.toMap(), 'updated_date': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [expense.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await AppDatabase.instance.database;
    return db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Expense>> getExpenses({
    String? startDate,
    String? endDate,
    int? categoryId,
  }) async {
    final db = await AppDatabase.instance.database;
    final wheres = <String>[];
    final args = <dynamic>[];
    if (startDate != null) {
      wheres.add('DATE(e.expense_date) >= DATE(?)');
      args.add(startDate);
    }
    if (endDate != null) {
      wheres.add('DATE(e.expense_date) < DATE(?)');
      args.add(endDate);
    }
    if (categoryId != null) {
      wheres.add('e.expense_category_id = ?');
      args.add(categoryId);
    }
    final where = wheres.isEmpty ? '' : 'WHERE ${wheres.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT e.*, ec.name AS category_name
      FROM expenses e
      JOIN expense_categories ec ON ec.id = e.expense_category_id
      $where
      ORDER BY e.expense_date DESC, e.id DESC
    ''', args);
    return rows.map((r) => Expense.fromMap(r)).toList();
  }
}
