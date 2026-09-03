import 'package:flutter/foundation.dart';

import '../database/database.dart';
import '../models/appointment_models.dart';
import '../models/visit_models.dart';
import '../services/notification_service.dart';
import '../utils/formatters.dart';

class AppointmentProvider extends ChangeNotifier {
  final _appointmentDao = AppointmentDao();
  final _visitDao = VisitDao();
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

    _appointments = await _appointmentDao.getAll(
      date: date,
      startDate: startDate,
      endDate: endDate,
      customerId: customerId,
      status: status,
    );
    _isLoading = false;
    notifyListeners();
  }

  Future<Appointment?> getAppointment(int id) => _appointmentDao.get(id);

  Future<List<Appointment>> getForCustomer(int customerId) =>
      _appointmentDao.getForCustomer(customerId);

  Future<int> addAppointment(Appointment appointment) async {
    final id = await _appointmentDao.insert(appointment);
    final saved = appointment.copyWith(id: id);
    await _notifications.scheduleAppointmentReminder(saved);
    await _reloadCurrentLists();
    return id;
  }

  Future<void> updateAppointment(Appointment appointment) async {
    await _appointmentDao.update(appointment);
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

  Future<int> markCompleted(Appointment appointment) async {
    final latest = await _appointmentDao.get(appointment.id!);
    if (latest == null) {
      throw Exception('Appointment not found.');
    }

    final service = latest.serviceId != null
        ? await _serviceDao.get(latest.serviceId!)
        : null;
    final category = latest.categoryId != null
        ? await _categoryDao.get(latest.categoryId!)
        : null;
    final serviceType = latest.serviceTypeId != null
        ? await _serviceTypeDao.get(latest.serviceTypeId!)
        : null;

    final categoryName = service?.categoryName ?? category?.name ?? '';
    final serviceTypeName = service?.serviceTypeName ?? serviceType?.name;
    final price = service?.defaultPrice ?? 0.0;
    final visitDate = _appointmentDateTime(latest).toIso8601String();
    final createdDate = DateTime.now().toIso8601String();

    final visit = Visit(
      customerId: latest.customerId,
      visitDate: visitDate,
      subtotal: price,
      discountType: DiscountType.fixed,
      discountValue: 0,
      discountAmount: 0,
      finalTotal: price,
      totalPaid: 0,
      pendingAmount: price,
      paymentStatus: PaymentStatus.pending,
      notes: latest.notes,
      createdDate: createdDate,
      customerName: latest.customerName,
      customerPhone: latest.customerPhone,
    );

    final visitServices = [
      VisitService(
        visitId: 0,
        serviceId: latest.serviceId,
        categoryId: latest.categoryId,
        serviceTypeId: latest.serviceTypeId,
        categoryNameSnapshot: categoryName,
        serviceTypeNameSnapshot: serviceTypeName,
        serviceNameSnapshot: latest.serviceNameSnapshot,
        price: price,
        total: price,
        createdAt: createdDate,
      ),
    ];

    final visitId =
        await _visitDao.insertVisit(visit, visitServices, const <Payment>[]);
    await _appointmentDao.updateStatus(
      latest.id!,
      AppointmentStatus.completed,
      visitId: visitId,
    );
    await _notifications.cancelReminder(latest.id!);
    await _reloadCurrentLists();
    return visitId;
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
