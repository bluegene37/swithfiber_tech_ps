import 'package:latlong2/latlong.dart';
import '../../../core/database/sql_values.dart';

/// DTO for Local Convergence Point (LCP) and Network Access Point (NAP) location sites.
class LcpNapDto {
  final int id;
  final String lcp;
  final String nap;
  final String lcpNap;
  final int portTotal;
  final String? coordinates;
  final String? street;
  final String? barangay;
  final String? city;
  final String? region;
  final String? image;
  final String? image2;
  final String? readingImage;
  final String? modifiedBy;
  final String? userEmail;
  final DateTime? modifiedDate;
  final bool isSynced;
  final DateTime? updatedAt;

  LcpNapDto({
    required this.id,
    required this.lcp,
    required this.nap,
    required this.lcpNap,
    this.portTotal = 8,
    this.coordinates,
    this.street,
    this.barangay,
    this.city,
    this.region,
    this.image,
    this.image2,
    this.readingImage,
    this.modifiedBy,
    this.userEmail,
    this.modifiedDate,
    this.isSynced = true,
    this.updatedAt,
  });

  /// Available ports remaining

  /// Parsed GPS latitude
  double? get latitude => latLng?.latitude;

  /// Parsed GPS longitude
  double? get longitude => latLng?.longitude;

  /// The site's position, or null when the record carries no usable fix.
  ///
  /// The API stores this as a single string such as `"14.469586, 121.195615"`.
  /// Anything that is not a real position - malformed text, out-of-range
  /// values, or the 0,0 placeholder the backend uses for "no fix recorded" -
  /// returns null so the site is left off the map rather than plotted somewhere
  /// misleading.
  LatLng? get latLng {
    final raw = coordinates;
    if (raw == null || raw.trim().isEmpty) return null;

    // Accepts the separators and labelled forms the web console accepts, so
    // both clients plot exactly the same rows.
    final clean = raw
        .replaceAll(
            RegExp(r'lat:|latitude:|lng:|longitude:|lon:',
                caseSensitive: false),
            '')
        .trim();
    if (clean.isEmpty) return null;

    final parts = clean
        .split(RegExp(r'[,;\s]+'))
        .map((p) => double.tryParse(p.trim()))
        .toList();
    if (parts.length != 2) return null;

    final lat = parts[0];
    final lng = parts[1];
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    if (lat == 0 && lng == 0) return null;

    return LatLng(lat, lng);
  }

  /// Whether this site can be shown as a pin on the map.
  bool get isMappable => latLng != null;

  factory LcpNapDto.fromJson(Map<String, dynamic> json) {
    final lcpStr = json['lcp']?.toString().trim() ?? '';
    final napStr = json['nap']?.toString().trim() ?? '';
    final lcpNapRaw =
        (json['lcpNap'] ?? json['lcpnap'])?.toString().trim() ?? '';
    final lcpNapStr = lcpNapRaw.isNotEmpty
        ? lcpNapRaw
        : (lcpStr.isNotEmpty && napStr.isNotEmpty
            ? '$lcpStr - $napStr'
            : (lcpStr.isNotEmpty ? lcpStr : napStr));

    // Gene - Oct 31, 2026: Parse image fields cleanly. In the backend API, image fields can be either:
    // 1. A string (URL, base64 data URL, or file path).
    // 2. A map with 'fileContents' (base64 string) from FileContentResult.
    // 3. A map representing an uploaded file metadata (e.g. IFormFile with fileName, name, contentType).
    // If the map only contains file metadata without fileContents, do not convert the map to a string "{...}".
    String? parseImageField(dynamic raw) {
      if (raw == null) return null;
      if (raw is String) {
        final trimmed = raw.trim();
        return trimmed.isNotEmpty ? trimmed : null;
      }
      if (raw is Map) {
        if (raw.containsKey('fileContents') && raw['fileContents'] != null) {
          final fc = raw['fileContents'].toString().trim();
          if (fc.isNotEmpty) {
            final mime =
                raw['contentType']?.toString().trim().isNotEmpty == true
                    ? raw['contentType'].toString().trim()
                    : 'image/jpeg';
            return fc.startsWith('data:') ? fc : 'data:$mime;base64,$fc';
          }
        }
        // If it's an uploaded file object without base64 contents (e.g. IFormFile metadata with fileName),
        // we return null here so the client fetches the actual image bytes via GetLCPNAPLocationImages.
        return null;
      }
      return raw.toString();
    }

    return LcpNapDto(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      lcp: lcpStr,
      nap: napStr,
      lcpNap: lcpNapStr,
      portTotal: json['portTotal'] is int
          ? json['portTotal']
          : int.tryParse(json['portTotal']?.toString() ?? '8') ?? 8,
      coordinates: json['coordinates']?.toString() ??
          json['addressCoordinates']?.toString(),
      street: json['street']?.toString(),
      barangay: json['barangay']?.toString(),
      city: json['city']?.toString(),
      region: json['region']?.toString(),
      /*
      image: json['image']?.toString(),
      image2: json['image2']?.toString(),
      readingImage: json['readingImage']?.toString(),
      */
      // Gene - Oct 31, 2026: Use parseImageField to handle both string payloads and ASP.NET FileResult maps.
      image: parseImageField(json['image']),
      image2: parseImageField(json['image2']),
      readingImage:
          parseImageField(json['readingImage'] ?? json['reading_image']),
      modifiedBy: json['modifiedBy']?.toString(),
      userEmail: json['userEmail']?.toString(),
      modifiedDate: DateTime.tryParse(json['modifiedDate']?.toString() ?? ''),
      isSynced: true,
      updatedAt: DateTime.now(),
    );
  }

