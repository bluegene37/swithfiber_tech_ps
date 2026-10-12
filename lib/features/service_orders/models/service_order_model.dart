import 'dart:convert';
import 'package:latlong2/latlong.dart';
import '../../../core/services/photo_storage_service.dart';
import '../../../core/database/sql_values.dart';

/// Data Transfer Object representing a Field Repair / Trouble Ticket / Service Order.
class ServiceOrderDto {
  final int id;
  final String accountNumber;
  final String fullName;
  final String contactNumber;
  final String emailAddress;
  final String address;
  final String? barangay;
  final String? city;
  final String? provider;
  final String? plan;
  final String? username; // RADIUS PPPoE username
  final String? connectionType;
  final String? routerModemSN;
  final String? lcp;
  final String? nap;
  final String? port;
  final String? vlan;
  final String supportStatus;
  final String
      concern; // e.g. "Pullout", "No Connection", "High Loss", "Relocation"
  final String?
      priorityLevel; // e.g. "Urgent", "High", "Normal", "System Generated"
  final String? visitStatus; // e.g. "In Progress", "Done", "Pending"
  final String? visitBy;
  final String? visitRemarks;
  final String? assignedEmail;
  final DateTime? createdDate;
  final DateTime? dateInstalled;

  // Equipment Swaps & Pullouts
  final String? newRouterModemSN;
  final String? newLCP;
  final String? newNAP;
  final String? newPORT;
  final String? newVLAN;
  final String? routerModel;
  final String? pulloutRouterModel;
  final String? pulloutRouterModelSN;
  final String? pulloutRemarks;

  // Materials & Consumables (1 to 10)
  final Map<String, int> materialsUsed;

  // Proofs & Signatures
  final String? clientSignature;
  final String? image1;
  final String? image2;
  final String? image3;
  final String? houseFrontPicture;
  final String? addressCoordinates;
  final double serviceCharge;

  // Raw JSON
  final String? rawJson;

  final bool isSynced;
  final DateTime? updatedAt;

  const ServiceOrderDto({
    required this.id,
    required this.accountNumber,
    required this.fullName,
    required this.contactNumber,
    required this.emailAddress,
    required this.address,
    this.barangay,
    this.city,
    this.provider,
    this.plan,
    this.username,
    this.connectionType,
    this.routerModemSN,
    this.lcp,
    this.nap,
    this.port,
    this.vlan,
    this.supportStatus = 'Open',
    this.concern = 'Maintenance Visit',
    this.priorityLevel,
    this.visitStatus,
    this.visitBy,
    this.visitRemarks,
    this.assignedEmail,
    this.createdDate,
    this.dateInstalled,
    this.newRouterModemSN,
    this.newLCP,
    this.newNAP,
    this.newPORT,
    this.newVLAN,
    this.routerModel,
    this.pulloutRouterModel,
    this.pulloutRouterModelSN,
    this.pulloutRemarks,
    this.materialsUsed = const {},
    this.clientSignature,
    this.image1,
    this.image2,
    this.image3,
    this.houseFrontPicture,
    this.addressCoordinates,
    this.serviceCharge = 0.0,
    this.rawJson,
    this.isSynced = true,
    this.updatedAt,
  });

