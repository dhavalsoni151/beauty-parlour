import 'dart:async';

import 'package:flutter/foundation.dart';

import '../firebase/firebase_service.dart';
import '../firestore/firestore_repositories.dart';
import '../models/appointment_models.dart';
import '../models/visit_models.dart';
import '../services/notification_service.dart';
import '../utils/formatters.dart';
import 'firebase_startup_provider.dart';

class AppointmentProvider extends ChangeNotifier {
  final FirestoreAppointmentRepository _repository = FirestoreAppointmentRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );
  final FirestoreCatalogRepository _catalogRepository = FirestoreCatalogRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );
  final _notifications = NotificationService.instance;

  List<Appointment> _appointments = [];
  List<Appointment> _upcomingAppointments = [];
  bool _isLoading = false;

  StreamSubscription<List<Appointment>>? _sub;

  List<Appointment> get appointments => _appointments;
  List<Appointment> get upcomingAppointments => _upcomingAppointments;
  bool get isLoading => _isLoading;

  Future<void> loadAppointments({
    DateTime? date,
    String? startDate,
    String? endDate,
    int? customerId,
    AppointmentStatus? status,
  }) async {
    _isLoading = true;
    notifyListeners();

    await _sub?.cancel();
    _sub = _repository.watchAppointments().listen((items) {
      _appointments = items.where((a) {
        if (customerId != null && a.customerId != customerId) return false;
        if (status != null && a.status != status) return false;
        if (date != null) {
          final d = DateTime.tryParse(a.appointmentDate);
          if (d == null ||
              d.year != date.year ||
              d.month != date.month ||
              d.day != date.day) {
            return false;
          }
        }
        if (startDate != null && a.appointmentDate.compareTo(startDate) < 0) {
          return false;
        }
        if (endDate != null && a.appointmentDate.compareTo(endDate) >= 0) {
          return false;
        }
        return true;
      }).toList();
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<Appointment?> getAppointment(int id) => _repository.get(id);

  Future<List<Appointment>> getForCustomer(int customerId) =>
      _repository.getForCustomer(customerId);

  Future<int> addAppointment(Appointment appointment,
      {List<AppointmentService> services = const []}) async {
    final id = await _repository.save(appointment.copyWith(services: services));
    final saved = appointment.copyWith(id: id);
    await _notifications.scheduleAppointmentReminder(saved);
    return id;
  }

  Future<void> updateAppointment(Appointment appointment,
      {List<AppointmentService>? services}) async {
    await _repository.save(appointment.copyWith(services: services ?? appointment.services));
    final refreshed = await _repository.get(appointment.id!);
    if (refreshed != null) {
      if (refreshed.status == AppointmentStatus.pending) {
        await _notifications.scheduleAppointmentReminder(refreshed);
      } else {
        await _notifications.cancelReminder(refreshed.id!);
      }
    }
  }

  Future<void> cancelAppointment(int id) async {
    await _repository.updateStatus(id, AppointmentStatus.cancelled);
    await _notifications.cancelReminder(id);
  }

  Future<void> markNotAttended(int id) async {
    await _repository.updateStatus(id, AppointmentStatus.notAttended);
    await _notifications.cancelReminder(id);
  }

  Future<Visit> buildPrefillVisit(Appointment appointment) async {
    final visitDate = _appointmentDateTime(appointment).toIso8601String();
    return Visit(
      customerId: appointment.customerId,
      visitDate: visitDate,
      subtotal: 0,
      discountType: DiscountType.fixed,
      discountValue: 0,
      discountAmount: 0,
      finalTotal: 0,
      totalPaid: 0,
      pendingAmount: 0,
      paymentStatus: PaymentStatus.pending,
      notes: appointment.notes,
      createdDate: DateTime.now().toIso8601String(),
      customerName: appointment.customerName,
      customerPhone: appointment.customerPhone,
      packageId: appointment.packageId,
      packageNameSnapshot: appointment.packageNameSnapshot,
      packageNormalTotal: appointment.packageNormalTotal,
      packagePrice: appointment.packagePrice,
      packageDiscount: appointment.packageDiscount,
    );
  }

  Future<List<VisitService>> buildPrefillServices(Appointment appointment) async {
    if (appointment.services.isNotEmpty) {
      return appointment.services
          .map((s) => VisitService(
                visitId: 0,
                serviceId: s.serviceId,
                categoryId: s.categoryId,
                serviceTypeId: s.serviceTypeId,
                categoryNameSnapshot: s.categoryNameSnapshot,
                serviceTypeNameSnapshot: s.serviceTypeNameSnapshot,
                serviceNameSnapshot: s.serviceNameSnapshot,
                price: s.price,
                quantity: s.quantity,
                total: s.total,
                createdAt: DateTime.now().toIso8601String(),
                isPackageItem: s.isPackageItem,
                packageId: s.packageId,
                normalPriceSnapshot: s.normalPriceSnapshot,
              ))
          .toList();
    }
    if (appointment.serviceNameSnapshot.isEmpty) {
      return const [];
    }
    final services = await _catalogRepository.watchServices().first;
    final categories = await _catalogRepository.watchCategories().first;
    final types = await _catalogRepository.watchServiceTypes().first;
    final service = appointment.serviceId == null
        ? null
        : services.where((s) => s.id == appointment.serviceId).firstOrNull;
    final category = appointment.categoryId == null
        ? null
        : categories.where((c) => c.id == appointment.categoryId).firstOrNull;
    final serviceType = appointment.serviceTypeId == null
        ? null
        : types.where((t) => t.id == appointment.serviceTypeId).firstOrNull;
    final price = service?.defaultPrice ?? 0.0;
    return [
      VisitService(
        visitId: 0,
        serviceId: appointment.serviceId,
        categoryId: appointment.categoryId,
        serviceTypeId: appointment.serviceTypeId,
        categoryNameSnapshot: service?.categoryName ?? category?.name ?? '',
        serviceTypeNameSnapshot: service?.serviceTypeName ?? serviceType?.name,
        serviceNameSnapshot: appointment.serviceNameSnapshot,
        price: price,
        total: price,
        createdAt: DateTime.now().toIso8601String(),
      ),
    ];
  }

  Future<void> completeWithVisit(int appointmentId, int visitId) async {
    final latest = await _repository.get(appointmentId);
    if (latest == null) {
      throw Exception('Appointment not found.');
    }
    if (latest.status != AppointmentStatus.pending) {
      throw Exception('Only pending appointments can be completed.');
    }
    await _repository.updateStatus(
      appointmentId,
      AppointmentStatus.completed,
      visitId: visitId,
    );
    await _notifications.cancelReminder(appointmentId);
  }

  Future<void> deleteAppointment(int id) async {
    await _repository.delete(id);
    await _notifications.cancelReminder(id);
  }

  Future<void> loadUpcomingAppointments({int limit = 5}) async {
    _upcomingAppointments = await _repository.getUpcoming(limit: limit);
    notifyListeners();
  }

  Future<List<Appointment>> getUpcomingAppointments({int limit = 5}) async {
    await loadUpcomingAppointments(limit: limit);
    return _upcomingAppointments;
  }

  Future<bool> isSlotTaken(DateTime date, String startTime, {int? excludeId}) =>
      _repository.isSlotTaken(date, startTime, excludeId: excludeId);

  Future<Map<String, dynamic>> getAppointmentStats(DateRange range) async {
    final inRange = _appointments.where((a) {
      final d = DateTime.tryParse(a.appointmentDate);
      if (d == null) return false;
      return !d.isBefore(range.start) && d.isBefore(range.endExclusive);
    }).toList();
    return {
      'total': inRange.length,
      'pending': inRange.where((a) => a.status == AppointmentStatus.pending).length,
      'completed': inRange.where((a) => a.status == AppointmentStatus.completed).length,
      'not_attended': inRange.where((a) => a.status == AppointmentStatus.notAttended).length,
      'cancelled': inRange.where((a) => a.status == AppointmentStatus.cancelled).length,
    };
  }

  DateTime _appointmentDateTime(Appointment appointment) {
    final date = DateTime.parse(appointment.appointmentDate);
    final parts = appointment.startTime.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}


extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
