import '../app_database.dart';
import '../../models/visit_models.dart';

class WriteOffDao {
  Future<int> insert(WriteOff writeOff) async {
    final db = await AppDatabase.instance.database;
    return db.insert('write_offs', {
      ...writeOff.toMap(),
      'created_date': DateTime.now().toIso8601String(),
    });
  }

  Future<List<WriteOff>> getForVisit(int visitId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('write_offs',
        where: 'visit_id = ?', whereArgs: [visitId]);
    return rows.map((r) => WriteOff.fromMap(r)).toList();
  }
}
