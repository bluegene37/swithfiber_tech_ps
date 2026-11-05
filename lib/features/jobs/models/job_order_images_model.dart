// Gene - Nov 5, 2026: Model for Job Order photo proofs and customer signature from GET /api/JobOrders/{id}/GetJobOrderImage.
import 'dart:convert';
import 'dart:typed_data';
import '../../../core/utils/data_url.dart';

/// Single file result payload for Job Order photos.
class JobOrderImageFileDto {
  final String? fileContents; // Base64 encoded string
  final String? contentType; // e.g. "image/jpeg", "image/png"
  final String? fileDownloadName;

  const JobOrderImageFileDto({
    this.fileContents,
    this.contentType,
    this.fileDownloadName,
  });

  factory JobOrderImageFileDto.fromJson(Map<String, dynamic> json) {
    return JobOrderImageFileDto(
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

/// Collection of photos returned by `GET /api/JobOrders/{id}/GetJobOrderImage`.
class JobOrderImagesDto {
  final JobOrderImageFileDto? setupImage;
  final JobOrderImageFileDto? clientSignature;
  final JobOrderImageFileDto? signedContractImage;
  final JobOrderImageFileDto? boxReadingImage;
  final JobOrderImageFileDto? routerReadingImage;
  final JobOrderImageFileDto? portLabelImage;
  final JobOrderImageFileDto? houseFront;

  const JobOrderImagesDto({
    this.setupImage,
    this.clientSignature,
    this.signedContractImage,
    this.boxReadingImage,
    this.routerReadingImage,
    this.portLabelImage,
    this.houseFront,
  });

  factory JobOrderImagesDto.fromJson(Map<String, dynamic> json) {
    JobOrderImageFileDto? parseFile(dynamic val) {
      if (val == null) return null;
      if (val is Map) {
        final map = Map<String, dynamic>.from(val);
        final dto = JobOrderImageFileDto.fromJson(map);
        return dto.hasImage ? dto : null;
      }
      if (val is String && val.trim().isNotEmpty) {
        final trimmed = val.trim();
        return JobOrderImageFileDto(
          fileContents: trimmed,
          contentType: 'image/jpeg',
          fileDownloadName: 'photo.jpg',
        );
      }
      return null;
    }

    return JobOrderImagesDto(
      setupImage: parseFile(json['setupImageFile'] ?? json['setupImage']),
      clientSignature:
          parseFile(json['clientSignatureFile'] ?? json['clientSignature']),
      signedContractImage: parseFile(
          json['signedContractImageFile'] ?? json['signedContractImage']),
      boxReadingImage:
          parseFile(json['boxReadingImageFile'] ?? json['boxReadingImage']),
      routerReadingImage: parseFile(
          json['routerReadingImageFile'] ?? json['routerReadingImage']),
      portLabelImage:
          parseFile(json['portLabelImageFile'] ?? json['portLabelImage']),
      houseFront: parseFile(json['houseFrontFile'] ?? json['houseFront']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (setupImage != null) 'setupImageFile': setupImage!.toJson(),
        if (clientSignature != null)
          'clientSignatureFile': clientSignature!.toJson(),
        if (signedContractImage != null)
          'signedContractImageFile': signedContractImage!.toJson(),
        if (boxReadingImage != null)
          'boxReadingImageFile': boxReadingImage!.toJson(),
        if (routerReadingImage != null)
          'routerReadingImageFile': routerReadingImage!.toJson(),
        if (portLabelImage != null)
          'portLabelImageFile': portLabelImage!.toJson(),
        if (houseFront != null) 'houseFrontFile': houseFront!.toJson(),
      };

  /// True if any of the photo proofs or signature contain image data.
  bool get hasAnyPhoto =>
      (setupImage?.hasImage ?? false) ||
      (clientSignature?.hasImage ?? false) ||
      (signedContractImage?.hasImage ?? false) ||
      (boxReadingImage?.hasImage ?? false) ||
      (routerReadingImage?.hasImage ?? false) ||
      (portLabelImage?.hasImage ?? false) ||
      (houseFront?.hasImage ?? false);
}
