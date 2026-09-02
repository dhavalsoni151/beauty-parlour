import '../app_database.dart';
import '../../models/customer_models.dart';
import 'db_exceptions.dart';

class ServiceTypeDao {
  /// Service types for a category with active service counts.
  Future<List<ServiceType>> getForCategory(int categoryId,
      {bool activeOnly = false}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT st.*, c.name AS category_name,
        (SELECT COUNT(*) FROM services s
           WHERE s.service_type_id = st.id AND s.is_active = 1) AS service_count
      FROM service_types st
      JOIN categories c ON c.id = st.category_id
      WHERE st.category_id = ? ${activeOnly ? 'AND st.is_active = 1' : ''}
      ORDER BY st.display_order ASC, st.name ASC
    ''', [categoryId]);
    return rows.map((r) => ServiceType.fromMap(r)).toList();
  }

  Future<List<ServiceType>> getAll({bool activeOnly = false}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT st.*, c.name AS category_name
      FROM service_types st
      JOIN categories c ON c.id = st.category_id
      ${activeOnly ? 'WHERE st.is_active = 1' : ''}
      ORDER BY st.category_id ASC, st.display_order ASC, st.name ASC
    ''');
    return rows.map((r) => ServiceType.fromMap(r)).toList();
  }

  Future<ServiceType?> get(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('service_types', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ServiceType.fromMap(rows.first);
  }

  Future<bool> nameExists(int categoryId, String name, {int? excludeId}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'service_types',
      where:
          'category_id = ? AND LOWER(name) = ?${excludeId != null ? ' AND id != ?' : ''}',
      whereArgs: [
        categoryId,
        name.trim().toLowerCase(),
        if (excludeId != null) excludeId,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> insert(ServiceType type) async {
    if (await nameExists(type.categoryId, type.name)) {
      throw DuplicateException(
          'A service type named "${type.name}" already exists in this category.');
    }
    final db = await AppDatabase.instance.database;
    return db.insert('service_types', type.toMap());
  }

  Future<int> update(ServiceType type) async {
    if (await nameExists(type.categoryId, type.name, excludeId: type.id)) {
      throw DuplicateException(
          'A service type named "${type.name}" already exists in this category.');
    }
    final db = await AppDatabase.instance.database;
    return db.update(
      'service_types',
      {...type.toMap(), 'updated_date': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [type.id],
    );
  }
}
