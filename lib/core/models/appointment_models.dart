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
  });

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
    );
  }
}
