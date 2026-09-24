import '../app_database.dart';
import '../../models/customer_models.dart';

class CustomerDao {
  Future<int> insert(Customer customer) async {
    final db = await AppDatabase.instance.database;
    return db.insert('customers', customer.toMap());
  }

  Future<int> update(Customer customer) async {
    final db = await AppDatabase.instance.database;
    return db.update('customers', customer.toMap(),
        where: 'id = ?', whereArgs: [customer.id]);
  }

  Future<List<Customer>> getAll({bool activeOnly = true}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'customers',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name ASC',
    );
    return rows.map((r) => Customer.fromMap(r)).toList();
  }

  Future<Customer?> get(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<List<Customer>> search(String query) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'customers',
      where: 'is_active = 1 AND (name LIKE ? OR phone LIKE ?)',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'name ASC',
    );
    return rows.map((r) => Customer.fromMap(r)).toList();
  }
}