  /// Rebuilds a site from an `lcp_nap_locations` row.
  factory LcpNapDto.fromRow(Map<String, Object?> row) => LcpNapDto(
        id: rowInt(row['id']),
        lcp: rowText(row['lcp']) ?? '',
        nap: rowText(row['nap']) ?? '',
        lcpNap: rowText(row['lcp_nap']) ?? '',
        portTotal: rowInt(row['port_total'], 8),
        coordinates: rowText(row['coordinates']),
        street: rowText(row['street']),
        barangay: rowText(row['barangay']),
        city: rowText(row['city']),
        region: rowText(row['region']),
        image: rowText(row['image']),
        image2: rowText(row['image2']),
        readingImage: rowText(row['reading_image']),
        modifiedBy: rowText(row['modified_by']),
        userEmail: rowText(row['user_email']),
        modifiedDate: rowDate(row['modified_date']),
        isSynced: rowBool(row['is_synced'], fallback: true),
        updatedAt: rowDate(row['updated_at']),
      );

  /// The `lcp_nap_locations` row for this site.
  Map<String, Object?> toRow({bool synced = true}) => {
        'id': idText(id),
        'lcp': lcp,
        'nap': nap,
        'lcp_nap': lcpNap,
        'port_total': portTotal,
        'coordinates': coordinates,
        'street': street,
        'barangay': barangay,
        'city': city,
        'region': region,
        'image': image,
        'image2': image2,
        'reading_image': readingImage,
        'modified_by': modifiedBy,
        'user_email': userEmail,
        'modified_date': dateText(modifiedDate),
        'is_synced': boolInt(synced),
        'updated_at': dateText(updatedAt ?? DateTime.now()),
      };

  /*
  // Gene - Oct 31, 2026: Added copyWith method to LcpNapDto to support updating location coordinates and metadata.
  LcpNapDto copyWith({
    int? id,
    String? lcp,
    String? nap,
    String? lcpNap,
    int? portTotal,
    String? coordinates,
    String? street,
    String? barangay,
    String? city,
    String? region,
    String? image,
    String? image2,
    String? readingImage,
    String? modifiedBy,
    String? userEmail,
    DateTime? modifiedDate,
    bool? isSynced,
    DateTime? updatedAt,
  }) {
    return LcpNapDto(
      id: id ?? this.id,
      lcp: lcp ?? this.lcp,
      nap: nap ?? this.nap,
      lcpNap: lcpNap ?? this.lcpNap,
      portTotal: portTotal ?? this.portTotal,
      coordinates: coordinates ?? this.coordinates,
      street: street ?? this.street,
      barangay: barangay ?? this.barangay,
      city: city ?? this.city,
      region: region ?? this.region,
      image: image ?? this.image,
      image2: image2 ?? this.image2,
      readingImage: readingImage ?? this.readingImage,
      modifiedBy: modifiedBy ?? this.modifiedBy,
      userEmail: userEmail ?? this.userEmail,
      modifiedDate: modifiedDate ?? this.modifiedDate,
      isSynced: isSynced ?? this.isSynced,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
  */
  // Gene - Nov, 8, 2026: Added clearImage, clearImage2, and clearReadingImage flags to copyWith so deleted photos are cleared in local SQLite state.
  LcpNapDto copyWith({
    int? id,
    String? lcp,
    String? nap,
    String? lcpNap,
    int? portTotal,
    String? coordinates,
    String? street,
    String? barangay,
    String? city,
    String? region,
    String? image,
    String? image2,
    String? readingImage,
    bool clearImage = false,
    bool clearImage2 = false,
    bool clearReadingImage = false,
    String? modifiedBy,
    String? userEmail,
    DateTime? modifiedDate,
    bool? isSynced,
    DateTime? updatedAt,
  }) {
    return LcpNapDto(
      id: id ?? this.id,
      lcp: lcp ?? this.lcp,
      nap: nap ?? this.nap,
      lcpNap: lcpNap ?? this.lcpNap,
      portTotal: portTotal ?? this.portTotal,
      coordinates: coordinates ?? this.coordinates,
      street: street ?? this.street,
      barangay: barangay ?? this.barangay,
      city: city ?? this.city,
      region: region ?? this.region,
      image: clearImage ? null : (image ?? this.image),
      image2: clearImage2 ? null : (image2 ?? this.image2),
      readingImage: clearReadingImage ? null : (readingImage ?? this.readingImage),
      modifiedBy: modifiedBy ?? this.modifiedBy,
      userEmail: userEmail ?? this.userEmail,
      modifiedDate: modifiedDate ?? this.modifiedDate,
      isSynced: isSynced ?? this.isSynced,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
