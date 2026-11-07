/// Model for ISP subscription broadband plans.
class PlanDto {
  final int id;
  final String name;
  final String description;
  final double amount;
  final int? discountId;

  const PlanDto({
    required this.id,
    required this.name,
    required this.description,
    required this.amount,
    this.discountId,
  });

  factory PlanDto.fromJson(Map<String, dynamic> json) {
    return PlanDto(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      amount: json['amount'] is num
          ? (json['amount'] as num).toDouble()
          : double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      discountId: json['discountId'] is int
          ? json['discountId'] as int
          : int.tryParse(json['discountId']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'amount': amount,
        if (discountId != null) 'discountId': discountId,
      };

  String get formattedPrice => '₱${amount.toStringAsFixed(2)}';
}

/// Model for approved ISP ONT / Router hardware specifications.
class RouterDto {
  final int id;
  final String name; // e.g. "Huawei", "UT-KING", "ZTE"
  final String description; // e.g. "5v5", "UT-XP6486-S", "F670L"
  final String brand; // e.g. "DUAL BAND ONU MODEM"
  final String model;

  const RouterDto({
    required this.id,
    required this.name,
    required this.description,
    required this.brand,
    required this.model,
  });

  factory RouterDto.fromJson(Map<String, dynamic> json) {
    return RouterDto(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      brand: json['brand']?.toString().trim() ?? '',
      model: json['model']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'brand': brand,
        'model': model,
      };

  /// Full display name for UI pickers: e.g. "Huawei 5v5 (DUAL BAND ONU MODEM)"
  String get displayName {
    final parts = [name, description].where((s) => s.isNotEmpty).join(' ');
    if (brand.isNotEmpty) {
      return '$parts ($brand)';
    }
    return parts;
  }

  /// Compact specification: e.g. "Huawei 5v5"
  String get compactName =>
      [name, description].where((s) => s.isNotEmpty).join(' ');
}

/// Model for NAP items from `/api/Naps`.
class NapDto {
  final int id;
  final String name; // e.g. "NAP 001", "NAP 002", "test nap 1"
  final String description; // e.g. "NAP 001 Description"
  final int? createdByUserId;
  final DateTime? createdDate;

  const NapDto({
    required this.id,
    required this.name,
    this.description = '',
    this.createdByUserId,
    this.createdDate,
  });

  factory NapDto.fromJson(Map<String, dynamic> json) {
    return NapDto(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      createdByUserId: json['createdByUserId'] is int
          ? json['createdByUserId'] as int
          : int.tryParse(json['createdByUserId']?.toString() ?? ''),
      createdDate: json['createdDate'] != null
          ? DateTime.tryParse(json['createdDate'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        if (createdByUserId != null) 'createdByUserId': createdByUserId,
        if (createdDate != null) 'createdDate': createdDate!.toIso8601String(),
      };
}

/// Model for Port items from `/api/Ports`.
class PortDto {
  final int id;
  final String name; // e.g. "PORT 001", "PORT 002"
  final String description; // e.g. "PORT 001 Description"
  final int? createdByUserId;
  final DateTime? createdDate;

  const PortDto({
    required this.id,
    required this.name,
    this.description = '',
    this.createdByUserId,
    this.createdDate,
  });

  factory PortDto.fromJson(Map<String, dynamic> json) {
    return PortDto(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      createdByUserId: json['createdByUserId'] is int
          ? json['createdByUserId'] as int
          : int.tryParse(json['createdByUserId']?.toString() ?? ''),
      createdDate: json['createdDate'] != null
          ? DateTime.tryParse(json['createdDate'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        if (createdByUserId != null) 'createdByUserId': createdByUserId,
        if (createdDate != null) 'createdDate': createdDate!.toIso8601String(),
      };
}

// Gene - Oct 12, 2026: Added LcpOptionDto for LCP-first selection flow matching AppSheet hierarchy.
class LcpOptionDto {
  final int id;
  final String name; // e.g. "LCP 01", "LCP 02"
  final String description; // e.g. "Binangonan Central Cabinet"

  const LcpOptionDto({
    required this.id,
    required this.name,
    this.description = '',
  });

  factory LcpOptionDto.fromJson(Map<String, dynamic> json) {
    return LcpOptionDto(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
      };
}

// Gene - Oct 24, 2026: Model for items from GET /api/InventoryItem used for dynamic materials selection.
class InventoryItemDto {
  final int id;
  final String itemId;
  final String name;
  final String description;
  final String supplier;
  final int quantity;
  final String? image;
  final String? category;
  final String? userEmail;
  final DateTime? modifiedDate;

  const InventoryItemDto({
    required this.id,
    required this.itemId,
    required this.name,
    this.description = '',
    this.supplier = '',
    this.quantity = 0,
    this.image,
    this.category,
    this.userEmail,
    this.modifiedDate,
  });

  factory InventoryItemDto.fromJson(Map<String, dynamic> json) {
    return InventoryItemDto(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      itemId: json['itemId']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      supplier: json['supplier']?.toString().trim() ?? '',
      quantity: json['quantity'] is int
          ? json['quantity'] as int
          : int.tryParse(json['quantity']?.toString() ?? '0') ?? 0,
      image: json['image']?.toString().trim(),
      category: json['category']?.toString().trim(),
      userEmail: json['userEmail']?.toString().trim(),
      modifiedDate: json['modifiedDate'] != null
          ? DateTime.tryParse(json['modifiedDate'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'itemId': itemId,
        'name': name,
        'description': description,
        'supplier': supplier,
        'quantity': quantity,
        if (image != null) 'image': image,
        if (category != null) 'category': category,
        if (userEmail != null) 'userEmail': userEmail,
        if (modifiedDate != null)
          'modifiedDate': modifiedDate!.toIso8601String(),
      };
}