  ServiceOrderDto copyWith({
    int? id,
    String? accountNumber,
    String? fullName,
    String? contactNumber,
    String? emailAddress,
    String? address,
    String? barangay,
    String? city,
    String? provider,
    String? plan,
    String? username,
    String? connectionType,
    String? routerModemSN,
    String? lcp,
    String? nap,
    String? port,
    String? vlan,
    String? supportStatus,
    String? concern,
    String? priorityLevel,
    String? visitStatus,
    String? visitBy,
    String? visitRemarks,
    String? assignedEmail,
    DateTime? createdDate,
    DateTime? dateInstalled,
    String? newRouterModemSN,
    String? newLCP,
    String? newNAP,
    String? newPORT,
    String? newVLAN,
    String? routerModel,
    String? pulloutRouterModel,
    String? pulloutRouterModelSN,
    String? pulloutRemarks,
    Map<String, int>? materialsUsed,
    String? clientSignature,
    String? image1,
    String? image2,
    String? image3,
    String? houseFrontPicture,
    String? addressCoordinates,
    double? serviceCharge,
    String? rawJson,
    bool? isSynced,
    DateTime? updatedAt,
  }) {
    return ServiceOrderDto(
      id: id ?? this.id,
      accountNumber: accountNumber ?? this.accountNumber,
      fullName: fullName ?? this.fullName,
      contactNumber: contactNumber ?? this.contactNumber,
      emailAddress: emailAddress ?? this.emailAddress,
      address: address ?? this.address,
      barangay: barangay ?? this.barangay,
      city: city ?? this.city,
      provider: provider ?? this.provider,
      plan: plan ?? this.plan,
      username: username ?? this.username,
      connectionType: connectionType ?? this.connectionType,
      routerModemSN: routerModemSN ?? this.routerModemSN,
      lcp: lcp ?? this.lcp,
      nap: nap ?? this.nap,
      port: port ?? this.port,
      vlan: vlan ?? this.vlan,
      supportStatus: supportStatus ?? this.supportStatus,
      concern: concern ?? this.concern,
      priorityLevel: priorityLevel ?? this.priorityLevel,
      visitStatus: visitStatus ?? this.visitStatus,
      visitBy: visitBy ?? this.visitBy,
      visitRemarks: visitRemarks ?? this.visitRemarks,
      assignedEmail: assignedEmail ?? this.assignedEmail,
      createdDate: createdDate ?? this.createdDate,
      dateInstalled: dateInstalled ?? this.dateInstalled,
      newRouterModemSN: newRouterModemSN ?? this.newRouterModemSN,
      newLCP: newLCP ?? this.newLCP,
      newNAP: newNAP ?? this.newNAP,
      newPORT: newPORT ?? this.newPORT,
      newVLAN: newVLAN ?? this.newVLAN,
      routerModel: routerModel ?? this.routerModel,
      pulloutRouterModel: pulloutRouterModel ?? this.pulloutRouterModel,
      pulloutRouterModelSN: pulloutRouterModelSN ?? this.pulloutRouterModelSN,
      pulloutRemarks: pulloutRemarks ?? this.pulloutRemarks,
      materialsUsed: materialsUsed ?? this.materialsUsed,
      clientSignature: clientSignature ?? this.clientSignature,
      image1: image1 ?? this.image1,
      image2: image2 ?? this.image2,
      image3: image3 ?? this.image3,
      houseFrontPicture: houseFrontPicture ?? this.houseFrontPicture,
      addressCoordinates: addressCoordinates ?? this.addressCoordinates,
      serviceCharge: serviceCharge ?? this.serviceCharge,
      rawJson: rawJson ?? this.rawJson,
      isSynced: isSynced ?? this.isSynced,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Rebuilds a service order from a `service_orders` row.
  factory ServiceOrderDto.fromRow(Map<String, Object?> row) {
    Map<String, int> materials = const {};
    final materialsJson = rowText(row['materials_used_json']);
    if (materialsJson != null && materialsJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(materialsJson);
        if (decoded is Map) {
          materials =
              decoded.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
        }
      } catch (_) {}
    }
    return ServiceOrderDto(
      id: rowInt(row['id']),
      accountNumber: rowText(row['account_number']) ?? '',
      fullName: rowText(row['full_name']) ?? '',
      contactNumber: rowText(row['contact_number']) ?? '',
      emailAddress: rowText(row['email_address']) ?? '',
      address: rowText(row['address']) ?? '',
      barangay: rowText(row['barangay']),
      city: rowText(row['city']),
      provider: rowText(row['provider']),
      plan: rowText(row['plan']),
      username: rowText(row['username']),
      connectionType: rowText(row['connection_type']),
      routerModemSN: rowText(row['router_modem_sn']),
      lcp: rowText(row['lcp']),
      nap: rowText(row['nap']),
      port: rowText(row['port']),
      vlan: rowText(row['vlan']),
      supportStatus: rowText(row['support_status']) ?? 'Open',
      concern: rowText(row['concern']) ?? 'Service Call',
      priorityLevel: rowText(row['priority_level']),
      visitStatus: rowText(row['visit_status']),
      visitBy: rowText(row['visit_by']),
      visitRemarks: rowText(row['visit_remarks']),
      assignedEmail: rowText(row['assigned_email']),
      createdDate: rowDate(row['created_date']),
      dateInstalled: rowDate(row['date_installed']),
      newRouterModemSN: rowText(row['new_router_modem_sn']),
      newLCP: rowText(row['new_lcp']),
      newNAP: rowText(row['new_nap']),
      newPORT: rowText(row['new_port']),
      newVLAN: rowText(row['new_vlan']),
      routerModel: rowText(row['router_model']),
      pulloutRouterModel: rowText(row['pullout_router_model']),
      pulloutRouterModelSN: rowText(row['pullout_router_model_sn']),
      pulloutRemarks: rowText(row['pullout_remarks']),
      materialsUsed: materials,
      clientSignature: rowText(row['client_signature']),
      image1: rowText(row['image1']),
      image2: rowText(row['image2']),
      image3: rowText(row['image3']),
      houseFrontPicture: rowText(row['house_front_picture']),
      addressCoordinates: rowText(row['address_coordinates']),
      serviceCharge: rowDouble(row['service_charge']) ?? 0.0,
      rawJson: rowText(row['raw_json']),
      isSynced: rowBool(row['is_synced'], fallback: true),
      updatedAt: rowDate(row['updated_at']),
    );
  }

  /// The `service_orders` row for this order.
  Map<String, Object?> toRow({bool synced = true}) => {
        'id': idText(id),
        'account_number': accountNumber,
        'full_name': fullName,
        'contact_number': contactNumber,
        'email_address': emailAddress,
        'address': address,
        'barangay': barangay,
        'city': city,
        'provider': provider,
        'plan': plan,
        'username': username,
        'connection_type': connectionType,
        'router_modem_sn': routerModemSN,
        'lcp': lcp,
        'nap': nap,
        'port': port,
        'vlan': vlan,
        'support_status': supportStatus,
        'concern': concern,
        'priority_level': priorityLevel,
        'visit_status': visitStatus,
        'visit_by': visitBy,
        'visit_remarks': visitRemarks,
        'assigned_email': assignedEmail,
        'created_date': dateText(createdDate),
        'date_installed': dateText(dateInstalled),
        'new_router_modem_sn': newRouterModemSN,
        'new_lcp': newLCP,
        'new_nap': newNAP,
        'new_port': newPORT,
        'new_vlan': newVLAN,
        'router_model': routerModel,
        'pullout_router_model': pulloutRouterModel,
        'pullout_router_model_sn': pulloutRouterModelSN,
        'pullout_remarks': pulloutRemarks,
        'materials_used_json':
            materialsUsed.isNotEmpty ? jsonEncode(materialsUsed) : null,
        'client_signature': clientSignature,
        'image1': image1,
        'image2': image2,
        'image3': image3,
        'house_front_picture': houseFrontPicture,
        'address_coordinates': addressCoordinates,
        'service_charge': serviceCharge,
        'raw_json': rawJson,
        'is_synced': boolInt(synced),
        'updated_at': dateText(updatedAt ?? DateTime.now()),
      };

  /// Converts fields to API JSON map, resolving local photo file paths
  /// back into Base64 data URLs as required by the backend API.
  Future<Map<String, dynamic>> toApiJsonAsync() async {
    final base = toJson();
    final photoStorage = PhotoStorageService.instance;
    if (clientSignature != null) {
      base['clientSignature'] =
          await photoStorage.resolveToDataUrl(clientSignature);
    }
    if (image1 != null) {
      base['image1'] = await photoStorage.resolveToDataUrl(image1);
    }
    if (image2 != null) {
      base['image2'] = await photoStorage.resolveToDataUrl(image2);
    }
    if (image3 != null) {
      base['image3'] = await photoStorage.resolveToDataUrl(image3);
    }
    if (houseFrontPicture != null) {
      base['houseFrontPicture'] =
          await photoStorage.resolveToDataUrl(houseFrontPicture);
    }
    return base;
  }

  /// Parse GPS coordinates from addressCoordinates string (e.g. "14.4705, 121.2150")
  LatLng? get latLng {
    if (addressCoordinates != null && addressCoordinates!.trim().isNotEmpty) {
      final parts = addressCoordinates!
          .replaceAll(RegExp(r'[^\d.,\s-]'), '')
          .split(RegExp(r'[,;\s]+'));
      if (parts.length >= 2) {
        final lat = double.tryParse(parts[0]);
        final lng = double.tryParse(parts[1]);
        if (lat != null &&
            lng != null &&
            lat.abs() <= 90 &&
            lng.abs() <= 180 &&
            !(lat == 0 && lng == 0)) {
          return LatLng(lat, lng);
        }
      }
    }
    return null;
  }

  // bool get isDone => (visitStatus ?? '').trim().toLowerCase() == 'done';
  // bool get isUrgent => (priorityLevel ?? '').trim().toLowerCase() == 'urgent';
  // Gene - Oct, 1, 2026: Added isOpen helper to determine whether a service order is active/actionable.
  bool get isDone => (visitStatus ?? '').trim().toLowerCase() == 'done';
  bool get isUrgent => (priorityLevel ?? '').trim().toLowerCase() == 'urgent';
  bool get isOpen =>
      !isDone &&
      supportStatus.trim().toLowerCase() != 'resolved' &&
      supportStatus.trim().toLowerCase() != 'closed';

  bool isAssignedTo(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    final mine = email.trim().toLowerCase();
    final theirs = (assignedEmail ?? '').trim().toLowerCase();
    return mine == theirs;
  }

  // Gene - Oct 12, 2026: Added concernRemarks and supportRemarks getters from payload.
  String? get concernRemarks {
    if (rawJson == null) return null;
    try {
      final m = jsonDecode(rawJson!) as Map<String, dynamic>;
      final v = m['concernRemarks'] ?? m['concern_remarks'];
      return v?.toString().trim();
    } catch (_) {
      return null;
    }
  }

  String? get supportRemarks {
    if (rawJson == null) return null;
    try {
      final m = jsonDecode(rawJson!) as Map<String, dynamic>;
      final v = m['supportRemarks'] ?? m['support_remarks'];
      return v?.toString().trim();
    } catch (_) {
      return null;
    }
  }

  factory ServiceOrderDto.fromJson(Map<String, dynamic> json) {
    // Extract materials from slots itemName / itemQuantity and itemName1..10
    final materials = <String, int>{};
    void checkSlot(String nameKey, String qtyKey) {
      final name = json[nameKey]?.toString().trim();
      final qty = json[qtyKey];
      if (name != null && name.isNotEmpty) {
        final parsedQty =
            qty is int ? qty : int.tryParse(qty?.toString() ?? '1') ?? 1;
        materials[name] = parsedQty;
      }
    }

    checkSlot('itemName', 'itemQuantity');
    for (int i = 1; i <= 10; i++) {
      checkSlot('itemName$i', 'itemQuantity$i');
    }

    return ServiceOrderDto(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      accountNumber: json['accountNumber']?.toString().trim() ?? '',
      fullName: json['fullName']?.toString().trim() ?? 'Subscriber',
      contactNumber: json['contactNumber']?.toString().trim() ?? '',
      emailAddress: json['emailAddress']?.toString().trim() ?? '',
      address: json['address']?.toString().trim() ?? 'No address provided',
      barangay: json['barangay']?.toString().trim(),
      city: json['city']?.toString().trim(),
      provider: json['provider']?.toString().trim(),
      plan: json['plan']?.toString().trim(),
      username: json['username']?.toString().trim(),
      connectionType: json['connectionType']?.toString().trim(),
      routerModemSN: json['routerModemSN']?.toString().trim(),
      lcp: json['lcp']?.toString().trim(),
      nap: json['nap']?.toString().trim(),
      port: json['port']?.toString().trim(),
      vlan: json['vlan']?.toString().trim(),
      supportStatus: json['supportStatus']?.toString().trim() ?? 'Open',
      concern: json['concern']?.toString().trim() ?? 'Service Call',
      priorityLevel: json['priorityLevel']?.toString().trim(),
      visitStatus: json['visitStatus']?.toString().trim(),
      visitBy: json['visitBy']?.toString().trim(),
      visitRemarks: json['visitRemarks']?.toString().trim(),
      assignedEmail: json['assignedEmail']?.toString().trim(),
      createdDate: json['createdDate'] != null
          ? DateTime.tryParse(json['createdDate'].toString())
          : null,
      dateInstalled: json['dateInstalled'] != null
          ? DateTime.tryParse(json['dateInstalled'].toString())
          : null,
      newRouterModemSN: json['newRouterModemSN']?.toString().trim(),
      newLCP: json['newLCP']?.toString().trim(),
      newNAP: json['newNAP']?.toString().trim(),
      newPORT: json['newPORT']?.toString().trim(),
      newVLAN: json['newVLAN']?.toString().trim(),
      routerModel: json['routerModel']?.toString().trim(),
      pulloutRouterModel: json['pulloutRouterModel']?.toString().trim(),
      pulloutRouterModelSN: json['pulloutRouterModelSN']?.toString().trim(),
      pulloutRemarks: json['pulloutRemarks']?.toString().trim(),
      materialsUsed: materials,
      clientSignature: json['clientSignature']?.toString(),
      image1: json['image1']?.toString(),
      image2: json['image2']?.toString(),
      image3: json['image3']?.toString(),
      houseFrontPicture: json['houseFrontPicture']?.toString(),
      addressCoordinates: json['addressCoordinates']?.toString().trim(),
      serviceCharge: json['serviceCharge'] is num
          ? (json['serviceCharge'] as num).toDouble()
          : double.tryParse(json['serviceCharge']?.toString() ?? '0') ?? 0.0,
      rawJson: jsonEncode(json),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'accountNumber': accountNumber,
      'fullName': fullName,
      'contactNumber': contactNumber,
      'emailAddress': emailAddress,
      'address': address,
      'barangay': barangay,
      'city': city,
      'provider': provider,
      'plan': plan,
      'username': username,
      'connectionType': connectionType,
      'routerModemSN': routerModemSN,
      'lcp': lcp,
      'nap': nap,
      'port': port,
      'vlan': vlan,
      'supportStatus': supportStatus,
      'concern': concern,
      'priorityLevel': priorityLevel,
      'visitStatus': visitStatus,
      'visitBy': visitBy,
      'visitRemarks': visitRemarks,
      'assignedEmail': assignedEmail,
      'newRouterModemSN': newRouterModemSN,
      'newLCP': newLCP,
      'newNAP': newNAP,
      'newPORT': newPORT,
      'newVLAN': newVLAN,
      'routerModel': routerModel,
      'pulloutRouterModel': pulloutRouterModel,
      'pulloutRouterModelSN': pulloutRouterModelSN,
      'pulloutRemarks': pulloutRemarks,
      'clientSignature': clientSignature,
      'image1': image1,
      'image2': image2,
      'image3': image3,
      'houseFrontPicture': houseFrontPicture,
      'addressCoordinates': addressCoordinates,
      'serviceCharge': serviceCharge,
    };

    // Serialize materials into itemName1..10 and itemQuantity1..10
    int index = 1;
    materialsUsed.forEach((name, qty) {
      if (index <= 10) {
        map['itemName$index'] = name;
        map['itemQuantity$index'] = qty;
        index++;
      }
    });

    return map;
  }
}
