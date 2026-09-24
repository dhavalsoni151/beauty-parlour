import 'visit_models.dart';

/// Lifecycle status of a single reminder action for a customer.
///
/// The app only opens WhatsApp — it cannot know whether the message was
/// actually delivered or read, so the furthest "positive" status recorded is
/// [opened]. Nothing here claims delivery.
enum ReminderStatus { suggested, previewed, opened, dismissed }

extension ReminderStatusX on ReminderStatus {
  String get dbValue {
    switch (this) {
      case ReminderStatus.suggested:
        return 'SUGGESTED';
      case ReminderStatus.previewed:
        return 'PREVIEWED';
      case ReminderStatus.opened:
        return 'WHATSAPP_OPENED';
      case ReminderStatus.dismissed:
        return 'DISMISSED';
    }
  }

  String get label {
    switch (this) {
      case ReminderStatus.suggested:
        return 'Suggested';
      case ReminderStatus.previewed:
        return 'Previewed';
      case ReminderStatus.opened:
        return 'WhatsApp Opened';
      case ReminderStatus.dismissed:
        return 'Dismissed';
    }
  }

  static ReminderStatus fromString(String s) {
    switch (s.toUpperCase()) {
      case 'PREVIEWED':
        return ReminderStatus.previewed;
      case 'WHATSAPP_OPENED':
        return ReminderStatus.opened;
      case 'DISMISSED':
        return ReminderStatus.dismissed;
      default:
        return ReminderStatus.suggested;
    }
  }
}

/// One recorded reminder action. Purely marketing metadata — it never touches
/// sales/visit/payment/package figures, so reports are unaffected.
class Reminder {
  final int? id;
  final int customerId;
  final String reminderDate;
  final ReminderStatus status;
  final String? reason;
  final int? lastVisitId;
  final int? daysSinceVisit;
  final String? createdDate;

  // Joined field (customer name), populated by DAO queries.
  String? customerName;

  Reminder({
    this.id,
    required this.customerId,
    required this.reminderDate,
    this.status = ReminderStatus.suggested,
    this.reason,
    this.lastVisitId,
    this.daysSinceVisit,
    this.createdDate,
    this.customerName,
  });

  factory Reminder.fromMap(Map<String, dynamic> map) {
    return Reminder(
      id: map['id'] as int?,
      customerId: map['customer_id'] as int,
      reminderDate: map['reminder_date'] as String,
      status: ReminderStatusX.fromString(map['status'] as String? ?? 'SUGGESTED'),
      reason: map['reason'] as String?,
      lastVisitId: map['last_visit_id'] as int?,
      daysSinceVisit: map['days_since_visit'] as int?,
      createdDate: map['created_date'] as String?,
      customerName: map['customer_name'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'customer_id': customerId,
      'reminder_date': reminderDate,
      'status': status.dbValue,
      'reason': reason,
      'last_visit_id': lastVisitId,
      'days_since_visit': daysSinceVisit,
      'created_date': createdDate,
    };
  }
}

/// A customer eligible for a "haven't visited in X days" reminder, derived
/// entirely from the customer's *latest* completed visit (see ReminderDao).
///
/// The [daysSinceVisit] / [lastVisitAmount] always describe the latest visit —
/// never a particular service — so a small recent visit correctly resets the
/// clock, and the amount is the visit's final bill total.
class ReminderCandidate {
  final CustomerInfo customer;

  /// Null when the customer has never completed a visit.
  final int? lastVisitId;
  final DateTime? lastVisitDate;

  /// Latest visit final bill total. Null when there is no visit.
  final double? lastVisitAmount;

  /// Days since [lastVisitDate]. Null when there is no visit.
  final int? daysSinceVisit;

  final List<VisitService> services;

  /// Package snapshot from the latest visit (null when no package was used).
  final int? packageId;
  final String? packageName;
  final double? packageNormalTotal;
  final double? packagePrice;
  final double? packageDiscount;

  /// Paid / pending on the latest visit (used by the expandable details view).
  final double? visitTotalPaid;
  final double? visitPendingAmount;

  bool get hasVisit => lastVisitId != null;
  bool get hasPackage => packageId != null;

  const ReminderCandidate({
    required this.customer,
    this.lastVisitId,
    this.lastVisitDate,
    this.lastVisitAmount,
    this.daysSinceVisit,
    this.services = const [],
    this.packageId,
    this.packageName,
    this.packageNormalTotal,
    this.packagePrice,
    this.packageDiscount,
    this.visitTotalPaid,
    this.visitPendingAmount,
  });

  ReminderCandidate copyWithServices(List<VisitService> services) {
    return ReminderCandidate(
      customer: customer,
      lastVisitId: lastVisitId,
      lastVisitDate: lastVisitDate,
      lastVisitAmount: lastVisitAmount,
      daysSinceVisit: daysSinceVisit,
      services: services,
      packageId: packageId,
      packageName: packageName,
      packageNormalTotal: packageNormalTotal,
      packagePrice: packagePrice,
      packageDiscount: packageDiscount,
      visitTotalPaid: visitTotalPaid,
      visitPendingAmount: visitPendingAmount,
    );
  }
}

/// Minimal customer info carried by a [ReminderCandidate] (kept independent of
/// the full Customer model so the DAO can return exactly what the screen needs).
class CustomerInfo {
  final int id;
  final String name;
  final String? phone;

  const CustomerInfo({required this.id, required this.name, this.phone});
}
