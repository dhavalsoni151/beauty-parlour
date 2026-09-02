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
  final int displayOrder;
  int serviceCount;

  Category({
    this.id,
    required this.name,
    this.description,
    this.isActive = true,
    required this.createdDate,
    this.displayOrder = 0,
    this.serviceCount = 0,
  });

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: map['description'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdDate: map['created_date'] as String,
      displayOrder: map['display_order'] as int? ?? 0,
      serviceCount: map['service_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'is_active': isActive ? 1 : 0,
      'created_date': createdDate,
      'display_order': displayOrder,
    };
  }

  Category copyWith({
    int? id,
    String? name,
    String? description,
    bool? isActive,
    String? createdDate,
    int? displayOrder,
    int? serviceCount,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdDate: createdDate ?? this.createdDate,
      displayOrder: displayOrder ?? this.displayOrder,
      serviceCount: serviceCount ?? this.serviceCount,
    );
  }
}

class Service {
  final int? id;
  final int categoryId;
  final String name;
  final double defaultPrice;
  final String? description;
  final bool isActive;
  final String createdDate;
  String? categoryName;

  Service({
    this.id,
    required this.categoryId,
    required this.name,
    required this.defaultPrice,
    this.description,
    this.isActive = true,
    required this.createdDate,
    this.categoryName,
  });

  factory Service.fromMap(Map<String, dynamic> map) {
    return Service(
      id: map['id'] as int?,
      categoryId: map['category_id'] as int,
      name: map['name'] as String,
      defaultPrice: (map['default_price'] as num).toDouble(),
      description: map['description'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdDate: map['created_date'] as String,
      categoryName: map['category_name'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'category_id': categoryId,
      'name': name,
      'default_price': defaultPrice,
      'description': description,
      'is_active': isActive ? 1 : 0,
      'created_date': createdDate,
    };
  }

  Service copyWith({
    int? id,
    int? categoryId,
    String? name,
    double? defaultPrice,
    String? description,
    bool? isActive,
    String? createdDate,
    String? categoryName,
  }) {
    return Service(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      defaultPrice: defaultPrice ?? this.defaultPrice,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdDate: createdDate ?? this.createdDate,
      categoryName: categoryName ?? this.categoryName,
    );
  }
}
