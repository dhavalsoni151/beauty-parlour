import '../app_database.dart';
import '../../models/visit_models.dart';

class PaymentDao {
  Future<int> insert(Payment payment) async {
    final db = await AppDatabase.instance.database;
    return db.insert('payments', {
      ...payment.toMap(),
      'created_date': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Payment>> getForVisit(int visitId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('payments',
        where: 'visit_id = ?', whereArgs: [visitId], orderBy: 'payment_date ASC');
    return rows.map((r) => Payment.fromMap(r)).toList();
  }
}
