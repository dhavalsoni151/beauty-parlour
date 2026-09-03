import '../app_database.dart';
import '../../models/customer_models.dart';
import 'db_exceptions.dart';
import 'package:sqflite/sqflite.dart';

class ServiceDao {
  Future<List<Service>> getServices({
    int? categoryId,
    int? serviceTypeId,
    bool onlyDirect = false,
    bool activeOnly = true,
  }) async {
    final db = await AppDatabase.instance.database;
    final wheres = <String>[];
    final args = <dynamic>[];
    if (activeOnly) wheres.add('s.is_active = 1 AND c.is_active = 1');
    if (categoryId != null) {
      wheres.add('s.category_id = ?');
      args.add(categoryId);
    }
    if (serviceTypeId != null) {
      wheres.add('s.service_type_id = ?');
      args.add(serviceTypeId);
    } else if (onlyDirect) {
      // Services attached directly to the category (no service type).
      wheres.add('s.service_type_id IS NULL');
    }
    final where = wheres.isEmpty ? '' : 'WHERE ${wheres.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT s.*, c.name AS category_name, st.name AS service_type_name
      FROM services s
      JOIN categories c ON c.id = s.category_id
      LEFT JOIN service_types st ON st.id = s.service_type_id
      $where
      ORDER BY c.display_order ASC, st.display_order ASC, s.display_order ASC, s.name ASC
    ''', args);
    return rows.map((r) => Service.fromMap(r)).toList();
  }

  Future<Service?> get(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT s.*, c.name AS category_name, st.name AS service_type_name
      FROM services s
      JOIN categories c ON c.id = s.category_id
      LEFT JOIN service_types st ON st.id = s.service_type_id
      WHERE s.id = ?
      LIMIT 1
    ''', [id]);
    return rows.isEmpty ? null : Service.fromMap(rows.first);
  }

  Future<List<Service>> search(String query) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT s.*, c.name AS category_name, st.name AS service_type_name
      FROM services s
      JOIN categories c ON c.id = s.category_id
      LEFT JOIN service_types st ON st.id = s.service_type_id
      WHERE s.is_active = 1 AND (s.name LIKE ? OR c.name LIKE ? OR st.name LIKE ?)
      ORDER BY s.name ASC
    ''', ['%$query%', '%$query%', '%$query%']);
    return rows.map((r) => Service.fromMap(r)).toList();
  }

  /// Unique on (category_id, service_type_id, name). NULL service type is
  /// treated as its own bucket for this friendly pre-check.
  Future<bool> nameExists(int categoryId, int? serviceTypeId, String name,
      {int? excludeId}) async {
    final db = await AppDatabase.instance.database;
    final wheres = <String>['category_id = ?', 'LOWER(name) = ?'];
    final args = <dynamic>[categoryId, name.trim().toLowerCase()];
    if (serviceTypeId == null) {
      wheres.add('service_type_id IS NULL');
    } else {
      wheres.add('service_type_id = ?');
      args.add(serviceTypeId);
    }
    if (excludeId != null) {
      wheres.add('id != ?');
      args.add(excludeId);
    }
    final rows = await db.query('services',
        where: wheres.join(' AND '), whereArgs: args, limit: 1);
    return rows.isNotEmpty;
  }

  Future<int> insert(Service service) async {
    if (await nameExists(service.categoryId, service.serviceTypeId, service.name)) {
      throw DuplicateException(
          'A service named "${service.name}" already exists here.');
    }
    final db = await AppDatabase.instance.database;
    return db.insert('services', service.toMap());
  }

  Future<int> update(Service service) async {
    if (await nameExists(service.categoryId, service.serviceTypeId, service.name,
        excludeId: service.id)) {
      throw DuplicateException(
          'A service named "${service.name}" already exists here.');
    }
    final db = await AppDatabase.instance.database;
    return db.update(
      'services',
      {...service.toMap(), 'updated_date': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [service.id],
    );
  }

  /// Deletes a service, but only if it was never used in a past visit.
  Future<void> delete(int id) async {
    final db = await AppDatabase.instance.database;
    final visitServiceCount = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM visit_services WHERE service_id = ?', [id])) ??
        0;
    if (visitServiceCount > 0) {
      throw const InUseException(
          'This service cannot be deleted because it has past visits linked '
          'to it. Deactivate it instead.');
    }
    await db.delete('services', where: 'id = ?', whereArgs: [id]);
  }
}
