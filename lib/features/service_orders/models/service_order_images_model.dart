// Gene - Nov, 25, 2026: Model for Service Order photo proofs and customer signature from GET /api/ServiceOrders/{id}/GetServiceOrderImage.
import 'dart:convert';
import 'dart:typed_data';
import '../../../core/utils/data_url.dart';

/// Single file result payload for Service Order photos.
class ServiceOrderImageFileDto {
  final String? fileContents; // Base64 encoded string
  final String? contentType; // e.g. "image/jpeg", "image/png"
  final String? fileDownloadName;

  const ServiceOrderImageFileDto({
    this.fileContents,
    this.contentType,
    this.fileDownloadName,
  });

  factory ServiceOrderImageFileDto.fromJson(Map<String, dynamic> json) {
    return ServiceOrderImageFileDto(
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
    final decodedDataUrl = DataUrl.decode(raw);
    if (decodedDataUrl != null) return decodedDataUrl;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
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

/// Collection of photos returned by `GET /api/ServiceOrders/{id}/GetServiceOrderImage`.
class ServiceOrderImagesDto {
  final ServiceOrderImageFileDto? clientSignature;
  final ServiceOrderImageFileDto? image1;
  final ServiceOrderImageFileDto? image2;
  final ServiceOrderImageFileDto? image3;
  final ServiceOrderImageFileDto? houseFrontPicture;

  const ServiceOrderImagesDto({
    this.clientSignature,
    this.image1,
    this.image2,
    this.image3,
    this.houseFrontPicture,
  });

  factory ServiceOrderImagesDto.fromJson(Map<String, dynamic> json) {
    ServiceOrderImageFileDto? parseFile(dynamic val) {
      if (val == null) return null;
      if (val is Map) {
        final map = Map<String, dynamic>.from(val);
        final dto = ServiceOrderImageFileDto.fromJson(map);
        return dto.hasImage ? dto : null;
      }
      if (val is String && val.trim().isNotEmpty) {
        final trimmed = val.trim();
        return ServiceOrderImageFileDto(
          fileContents: trimmed,
          contentType: 'image/jpeg',
          fileDownloadName: 'photo.jpg',
        );
      }
      return null;
    }

    return ServiceOrderImagesDto(
      clientSignature:
          parseFile(json['clientSignatureFile'] ?? json['clientSignature']),
      image1: parseFile(json['image1File'] ?? json['image1']),
      image2: parseFile(json['image2File'] ?? json['image2']),
      image3: parseFile(json['image3File'] ?? json['image3']),
      houseFrontPicture:
          parseFile(json['houseFrontPictureFile'] ?? json['houseFrontPicture']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (clientSignature != null)
          'clientSignatureFile': clientSignature!.toJson(),
        if (image1 != null) 'image1File': image1!.toJson(),
        if (image2 != null) 'image2File': image2!.toJson(),
        if (image3 != null) 'image3File': image3!.toJson(),
        if (houseFrontPicture != null)
          'houseFrontPictureFile': houseFrontPicture!.toJson(),
      };

  /// True if any of the photo proofs or signature contain image data.
  bool get hasAnyPhoto =>
      (clientSignature?.hasImage ?? false) ||
      (image1?.hasImage ?? false) ||
      (image2?.hasImage ?? false) ||
      (image3?.hasImage ?? false) ||
      (houseFrontPicture?.hasImage ?? false);
}
