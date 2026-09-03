import 'package:flutter/foundation.dart';

import '../database/database.dart';
import '../models/appointment_models.dart';
import '../models/visit_models.dart';
import '../services/notification_service.dart';
import '../utils/formatters.dart';

class AppointmentProvider extends ChangeNotifier {
  final _appointmentDao = AppointmentDao();
  final _serviceDao = ServiceDao();
  final _categoryDao = CategoryDao();
  final _serviceTypeDao = ServiceTypeDao();
  final _reportDao = ReportDao();
  final _notifications = NotificationService.instance;

  List<Appointment> _appointments = [];
  List<Appointment> _upcomingAppointments = [];
  bool _isLoading = false;

  DateTime? _lastDateFilter;
  String? _lastStartDate;
  String? _lastEndDate;
  AppointmentStatus? _lastStatusFilter;
  int? _lastCustomerId;

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
    _lastDateFilter = date;
    _lastStartDate = startDate;
    _lastEndDate = endDate;
    _lastCustomerId = customerId;
    _lastStatusFilter = status;
    notifyListeners();

    try {
      _appointments = await _appointmentDao.getAll(
        date: date,
        startDate: startDate,
        endDate: endDate,
        customerId: customerId,
        status: status,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Appointment?> getAppointment(int id) => _appointmentDao.get(id);

  Future<List<Appointment>> getForCustomer(int customerId) =>
      _appointmentDao.getForCustomer(customerId);

  Future<int> addAppointment(Appointment appointment,
      {List<AppointmentService> services = const []}) async {
    final id = await _appointmentDao.insert(appointment, services: services);
    final saved = appointment.copyWith(id: id);
    await _notifications.scheduleAppointmentReminder(saved);
    await _reloadCurrentLists();
    return id;
  }

  Future<void> updateAppointment(Appointment appointment,
      {List<AppointmentService>? services}) async {
    await _appointmentDao.update(appointment, services: services);
    final refreshed = await _appointmentDao.get(appointment.id!);
    if (refreshed != null) {
      if (refreshed.status == AppointmentStatus.pending) {
        await _notifications.scheduleAppointmentReminder(refreshed);
      } else {
        await _notifications.cancelReminder(refreshed.id!);
      }
    }
    await _reloadCurrentLists();
  }

  Future<void> cancelAppointment(int id) async {
    await _appointmentDao.updateStatus(id, AppointmentStatus.cancelled);
    await _notifications.cancelReminder(id);
    await _reloadCurrentLists();
  }

  Future<void> markNotAttended(int id) async {
    await _appointmentDao.updateStatus(id, AppointmentStatus.notAttended);
    await _notifications.cancelReminder(id);
    await _reloadCurrentLists();
  }

  /// Builds the (unsaved) visit + visit-service prefill for "Mark Completed".
  /// The caller (New Visit screen) shows this to the user for review/edits;
  /// nothing is written to the database until the visit is actually saved.
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

    // Legacy fallback for appointments created before multi-service support.
    if (appointment.serviceId == null &&
        appointment.serviceNameSnapshot.isEmpty) {
      return const [];
    }
    final service = appointment.serviceId != null
        ? await _serviceDao.get(appointment.serviceId!)
        : null;
    final category = appointment.categoryId != null
        ? await _categoryDao.get(appointment.categoryId!)
        : null;
    final serviceType = appointment.serviceTypeId != null
        ? await _serviceTypeDao.get(appointment.serviceTypeId!)
        : null;
    final categoryName = service?.categoryName ?? category?.name ?? '';
    final serviceTypeName = service?.serviceTypeName ?? serviceType?.name;
    final price = service?.defaultPrice ?? 0.0;
    return [
      VisitService(
        visitId: 0,
        serviceId: appointment.serviceId,
        categoryId: appointment.categoryId,
        serviceTypeId: appointment.serviceTypeId,
        categoryNameSnapshot: categoryName,
        serviceTypeNameSnapshot: serviceTypeName,
        serviceNameSnapshot: appointment.serviceNameSnapshot,
        price: price,
        total: price,
        createdAt: DateTime.now().toIso8601String(),
      ),
    ];
  }

  /// Links an already-saved visit (created from the prefilled New Visit
  /// screen) back to its source appointment and marks it completed.
  Future<void> completeWithVisit(int appointmentId, int visitId) async {
    final latest = await _appointmentDao.get(appointmentId);
    if (latest == null) {
      throw Exception('Appointment not found.');
    }
    if (latest.status != AppointmentStatus.pending) {
      throw Exception('Only pending appointments can be completed.');
    }
    await _appointmentDao.updateStatus(
      appointmentId,
      AppointmentStatus.completed,
      visitId: visitId,
    );
    await _notifications.cancelReminder(appointmentId);
    await _reloadCurrentLists();
  }

  Future<void> deleteAppointment(int id) async {
    await _appointmentDao.delete(id);
    await _notifications.cancelReminder(id);
    await _reloadCurrentLists();
  }

  Future<void> loadUpcomingAppointments({int limit = 5}) async {
    _upcomingAppointments = await _appointmentDao.getUpcoming(limit: limit);
    notifyListeners();
  }

  Future<List<Appointment>> getUpcomingAppointments({int limit = 5}) async {
    final items = await _appointmentDao.getUpcoming(limit: limit);
    _upcomingAppointments = items;
    notifyListeners();
    return items;
  }

  Future<bool> isSlotTaken(DateTime date, String startTime, {int? excludeId}) {
    return _appointmentDao.isSlotTaken(date, startTime, excludeId: excludeId);
  }

  Future<Map<String, dynamic>> getAppointmentStats(DateRange range) {
    return _reportDao.getAppointmentStats(
      range.start.toIso8601String(),
      range.endExclusive.toIso8601String(),
    );
  }

  Future<void> _reloadCurrentLists() async {
    await loadAppointments(
      date: _lastDateFilter,
      startDate: _lastStartDate,
      endDate: _lastEndDate,
      customerId: _lastCustomerId,
      status: _lastStatusFilter,
    );
    await loadUpcomingAppointments(limit: _upcomingAppointments.isEmpty
        ? 5
        : _upcomingAppointments.length);
  }

  DateTime _appointmentDateTime(Appointment appointment) {
    final date = DateTime.parse(appointment.appointmentDate);
    final parts = appointment.startTime.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }
}
