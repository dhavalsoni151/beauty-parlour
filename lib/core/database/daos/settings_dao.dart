import 'package:sqflite/sqflite.dart';
import '../app_database.dart';

class SettingsDao {
  Future<Map<String, String>> getSettings() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('settings');
    return Map.fromEntries(rows
        .map((r) => MapEntry(r['key'] as String, r['value'] as String? ?? '')));
  }

  Future<String?> getSetting(String key) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await AppDatabase.instance.database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSetting(String key) async {
    final db = await AppDatabase.instance.database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }
}
