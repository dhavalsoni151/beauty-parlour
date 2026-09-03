import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/appointment_models.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const AndroidNotificationChannel _appointmentChannel =
      AndroidNotificationChannel(
    'appointments',
    'Appointments',
    description: 'Appointment reminders',
    importance: Importance.high,
  );

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      tz_data.initializeTimeZones();
      _setBestEffortLocalTimezone();

      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_appointmentChannel);
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService.initialize failed: $e');
    }
  }

  Future<void> scheduleAppointmentReminder(Appointment appointment) async {
    final id = appointment.id;
    if (id == null) return;
    try {
      await initialize();
      await cancelReminder(id);
      if (appointment.status != AppointmentStatus.pending ||
          appointment.reminderMinutesBefore == null) {
        return;
      }

      final appointmentAt = _appointmentDateTime(appointment);
      final remindAt = appointmentAt.subtract(
        Duration(minutes: appointment.reminderMinutesBefore!),
      );
      if (!remindAt.isAfter(DateTime.now())) return;

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _appointmentChannel.id,
          _appointmentChannel.name,
          channelDescription: _appointmentChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      );
      final body = [
        if ((appointment.customerName ?? '').trim().isNotEmpty)
          appointment.customerName!.trim(),
        if (appointment.serviceNameSnapshot.trim().isNotEmpty)
          appointment.serviceNameSnapshot.trim(),
        'at ${appointment.startTime}',
      ].join(' • ');

      try {
        await _plugin.zonedSchedule(
          id,
          'Appointment Reminder',
          body,
          tz.TZDateTime.from(remindAt, tz.local),
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: 'appointment:$id',
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        debugPrint('Exact reminder scheduling failed, retrying inexact: $e');
        await _plugin.zonedSchedule(
          id,
          'Appointment Reminder',
          body,
          tz.TZDateTime.from(remindAt, tz.local),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'appointment:$id',
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (e) {
      debugPrint('scheduleAppointmentReminder failed for ${appointment.id}: $e');
    }
  }

  Future<void> cancelReminder(int appointmentId) async {
    try {
      await initialize();
      await _plugin.cancel(appointmentId);
    } catch (e) {
      debugPrint('cancelReminder failed for $appointmentId: $e');
    }
  }

  DateTime _appointmentDateTime(Appointment appointment) {
    final parts = appointment.startTime.split(':');
    final date = DateTime.parse(appointment.appointmentDate);
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  void _setBestEffortLocalTimezone() {
    try {
      final now = DateTime.now();
      final offset = now.timeZoneOffset;
      tz.Location? offsetMatch;
      final zoneName = now.timeZoneName.toLowerCase();
      for (final entry in tz.timeZoneDatabase.locations.entries) {
        final localNow = tz.TZDateTime.from(now, entry.value);
        if (localNow.timeZoneOffset != offset) continue;
        offsetMatch ??= entry.value;
        final key = entry.key.toLowerCase();
        if (key.contains(zoneName) || zoneName.contains(key.split('/').last)) {
          tz.setLocalLocation(entry.value);
          return;
        }
      }
      if (offsetMatch != null) {
        tz.setLocalLocation(offsetMatch);
      }
    } catch (e) {
      debugPrint('Timezone detection fallback to UTC: $e');
    }
  }
}
