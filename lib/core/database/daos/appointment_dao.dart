import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../../models/appointment_models.dart';
import 'db_exceptions.dart';

class AppointmentDao {
  Future<List<Appointment>> getAll({
    DateTime? date,
    String? startDate,
    String? endDate,
    int? customerId,
    AppointmentStatus? status,
  }) async {
    final db = await AppDatabase.instance.database;
    final wheres = <String>[];
    final args = <dynamic>[];

    if (date != null) {
      wheres.add('a.appointment_date = ?');
      args.add(_dateOnly(date));
    }
    if (startDate != null) {
      wheres.add('a.appointment_date >= ?');
      args.add(startDate);
    }
    if (endDate != null) {
      wheres.add('a.appointment_date < ?');
      args.add(endDate);
    }
    if (customerId != null) {
      wheres.add('a.customer_id = ?');
      args.add(customerId);
    }
    if (status != null) {
      wheres.add('a.status = ?');
      args.add(status.dbValue);
    }

    final where = wheres.isEmpty ? '' : 'WHERE ${wheres.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT a.*, c.name AS customer_name, c.phone AS customer_phone
      FROM appointments a
      JOIN customers c ON c.id = a.customer_id
      $where
      ORDER BY a.appointment_date ASC, a.start_time ASC, a.id ASC
    ''', args);
    final appointments = rows.map((r) => Appointment.fromMap(r)).toList();
    await _attachServices(db, appointments);
    return appointments;
  }

  Future<Appointment?> get(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT a.*, c.name AS customer_name, c.phone AS customer_phone
      FROM appointments a
      JOIN customers c ON c.id = a.customer_id
      WHERE a.id = ?
      LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    final appointment = Appointment.fromMap(rows.first);
    await _attachServices(db, [appointment]);
    return appointment;
  }

  Future<void> _attachServices(
      DatabaseExecutor db, List<Appointment> appointments) async {
    if (appointments.isEmpty) return;
    final ids = appointments.map((a) => a.id).whereType<int>().toList();
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM appointment_services WHERE appointment_id IN ($placeholders) ORDER BY id ASC',
      ids,
    );
    final byAppointment = <int, List<AppointmentService>>{};
    for (final row in rows) {
      final service = AppointmentService.fromMap(row);
      byAppointment.putIfAbsent(service.appointmentId, () => []).add(service);
    }
    for (final appointment in appointments) {
      appointment.services = byAppointment[appointment.id] ?? const [];
    }
  }

  Future<List<AppointmentService>> getServices(int appointmentId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'appointment_services',
      where: 'appointment_id = ?',
      whereArgs: [appointmentId],
      orderBy: 'id ASC',
    );
    return rows.map((r) => AppointmentService.fromMap(r)).toList();
  }

  Future<int> insert(Appointment appointment,
      {List<AppointmentService> services = const []}) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final id = await txn.insert('appointments', appointment.toMap());
      for (final service in services) {
        await txn.insert(
            'appointment_services', service.copyWith(appointmentId: id).toMap());
      }
      return id;
    });
  }

  Future<int> update(Appointment appointment,
      {List<AppointmentService>? services}) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final result = await txn.update(
        'appointments',
        {...appointment.toMap(), 'updated_date': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [appointment.id],
      );
      if (services != null) {
        await txn.delete('appointment_services',
            where: 'appointment_id = ?', whereArgs: [appointment.id]);
        for (final service in services) {
          await txn.insert(
            'appointment_services',
            service.copyWith(appointmentId: appointment.id!).toMap(),
          );
        }
      }
      return result;
    });
  }

  Future<void> updateStatus(int id, AppointmentStatus status, {int? visitId}) async {
    final db = await AppDatabase.instance.database;
    final values = <String, dynamic>{
      'status': status.dbValue,
      'updated_date': DateTime.now().toIso8601String(),
    };
    if (visitId != null) {
      values['visit_id'] = visitId;
    }
    await db.update('appointments', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Appointment>> getUpcoming({int limit = 5}) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now();
    final today = _dateOnly(now);
    final time = _timeOnly(now);
    final rows = await db.rawQuery('''
      SELECT a.*, c.name AS customer_name, c.phone AS customer_phone
      FROM appointments a
      JOIN customers c ON c.id = a.customer_id
      WHERE a.status = ?
        AND (
          a.appointment_date > ? OR
          (a.appointment_date = ? AND a.start_time >= ?)
        )
      ORDER BY a.appointment_date ASC, a.start_time ASC, a.id ASC
      LIMIT $limit
    ''', [AppointmentStatus.pending.dbValue, today, today, time]);
    final appointments = rows.map((r) => Appointment.fromMap(r)).toList();
    await _attachServices(db, appointments);
    return appointments;
  }

  Future<List<Appointment>> getForCustomer(int customerId) {
    return getAll(customerId: customerId);
  }

  Future<void> delete(int id) async {
    final db = await AppDatabase.instance.database;
    final current = await db.query(
      'appointments',
      columns: ['visit_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (current.isEmpty) return;
    if (current.first['visit_id'] != null) {
      throw const InUseException(
        'This appointment is already linked to a visit and cannot be deleted.',
      );
    }
    await db.delete('appointment_services',
        where: 'appointment_id = ?', whereArgs: [id]);
    await db.delete('appointments', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> isSlotTaken(DateTime date, String startTime, {int? excludeId}) async {
    final db = await AppDatabase.instance.database;
    final wheres = <String>[
      'appointment_date = ?',
      'start_time = ?',
      'status = ?',
    ];
    final args = <dynamic>[
      _dateOnly(date),
      startTime,
      AppointmentStatus.pending.dbValue,
    ];
    if (excludeId != null) {
      wheres.add('id != ?');
      args.add(excludeId);
    }
    final count = Sqflite.firstIntValue(await db.query(
          'appointments',
          columns: ['COUNT(*)'],
          where: wheres.join(' AND '),
          whereArgs: args,
        )) ??
        0;
    return count > 0;
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _timeOnly(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
