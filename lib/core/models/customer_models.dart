class Customer {
  final int? id;
  final String name;
  final String? phone;
  final String? birthDate; // ISO date string yyyy-MM-dd
  final String? notes;
  final String createdDate;
  final bool isActive;

  const Customer({
    this.id,
    required this.name,
    this.phone,
    this.birthDate,
    this.notes,
    required this.createdDate,
    this.isActive = true,
  });

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as int?,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      birthDate: map['birth_date'] as String?,
      notes: map['notes'] as String?,
      createdDate: map['created_date'] as String,
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'phone': phone,
      'birth_date': birthDate,
      'notes': notes,
      'created_date': createdDate,
      'is_active': isActive ? 1 : 0,
    };
  }

  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    String? birthDate,
    String? notes,
    String? createdDate,
    bool? isActive,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      birthDate: birthDate ?? this.birthDate,
      notes: notes ?? this.notes,
      createdDate: createdDate ?? this.createdDate,
      isActive: isActive ?? this.isActive,
    );
  }
}

class Category {
  final int? id;
  final String name;
  final String? description;
  final bool isActive;
  final String createdDate;
  final String? updatedDate;
  final int displayOrder;

  // Joined/aggregated fields (not persisted directly).
  int serviceCount;
  int serviceTypeCount;

  Category({
    this.id,
    required this.name,
    this.description,
    this.isActive = true,
    required this.createdDate,
    this.updatedDate,
    this.displayOrder = 0,
    this.serviceCount = 0,
    this.serviceTypeCount = 0,
  });

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: map['description'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdDate: map['created_date'] as String,
      updatedDate: map['updated_date'] as String?,
      displayOrder: map['display_order'] as int? ?? 0,
      serviceCount: map['service_count'] as int? ?? 0,
      serviceTypeCount: map['service_type_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'is_active': isActive ? 1 : 0,
      'created_date': createdDate,
      'updated_date': updatedDate,
      'display_order': displayOrder,
    };
  }

  Category copyWith({
    int? id,
    String? name,
    String? description,
    bool? isActive,
    String? createdDate,
    String? updatedDate,
    int? displayOrder,
    int? serviceCount,
    int? serviceTypeCount,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdDate: createdDate ?? this.createdDate,
      updatedDate: updatedDate ?? this.updatedDate,
      displayOrder: displayOrder ?? this.displayOrder,
      serviceCount: serviceCount ?? this.serviceCount,
      serviceTypeCount: serviceTypeCount ?? this.serviceTypeCount,
    );
  }
}

/// Sub-category level between [Category] and [Service] (e.g. "Rica Wax" under
/// the "Wax" category). Optional — a service can hang directly off a category.
class ServiceType {
  final int? id;
  final int categoryId;
  final String name;
  final String? description;
  final bool isActive;
  final String createdDate;
  final String? updatedDate;
  final int displayOrder;

  // Joined/aggregated fields.
  String? categoryName;
  int serviceCount;

  ServiceType({
    this.id,
    required this.categoryId,
    required this.name,
    this.description,
    this.isActive = true,
    required this.createdDate,
    this.updatedDate,
    this.displayOrder = 0,
    this.categoryName,
    this.serviceCount = 0,
  });

  factory ServiceType.fromMap(Map<String, dynamic> map) {
    return ServiceType(
      id: map['id'] as int?,
      categoryId: map['category_id'] as int,
      name: map['name'] as String,
      description: map['description'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdDate: map['created_date'] as String,
      updatedDate: map['updated_date'] as String?,
      displayOrder: map['display_order'] as int? ?? 0,
      categoryName: map['category_name'] as String?,
      serviceCount: map['service_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'category_id': categoryId,
      'name': name,
      'description': description,
      'is_active': isActive ? 1 : 0,
      'created_date': createdDate,
      'updated_date': updatedDate,
      'display_order': displayOrder,
    };
  }

  ServiceType copyWith({
    int? id,
    int? categoryId,
    String? name,
    String? description,
    bool? isActive,
    String? createdDate,
    String? updatedDate,
    int? displayOrder,
    String? categoryName,
    int? serviceCount,
  }) {
    return ServiceType(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdDate: createdDate ?? this.createdDate,
      updatedDate: updatedDate ?? this.updatedDate,
      displayOrder: displayOrder ?? this.displayOrder,
      categoryName: categoryName ?? this.categoryName,
      serviceCount: serviceCount ?? this.serviceCount,
    );
  }
}

class Service {
  final int? id;
  final int categoryId;
  final int? serviceTypeId; // optional — a service may sit directly under a category
  final String name;
  final double defaultPrice;
  final String? description;
  final bool isActive;
  final String createdDate;
  final String? updatedDate;
  final int displayOrder;
  final bool isFavorite;

  // Joined fields.
  String? categoryName;
  String? serviceTypeName;

  Service({
    this.id,
    required this.categoryId,
    this.serviceTypeId,
    required this.name,
    required this.defaultPrice,
    this.description,
    this.isActive = true,
    required this.createdDate,
    this.updatedDate,
    this.displayOrder = 0,
    this.isFavorite = false,
    this.categoryName,
    this.serviceTypeName,
  });

  factory Service.fromMap(Map<String, dynamic> map) {
    return Service(
      id: map['id'] as int?,
      categoryId: map['category_id'] as int,
      serviceTypeId: map['service_type_id'] as int?,
      name: map['name'] as String,
      defaultPrice: (map['default_price'] as num).toDouble(),
      description: map['description'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdDate: map['created_date'] as String,
      updatedDate: map['updated_date'] as String?,
      displayOrder: map['display_order'] as int? ?? 0,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      categoryName: map['category_name'] as String?,
      serviceTypeName: map['service_type_name'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'category_id': categoryId,
      'service_type_id': serviceTypeId,
      'name': name,
      'default_price': defaultPrice,
      'description': description,
      'is_active': isActive ? 1 : 0,
      'created_date': createdDate,
      'updated_date': updatedDate,
      'display_order': displayOrder,
      'is_favorite': isFavorite ? 1 : 0,
    };
  }

  Service copyWith({
    int? id,
    int? categoryId,
    int? serviceTypeId,
    bool clearServiceTypeId = false,
    String? name,
    double? defaultPrice,
    String? description,
    bool? isActive,
    String? createdDate,
    String? updatedDate,
    int? displayOrder,
    bool? isFavorite,
    String? categoryName,
    String? serviceTypeName,
  }) {
    return Service(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      serviceTypeId: clearServiceTypeId ? null : (serviceTypeId ?? this.serviceTypeId),
      name: name ?? this.name,
      defaultPrice: defaultPrice ?? this.defaultPrice,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdDate: createdDate ?? this.createdDate,
      updatedDate: updatedDate ?? this.updatedDate,
      displayOrder: displayOrder ?? this.displayOrder,
      isFavorite: isFavorite ?? this.isFavorite,
      categoryName: categoryName ?? this.categoryName,
      serviceTypeName: serviceTypeName ?? this.serviceTypeName,
    );
  }
}
