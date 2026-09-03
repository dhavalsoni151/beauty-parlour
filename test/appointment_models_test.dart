import 'package:flutter_test/flutter_test.dart';
import 'package:beauty_parlour/core/models/appointment_models.dart';

void main() {
  group('AppointmentStatus', () {
    test('round-trips db values', () {
      for (final status in AppointmentStatus.values) {
        expect(
          AppointmentStatusX.fromString(status.dbValue),
          status,
        );
      }
    });

    test('unknown status falls back to pending', () {
      expect(AppointmentStatusX.fromString('unexpected'), AppointmentStatus.pending);
    });
  });

  group('Appointment', () {
    test('toMap/fromMap preserves stored fields', () {
      final appointment = Appointment(
        id: 7,
        customerId: 11,
        serviceId: 13,
        categoryId: 17,
        serviceTypeId: 19,
        serviceNameSnapshot: 'Bridal Makeup',
        appointmentDate: '2026-09-03',
        startTime: '10:30',
        endTime: '11:30',
        status: AppointmentStatus.pending,
        notes: 'Bring reference photos',
        visitId: 23,
        reminderMinutesBefore: 30,
        createdDate: '2026-09-01T10:00:00.000',
        updatedDate: '2026-09-02T10:00:00.000',
        customerName: 'Priya',
        customerPhone: '9999999999',
      );

      final mapped = appointment.toMap();
      final restored = Appointment.fromMap({
        ...mapped,
        'customer_name': 'Priya',
        'customer_phone': '9999999999',
      });

      expect(restored.id, appointment.id);
      expect(restored.customerId, appointment.customerId);
      expect(restored.serviceId, appointment.serviceId);
      expect(restored.categoryId, appointment.categoryId);
      expect(restored.serviceTypeId, appointment.serviceTypeId);
      expect(restored.serviceNameSnapshot, appointment.serviceNameSnapshot);
      expect(restored.appointmentDate, appointment.appointmentDate);
      expect(restored.startTime, appointment.startTime);
      expect(restored.endTime, appointment.endTime);
      expect(restored.status, appointment.status);
      expect(restored.notes, appointment.notes);
      expect(restored.visitId, appointment.visitId);
      expect(restored.reminderMinutesBefore, appointment.reminderMinutesBefore);
      expect(restored.createdDate, appointment.createdDate);
      expect(restored.updatedDate, appointment.updatedDate);
      expect(restored.customerName, appointment.customerName);
      expect(restored.customerPhone, appointment.customerPhone);
    });
  });
}
