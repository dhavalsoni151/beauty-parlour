import '../app_database.dart';
import '../../models/customer_models.dart';
import 'db_exceptions.dart';

class CategoryDao {
  /// Returns all categories with aggregated active service-type and service
  /// counts, ordered for display.
  Future<List<Category>> getAll({bool activeOnly = false}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT c.*,
        (SELECT COUNT(*) FROM service_types st
           WHERE st.category_id = c.id AND st.is_active = 1) AS service_type_count,
        (SELECT COUNT(*) FROM services s
           WHERE s.category_id = c.id AND s.is_active = 1) AS service_count
      FROM categories c
      ${activeOnly ? 'WHERE c.is_active = 1' : ''}
      ORDER BY c.display_order ASC, c.name ASC
    ''');
    return rows.map((r) => Category.fromMap(r)).toList();
  }

  Future<Category?> get(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('categories', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Category.fromMap(rows.first);
  }

  /// True if another ACTIVE category already uses [name] (case-insensitive),
  /// excluding [excludeId].
  Future<bool> nameExists(String name, {int? excludeId}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'categories',
      where: 'is_active = 1 AND LOWER(name) = ?${excludeId != null ? ' AND id != ?' : ''}',
      whereArgs: [name.trim().toLowerCase(), if (excludeId != null) excludeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> insert(Category category) async {
    if (await nameExists(category.name)) {
      throw DuplicateException('A category named "${category.name}" already exists.');
    }
    final db = await AppDatabase.instance.database;
    return db.insert('categories', category.toMap());
  }

  Future<int> update(Category category) async {
    if (await nameExists(category.name, excludeId: category.id)) {
      throw DuplicateException('A category named "${category.name}" already exists.');
    }
    final db = await AppDatabase.instance.database;
    return db.update(
      'categories',
      {...category.toMap(), 'updated_date': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<void> updateDisplayOrder(int id, int displayOrder) async {
    final db = await AppDatabase.instance.database;
    await db.update('categories', {'display_order': displayOrder},
        where: 'id = ?', whereArgs: [id]);
  }
}
