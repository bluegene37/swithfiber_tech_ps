// Gene - Oct 24, 2026: Model for LCP NAP site enclosure and optical power reading photos from GET /api/LCPNapLocations/{id}/GetLCPNAPLocationImages.
import 'dart:convert';
import 'dart:typed_data';
import '../../../core/utils/data_url.dart';

/// Single file result payload for LCP NAP photos.
class LcpNapImageFileDto {
  final String? fileContents; // Base64 encoded string
  final String? contentType; // e.g. "image/jpeg", "image/png"
  final String? fileDownloadName;

  const LcpNapImageFileDto({
    this.fileContents,
    this.contentType,
    this.fileDownloadName,
  });

  factory LcpNapImageFileDto.fromJson(Map<String, dynamic> json) {
    return LcpNapImageFileDto(
      fileContents: json['fileContents']?.toString(),
      contentType: json['contentType']?.toString(),
      fileDownloadName: json['fileDownloadName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (fileContents != null) 'fileContents': fileContents,
        if (contentType != null) 'contentType': contentType,
        if (fileDownloadName != null) 'fileDownloadName': fileDownloadName,
      };

  /// Decodes base64 `fileContents` into raw binary bytes.
  Uint8List? get bytes {
    final raw = fileContents?.trim();
    if (raw == null || raw.isEmpty) return null;
    return DataUrl.decode(raw) ?? base64Decode(raw);
  }

  /// Builds a browser- and widget-compatible `data:image/...;base64,...` URL.
  String? get dataUrl {
    final raw = fileContents?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (DataUrl.isDataUrl(raw)) return raw;
    final mime = contentType?.trim().isNotEmpty == true
        ? contentType!.trim()
        : 'image/jpeg';
    return 'data:$mime;base64,$raw';
  }

  /// True if this file result contains valid base64 photo data.
  bool get hasImage => fileContents != null && fileContents!.trim().isNotEmpty;
}

/// Collection of photos returned by `GET /api/LCPNapLocations/{id}/GetLCPNAPLocationImages`.
class LcpNapImagesDto {
  final LcpNapImageFileDto? image; // Enclosure 1 photo
  final LcpNapImageFileDto? image2; // Enclosure 2 photo
  final LcpNapImageFileDto? readingImage; // Optical power reading photo

  const LcpNapImagesDto({
    this.image,
    this.image2,
    this.readingImage,
  });

  factory LcpNapImagesDto.fromJson(Map<String, dynamic> json) {
    LcpNapImageFileDto? parseFile(dynamic val) {
      if (val is Map<String, dynamic>) {
        final dto = LcpNapImageFileDto.fromJson(val);
        return dto.hasImage ? dto : null;
      }
      return null;
    }

    return LcpNapImagesDto(
      image: parseFile(json['image']),
      image2: parseFile(json['image2']),
      readingImage: parseFile(json['readingImage'] ?? json['reading_image']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (image != null) 'image': image!.toJson(),
        if (image2 != null) 'image2': image2!.toJson(),
        if (readingImage != null) 'readingImage': readingImage!.toJson(),
      };

  bool get hasAnyPhoto =>
      (image != null && image!.hasImage) ||
      (image2 != null && image2!.hasImage) ||
      (readingImage != null && readingImage!.hasImage);
}
