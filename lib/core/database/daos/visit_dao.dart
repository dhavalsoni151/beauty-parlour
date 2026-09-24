import '../app_database.dart';
import '../../models/visit_models.dart';

class VisitDao {
  /// Saves a full visit (visit + visit_services + payments) atomically.
  /// The whole thing rolls back if any insert fails.
  Future<int> insertVisit(
    Visit visit,
    List<VisitService> services,
    List<Payment> payments,
  ) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final createdAt = DateTime.now().toIso8601String();
      final visitId = await txn.insert('visits', visit.toMap());
      for (final s in services) {
        final map = s.toMap()
          ..['visit_id'] = visitId
          ..['created_at'] = s.createdAt ?? createdAt;
        await txn.insert('visit_services', map);
      }
      for (final p in payments) {
        final map = p.toMap()
          ..['visit_id'] = visitId
          ..['created_date'] = createdAt;
        await txn.insert('payments', map);
      }
      return visitId;
    });
  }

  /// Updates an existing visit's details and replaces its service lines.
  /// Used for editing a visit (including one already paid/written off) —
  /// since it writes to the same `visits`/`visit_services` rows the reports
  /// and dashboard read from, every aggregate automatically reflects the edit.
  Future<void> updateVisit(Visit visit, List<VisitService> services) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        'visits',
        {...visit.toMap(), 'updated_date': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [visit.id],
      );
      await txn.delete('visit_services', where: 'visit_id = ?', whereArgs: [visit.id]);
      final createdAt = DateTime.now().toIso8601String();
      for (final s in services) {
        final map = s.toMap()
          ..['visit_id'] = visit.id
          ..['created_at'] = s.createdAt ?? createdAt;
        await txn.insert('visit_services', map);
      }
    });
  }

  Future<Visit?> get(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT v.*, c.name AS customer_name, c.phone AS customer_phone
      FROM visits v
      JOIN customers c ON c.id = v.customer_id
      WHERE v.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    final visit = Visit.fromMap(rows.first);
    visit.services = await getVisitServices(id);
    visit.payments = await getPaymentsForVisit(id);
    return visit;
  }

  Future<List<Visit>> getVisits({
    int? customerId,
    String? startDate,
    String? endDate,
    String? paymentStatus,
  }) async {
    final db = await AppDatabase.instance.database;
    final wheres = <String>[];
    final args = <dynamic>[];
    if (customerId != null) {
      wheres.add('v.customer_id = ?');
      args.add(customerId);
    }
    if (startDate != null) {
      wheres.add('v.visit_date >= ?');
      args.add(startDate);
    }
    if (endDate != null) {
      wheres.add('v.visit_date < ?');
      args.add(endDate);
    }
    if (paymentStatus != null) {
      wheres.add('v.payment_status = ?');
      args.add(paymentStatus);
    }
    final where = wheres.isEmpty ? '' : 'WHERE ${wheres.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT v.*, c.name AS customer_name, c.phone AS customer_phone
      FROM visits v
      JOIN customers c ON c.id = v.customer_id
      $where
      ORDER BY v.visit_date DESC, v.id DESC
    ''', args);
    return rows.map((r) => Visit.fromMap(r)).toList();
  }

  Future<List<Visit>> getPendingVisits() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT v.*, c.name AS customer_name, c.phone AS customer_phone
      FROM visits v
      JOIN customers c ON c.id = v.customer_id
      WHERE v.payment_status IN ('PENDING', 'PARTIALLY_PAID')
      ORDER BY v.visit_date DESC
    ''');
    return rows.map((r) => Visit.fromMap(r)).toList();
  }

  Future<List<VisitService>> getVisitServices(int visitId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('visit_services',
        where: 'visit_id = ?', whereArgs: [visitId], orderBy: 'id ASC');
    return rows.map((r) => VisitService.fromMap(r)).toList();
  }

  Future<List<Payment>> getPaymentsForVisit(int visitId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('payments',
        where: 'visit_id = ?', whereArgs: [visitId], orderBy: 'payment_date ASC');
    return rows.map((r) => Payment.fromMap(r)).toList();
  }

  Future<void> updateVisitPayment(
    int visitId,
    double totalPaid,
    double pendingAmount,
    String paymentStatus,
  ) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'visits',
      {
        'total_paid': totalPaid,
        'pending_amount': pendingAmount,
        'payment_status': paymentStatus,
        'updated_date': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [visitId],
    );
  }
}
