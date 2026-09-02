enum PaymentStatus { paid, partiallyPaid, pending, writtenOff }

extension PaymentStatusX on PaymentStatus {
  String get label {
    switch (this) {
      case PaymentStatus.paid: return 'PAID';
      case PaymentStatus.partiallyPaid: return 'PARTIALLY PAID';
      case PaymentStatus.pending: return 'PENDING';
      case PaymentStatus.writtenOff: return 'WRITTEN OFF';
    }
  }

  static PaymentStatus fromString(String s) {
    switch (s.toUpperCase()) {
      case 'PAID': return PaymentStatus.paid;
      case 'PARTIALLY_PAID': return PaymentStatus.partiallyPaid;
      case 'WRITTEN_OFF': return PaymentStatus.writtenOff;
      default: return PaymentStatus.pending;
    }
  }

  String get dbValue {
    switch (this) {
      case PaymentStatus.paid: return 'PAID';
      case PaymentStatus.partiallyPaid: return 'PARTIALLY_PAID';
      case PaymentStatus.pending: return 'PENDING';
      case PaymentStatus.writtenOff: return 'WRITTEN_OFF';
    }
  }
}

enum DiscountType { fixed, percent }

extension DiscountTypeX on DiscountType {
  String get dbValue => this == DiscountType.fixed ? 'FIXED' : 'PERCENT';
  static DiscountType fromString(String s) =>
      s.toUpperCase() == 'PERCENT' ? DiscountType.percent : DiscountType.fixed;
}

enum PaymentMethod { cash, upi, card, bankTransfer, other }

extension PaymentMethodX on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash: return 'Cash';
      case PaymentMethod.upi: return 'UPI';
      case PaymentMethod.card: return 'Card';
      case PaymentMethod.bankTransfer: return 'Bank Transfer';
      case PaymentMethod.other: return 'Other';
    }
  }

  String get dbValue {
    switch (this) {
      case PaymentMethod.cash: return 'CASH';
      case PaymentMethod.upi: return 'UPI';
      case PaymentMethod.card: return 'CARD';
      case PaymentMethod.bankTransfer: return 'BANK_TRANSFER';
      case PaymentMethod.other: return 'OTHER';
    }
  }

  static PaymentMethod fromString(String s) {
    switch (s.toUpperCase()) {
      case 'UPI': return PaymentMethod.upi;
      case 'CARD': return PaymentMethod.card;
      case 'BANK_TRANSFER': return PaymentMethod.bankTransfer;
      case 'OTHER': return PaymentMethod.other;
      default: return PaymentMethod.cash;
    }
  }

  static List<PaymentMethod> get all =>
      [PaymentMethod.cash, PaymentMethod.upi, PaymentMethod.card, PaymentMethod.bankTransfer, PaymentMethod.other];
}

class VisitService {
  final int? id;
  final int visitId;
  final int? serviceId; // nullable — service master row may be gone/optional
  final int? categoryId;
  final int? serviceTypeId;
  final String categoryNameSnapshot;
  final String? serviceTypeNameSnapshot;
  final String serviceNameSnapshot;
  final double price; // unit price
  final int quantity;
  final double total;
  final String? createdAt;

