/// A single service included in a package, at the package-specific amount.
/// This is master data used only when composing/selecting a package — once
/// a package is actually used in a visit/appointment, every field here is
/// snapshotted onto the visit/appointment row so later edits never change
/// historical transactions.
class PackageService {
  final int? id;
  final int packageId;
  final int? serviceId;
  final int? categoryId;
  final int? serviceTypeId;
  final String categoryNameSnapshot;
  final String? serviceTypeNameSnapshot;
  final String serviceNameSnapshot;

  /// The service's own default/normal price at the time it was added to the
  /// package. Never modified when the package price changes.
  final double normalPrice;

  /// The package-specific amount allocated to this service. Independent of
  /// [normalPrice] and never written back to `services.default_price`.
  final double packageServiceAmount;
  final int quantity;
  final String? createdDate;

  const PackageService({
    this.id,
    required this.packageId,
    this.serviceId,
    this.categoryId,
    this.serviceTypeId,
    required this.categoryNameSnapshot,
    this.serviceTypeNameSnapshot,
    required this.serviceNameSnapshot,
    required this.normalPrice,
    required this.packageServiceAmount,
    this.quantity = 1,
    this.createdDate,
  });

  factory PackageService.fromMap(Map<String, dynamic> map) {
    return PackageService(
      id: map['id'] as int?,
      packageId: map['package_id'] as int,
      serviceId: map['service_id'] as int?,
      categoryId: map['category_id'] as int?,
      serviceTypeId: map['service_type_id'] as int?,
      categoryNameSnapshot: map['category_name_snapshot'] as String? ?? '',
      serviceTypeNameSnapshot: map['service_type_name_snapshot'] as String?,
      serviceNameSnapshot: map['service_name_snapshot'] as String? ?? '',
      normalPrice: (map['normal_price'] as num? ?? 0).toDouble(),
      packageServiceAmount:
          (map['package_service_amount'] as num? ?? 0).toDouble(),
      quantity: map['quantity'] as int? ?? 1,
      createdDate: map['created_date'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'package_id': packageId,
      'service_id': serviceId,
      'category_id': categoryId,
      'service_type_id': serviceTypeId,
      'category_name_snapshot': categoryNameSnapshot,
      'service_type_name_snapshot': serviceTypeNameSnapshot,
      'service_name_snapshot': serviceNameSnapshot,
      'normal_price': normalPrice,
      'package_service_amount': packageServiceAmount,
      'quantity': quantity,
      'created_date': createdDate,
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
}

class Package {
  final int? id;
  final String name;
  final String? description;

  /// The bundled selling price. Independent of the sum of the individual
  /// service/package-service amounts.
  final double packagePrice;
  final String startDate; // yyyy-MM-dd
  final String expiryDate; // yyyy-MM-dd
  final bool isActive;
  final String createdDate;
  final String? updatedDate;

  /// Populated by [PackageDao.get]/[PackageDao.getAll]; not part of the flat
  /// `packages` row (stored in `package_services`).
  List<PackageService> services;

  Package({
    this.id,
    required this.name,
    this.description,
    required this.packagePrice,
    required this.startDate,
    required this.expiryDate,
    this.isActive = true,
    required this.createdDate,
    this.updatedDate,
    List<PackageService>? services,
  }) : services = services ?? const [];

  factory Package.fromMap(Map<String, dynamic> map) {
    return Package(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: map['description'] as String?,
      packagePrice: (map['package_price'] as num).toDouble(),
      startDate: map['start_date'] as String,
      expiryDate: map['expiry_date'] as String,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdDate: map['created_date'] as String,
      updatedDate: map['updated_date'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'package_price': packagePrice,
      'start_date': startDate,
      'expiry_date': expiryDate,
      'is_active': isActive ? 1 : 0,
      'created_date': createdDate,
      'updated_date': updatedDate,
    };
  }

  /// Sum of every included service's normal/default price (quantity-aware).
  /// This is the "Actual Total" shown alongside the package price — never
  /// used as the amount charged.
  double get normalTotal =>
      services.fold(0.0, (sum, s) => sum + s.normalPrice * s.quantity);

  double get discount => normalTotal - packagePrice;

  /// True if [date] (yyyy-MM-dd) falls within [startDate]..[expiryDate]
  /// inclusive and the package is active.
  bool isValidOn(String date) {
    if (!isActive) return false;
    return date.compareTo(startDate) >= 0 && date.compareTo(expiryDate) <= 0;
  }

  Package copyWith({
    int? id,
    String? name,
    String? description,
    double? packagePrice,
    String? startDate,
    String? expiryDate,
    bool? isActive,
    String? createdDate,
    String? updatedDate,
    List<PackageService>? services,
  }) {
    return Package(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      packagePrice: packagePrice ?? this.packagePrice,
      startDate: startDate ?? this.startDate,
      expiryDate: expiryDate ?? this.expiryDate,
      isActive: isActive ?? this.isActive,
      createdDate: createdDate ?? this.createdDate,
      updatedDate: updatedDate ?? this.updatedDate,
      services: services ?? this.services,
    );
  }
}

/// Result of validating a package against a proposed appointment/visit date,
/// re-checked both when the package is *selected* and again when the
/// appointment/visit is actually *processed* (per the package validity
/// business rules).
class PackageValidationResult {
  final bool isValid;
  final String? message;
  final Package? package;

  const PackageValidationResult._(this.isValid, this.message, this.package);

  factory PackageValidationResult.ok(Package package) =>
      PackageValidationResult._(true, null, package);

  factory PackageValidationResult.fail(String message) =>
      PackageValidationResult._(false, message, null);
}
