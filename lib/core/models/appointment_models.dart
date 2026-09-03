enum AppointmentStatus { pending, completed, notAttended, cancelled }

extension AppointmentStatusX on AppointmentStatus {
  String get label {
    switch (this) {
      case AppointmentStatus.pending:
        return 'PENDING';
      case AppointmentStatus.completed:
        return 'COMPLETED';
      case AppointmentStatus.notAttended:
        return 'NOT ATTENDED';
      case AppointmentStatus.cancelled:
        return 'CANCELLED';
    }
  }

  static AppointmentStatus fromString(String s) {
    switch (s.toUpperCase()) {
      case 'COMPLETED':
        return AppointmentStatus.completed;
      case 'NOT_ATTENDED':
        return AppointmentStatus.notAttended;
      case 'CANCELLED':
        return AppointmentStatus.cancelled;
      default:
        return AppointmentStatus.pending;
    }
  }

  String get dbValue {
    switch (this) {
      case AppointmentStatus.pending:
        return 'PENDING';
      case AppointmentStatus.completed:
        return 'COMPLETED';
      case AppointmentStatus.notAttended:
        return 'NOT_ATTENDED';
      case AppointmentStatus.cancelled:
        return 'CANCELLED';
    }
  }
}

/// One service booked as part of an appointment. Mirrors [VisitService] so
/// that "mark completed" can carry every field straight over to the visit
/// it creates without any lossy re-derivation.
class AppointmentService {
  final int? id;
  final int appointmentId;
  final int? serviceId;
  final int? categoryId;
  final int? serviceTypeId;
  final String categoryNameSnapshot;
  final String? serviceTypeNameSnapshot;
  final String serviceNameSnapshot;
  final double price;
  final int quantity;
  final double total;
  final String? createdAt;

  const AppointmentService({
    this.id,
    required this.appointmentId,
    this.serviceId,
    this.categoryId,
    this.serviceTypeId,
    required this.categoryNameSnapshot,
    this.serviceTypeNameSnapshot,
    required this.serviceNameSnapshot,
    required this.price,
    this.quantity = 1,
    required this.total,
    this.createdAt,
  });