  const VisitService({
    this.id,
    required this.visitId,
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

  factory VisitService.fromMap(Map<String, dynamic> map) {
    return VisitService(
      id: map['id'] as int?,
      visitId: map['visit_id'] as int,
      serviceId: map['service_id'] as int?,
      categoryId: map['category_id'] as int?,
      serviceTypeId: map['service_type_id'] as int?,
      categoryNameSnapshot: map['category_name_snapshot'] as String? ?? '',
      serviceTypeNameSnapshot: map['service_type_name_snapshot'] as String?,
      serviceNameSnapshot: map['service_name_snapshot'] as String,
      price: (map['price'] as num).toDouble(),
      quantity: map['quantity'] as int? ?? 1,
      total: (map['total'] as num).toDouble(),
      createdAt: map['created_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'visit_id': visitId,
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

  /// "Category → ServiceType → Service" path derived purely from snapshot
  /// fields (never live joins) so historical bills never change.
  String get pathLabel {
    final parts = <String>[
      if (categoryNameSnapshot.isNotEmpty) categoryNameSnapshot,
      if (serviceTypeNameSnapshot != null && serviceTypeNameSnapshot!.isNotEmpty)
        serviceTypeNameSnapshot!,
      serviceNameSnapshot,
    ];
    return parts.join(' → ');
  }
}

class Visit {
  final int? id;
  final int customerId;
  final String visitDate;
  final double subtotal;
  final DiscountType discountType;
  final double discountValue;
  final double discountAmount;
  final double finalTotal;
  final double totalPaid;
  final double pendingAmount;
  final PaymentStatus paymentStatus;
  final String? notes;
  final String createdDate;

  // Joined fields
  String? customerName;
  String? customerPhone;
  List<VisitService> services;
  List<Payment> payments;

  Visit({
    this.id,
    required this.customerId,
    required this.visitDate,
    required this.subtotal,
    required this.discountType,
    required this.discountValue,
    required this.discountAmount,
    required this.finalTotal,
    required this.totalPaid,
    required this.pendingAmount,
    required this.paymentStatus,
    this.notes,
    required this.createdDate,
    this.customerName,
    this.customerPhone,
    this.services = const [],
    this.payments = const [],
  });

  factory Visit.fromMap(Map<String, dynamic> map) {
    return Visit(
      id: map['id'] as int?,
      customerId: map['customer_id'] as int,
      visitDate: map['visit_date'] as String,
      subtotal: (map['subtotal'] as num).toDouble(),
      discountType: DiscountTypeX.fromString(map['discount_type'] as String? ?? 'FIXED'),
      discountValue: (map['discount_value'] as num? ?? 0).toDouble(),
      discountAmount: (map['discount_amount'] as num? ?? 0).toDouble(),
      finalTotal: (map['final_total'] as num).toDouble(),
      totalPaid: (map['total_paid'] as num? ?? 0).toDouble(),
      pendingAmount: (map['pending_amount'] as num? ?? 0).toDouble(),
      paymentStatus: PaymentStatusX.fromString(map['payment_status'] as String? ?? 'PENDING'),
      notes: map['notes'] as String?,
      createdDate: map['created_date'] as String,
      customerName: map['customer_name'] as String?,
      customerPhone: map['customer_phone'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'customer_id': customerId,
      'visit_date': visitDate,
      'subtotal': subtotal,
      'discount_type': discountType.dbValue,
      'discount_value': discountValue,
      'discount_amount': discountAmount,
      'final_total': finalTotal,
      'total_paid': totalPaid,
      'pending_amount': pendingAmount,
      'payment_status': paymentStatus.dbValue,
      'notes': notes,
      'created_date': createdDate,
    };
  }

  Visit copyWith({
    int? id,
    double? totalPaid,
    double? pendingAmount,
    PaymentStatus? paymentStatus,
    List<Payment>? payments,
  }) {
    return Visit(
      id: id ?? this.id,
      customerId: customerId,
      visitDate: visitDate,
      subtotal: subtotal,
      discountType: discountType,
      discountValue: discountValue,
      discountAmount: discountAmount,
      finalTotal: finalTotal,
      totalPaid: totalPaid ?? this.totalPaid,
      pendingAmount: pendingAmount ?? this.pendingAmount,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      notes: notes,
      createdDate: createdDate,
      customerName: customerName,
      customerPhone: customerPhone,
      services: services,
      payments: payments ?? this.payments,
    );
  }
}

class Payment {
  final int? id;
  final int visitId;
  final String paymentDate;
  final double amount;
  final PaymentMethod paymentMethod;
  final String? notes;

  const Payment({
    this.id,
    required this.visitId,
    required this.paymentDate,
    required this.amount,
    required this.paymentMethod,
    this.notes,
  });

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'] as int?,
      visitId: map['visit_id'] as int,
      paymentDate: map['payment_date'] as String,
      amount: (map['amount'] as num).toDouble(),
      paymentMethod: PaymentMethodX.fromString(map['payment_method'] as String? ?? 'CASH'),
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'visit_id': visitId,
      'payment_date': paymentDate,
      'amount': amount,
      'payment_method': paymentMethod.dbValue,
      'notes': notes,
    };
  }
}

class WriteOff {
  final int? id;
  final int visitId;
  final double amount;
  final String writeOffDate;
  final String reason;
  final String? notes;

  const WriteOff({
    this.id,
    required this.visitId,
    required this.amount,
    required this.writeOffDate,
    required this.reason,
    this.notes,
  });

  factory WriteOff.fromMap(Map<String, dynamic> map) {
    return WriteOff(
      id: map['id'] as int?,
      visitId: map['visit_id'] as int,
      amount: (map['amount'] as num).toDouble(),
      writeOffDate: map['write_off_date'] as String,
      reason: map['reason'] as String? ?? '',
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'visit_id': visitId,
      'amount': amount,
      'write_off_date': writeOffDate,
      'reason': reason,
      'notes': notes,
    };
  }
}

class ExpenseCategory {
  final int? id;
  final String name;
  final bool isActive;

  const ExpenseCategory({
    this.id,
    required this.name,
    this.isActive = true,
  });

  factory ExpenseCategory.fromMap(Map<String, dynamic> map) {
    return ExpenseCategory(
      id: map['id'] as int?,
      name: map['name'] as String,
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'is_active': isActive ? 1 : 0,
    };
  }
}

class Expense {
  final int? id;
  final int expenseCategoryId;
  final String expenseDate;
  final String description;
  final double amount;
  final PaymentMethod paymentMethod;
  final String? notes;
  final String createdDate;
  String? categoryName;

  Expense({
    this.id,
    required this.expenseCategoryId,
    required this.expenseDate,
    required this.description,
    required this.amount,
    required this.paymentMethod,
    this.notes,
    required this.createdDate,
    this.categoryName,
  });

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as int?,
      expenseCategoryId: map['expense_category_id'] as int,
      expenseDate: map['expense_date'] as String,
      description: map['description'] as String,
      amount: (map['amount'] as num).toDouble(),
      paymentMethod: PaymentMethodX.fromString(map['payment_method'] as String? ?? 'CASH'),
      notes: map['notes'] as String?,
      createdDate: map['created_date'] as String,
      categoryName: map['category_name'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'expense_category_id': expenseCategoryId,
      'expense_date': expenseDate,
      'description': description,
      'amount': amount,
      'payment_method': paymentMethod.dbValue,
      'notes': notes,
      'created_date': createdDate,
    };
  }

  Expense copyWith({
    int? id,
    int? expenseCategoryId,
    String? expenseDate,
    String? description,
    double? amount,
    PaymentMethod? paymentMethod,
    String? notes,
    String? createdDate,
    String? categoryName,
  }) {
    return Expense(
      id: id ?? this.id,
      expenseCategoryId: expenseCategoryId ?? this.expenseCategoryId,
      expenseDate: expenseDate ?? this.expenseDate,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      createdDate: createdDate ?? this.createdDate,
      categoryName: categoryName ?? this.categoryName,
    );
  }
}