  factory AppointmentService.fromMap(Map<String, dynamic> map) {
    return AppointmentService(
      id: map['id'] as int?,
      appointmentId: map['appointment_id'] as int,
      serviceId: map['service_id'] as int?,
      categoryId: map['category_id'] as int?,
      serviceTypeId: map['service_type_id'] as int?,
      categoryNameSnapshot: map['category_name_snapshot'] as String? ?? '',
      serviceTypeNameSnapshot: map['service_type_name_snapshot'] as String?,
      serviceNameSnapshot: map['service_name_snapshot'] as String? ?? '',
      price: (map['price'] as num? ?? 0).toDouble(),
      quantity: map['quantity'] as int? ?? 1,
      total: (map['total'] as num? ?? 0).toDouble(),
      createdAt: map['created_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'appointment_id': appointmentId,
      'service_id': serviceId,
      'category_id': categoryId,
      'service_type_id': serviceTypeId,
      'category_name_snapshot': categoryNameSnapshot,
      'service_type_name_snapshot': serviceTypeNameSnapshot,
      'service_name_snapshot': serviceNameSnapshot,
      'price': price,
      'quantity': quantity,
      'total': total,
      'created_at': createdAt,
    };
  }

  String get pathLabel {
    final parts = <String>[
      if (categoryNameSnapshot.isNotEmpty) categoryNameSnapshot,
      if (serviceTypeNameSnapshot != null && serviceTypeNameSnapshot!.isNotEmpty)
        serviceTypeNameSnapshot!,
      serviceNameSnapshot,
    ];
    return parts.join(' → ');
  }

  AppointmentService copyWith({
    int? id,
    int? appointmentId,
    int? serviceId,
    int? categoryId,
    int? serviceTypeId,
    String? categoryNameSnapshot,
    String? serviceTypeNameSnapshot,
    String? serviceNameSnapshot,
    double? price,
    int? quantity,
    double? total,
    String? createdAt,
  }) {
    return AppointmentService(
      id: id ?? this.id,
      appointmentId: appointmentId ?? this.appointmentId,
      serviceId: serviceId ?? this.serviceId,
      categoryId: categoryId ?? this.categoryId,
      serviceTypeId: serviceTypeId ?? this.serviceTypeId,
      categoryNameSnapshot: categoryNameSnapshot ?? this.categoryNameSnapshot,
      serviceTypeNameSnapshot:
          serviceTypeNameSnapshot ?? this.serviceTypeNameSnapshot,
      serviceNameSnapshot: serviceNameSnapshot ?? this.serviceNameSnapshot,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      total: total ?? this.total,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class Appointment {
  final int? id;
  final int customerId;
  final int? serviceId;
  final int? categoryId;
  final int? serviceTypeId;
  final String serviceNameSnapshot;
  final String appointmentDate;
  final String startTime;
  final String? endTime;
  final AppointmentStatus status;
  final String? notes;
  final int? visitId;
  final int? reminderMinutesBefore;
  final String createdDate;
  final String? updatedDate;

  String? customerName;
  String? customerPhone;

  /// All services booked for this appointment. Populated by
  /// [AppointmentDao.get]/[AppointmentDao.getAll]; not part of the flat
  /// `appointments` row (stored in `appointment_services`).
  List<AppointmentService> services;

  Appointment({
    this.id,
    required this.customerId,
    this.serviceId,
    this.categoryId,
    this.serviceTypeId,
    required this.serviceNameSnapshot,
    required this.appointmentDate,
    required this.startTime,
    this.endTime,
    this.status = AppointmentStatus.pending,
    this.notes,
    this.visitId,
    this.reminderMinutesBefore,
    required this.createdDate,
    this.updatedDate,
    this.customerName,
    this.customerPhone,
    List<AppointmentService>? services,
  }) : services = services ?? const [];

  factory Appointment.fromMap(Map<String, dynamic> map) {
    return Appointment(
      id: map['id'] as int?,
      customerId: map['customer_id'] as int,
      serviceId: map['service_id'] as int?,
      categoryId: map['category_id'] as int?,
      serviceTypeId: map['service_type_id'] as int?,
      serviceNameSnapshot: map['service_name_snapshot'] as String? ?? '',
      appointmentDate: map['appointment_date'] as String,
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String?,
      status: AppointmentStatusX.fromString(
          map['status'] as String? ?? AppointmentStatus.pending.dbValue),
      notes: map['notes'] as String?,
      visitId: map['visit_id'] as int?,
      reminderMinutesBefore: map['reminder_minutes_before'] as int?,
      createdDate: map['created_date'] as String,
      updatedDate: map['updated_date'] as String?,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'customer_id': customerId,
      'service_id': serviceId,
      'category_id': categoryId,
      'service_type_id': serviceTypeId,
      'service_name_snapshot': serviceNameSnapshot,
      'appointment_date': appointmentDate,
      'start_time': startTime,
      'end_time': endTime,
      'status': status.dbValue,
      'notes': notes,
      'visit_id': visitId,
      'reminder_minutes_before': reminderMinutesBefore,
      'created_date': createdDate,
      'updated_date': updatedDate,
    };
  }

  Appointment copyWith({
    int? id,
    int? customerId,
    int? serviceId,
    int? categoryId,
    int? serviceTypeId,
    String? serviceNameSnapshot,
    String? appointmentDate,
    String? startTime,
    String? endTime,
    AppointmentStatus? status,
    String? notes,
    int? visitId,
    int? reminderMinutesBefore,
    String? createdDate,
    String? updatedDate,
    String? customerName,
    String? customerPhone,
    List<AppointmentService>? services,
  }) {
    return Appointment(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      serviceId: serviceId ?? this.serviceId,
      categoryId: categoryId ?? this.categoryId,
      serviceTypeId: serviceTypeId ?? this.serviceTypeId,
      serviceNameSnapshot: serviceNameSnapshot ?? this.serviceNameSnapshot,
      appointmentDate: appointmentDate ?? this.appointmentDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      visitId: visitId ?? this.visitId,
      reminderMinutesBefore:
          reminderMinutesBefore ?? this.reminderMinutesBefore,
      createdDate: createdDate ?? this.createdDate,
      updatedDate: updatedDate ?? this.updatedDate,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      services: services ?? this.services,
    );
  }
}
