// Gene - Oct 24, 2026: Models for customer application images and KYC proofs from GET /api/Applications/{id}/GetApplicationImages.
import 'dart:convert';
import 'dart:typed_data';
import '../../../core/utils/data_url.dart';

/// Single file result payload from ASP.NET FileContentResult.
class ApplicationImageFileDto {
  final String? fileContents; // Base64 encoded string
  final String? contentType; // e.g. "image/jpeg", "image/png"
  final String? fileDownloadName;

  const ApplicationImageFileDto({
    this.fileContents,
    this.contentType,
    this.fileDownloadName,
  });

  factory ApplicationImageFileDto.fromJson(Map<String, dynamic> json) {
    return ApplicationImageFileDto(
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
    return DataUrl.decode(raw) ?? (base64Decode(raw));
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

  /// Returns true if this file result has valid base64 image data.
  bool get hasImage => fileContents != null && fileContents!.trim().isNotEmpty;
}

/// Collection of application images returned by `GET /api/Applications/{id}/GetApplicationImages`.
class ApplicationImagesDto {
  final ApplicationImageFileDto? houseFrontPictureFile;
  final ApplicationImageFileDto? landmarkFile;
  final ApplicationImageFileDto? secondNearestLandmarkFile;
  final ApplicationImageFileDto? governmentValidIdFile;
  final ApplicationImageFileDto? secondGovernmentValidIdFile;
  final ApplicationImageFileDto? proofOfBillingFile;
  final ApplicationImageFileDto? documentPictureFile;
  final ApplicationImageFileDto? pictureOfStatementBillingFromOtherProviderFile;

  const ApplicationImagesDto({
    this.houseFrontPictureFile,
    this.landmarkFile,
    this.secondNearestLandmarkFile,
    this.governmentValidIdFile,
    this.secondGovernmentValidIdFile,
    this.proofOfBillingFile,
    this.documentPictureFile,
    this.pictureOfStatementBillingFromOtherProviderFile,
  });

  factory ApplicationImagesDto.fromJson(Map<String, dynamic> json) {
    ApplicationImageFileDto? parseFile(dynamic val) {
      if (val is Map<String, dynamic>) {
        final dto = ApplicationImageFileDto.fromJson(val);
        return dto.hasImage ? dto : null;
      }
      return null;
    }

    return ApplicationImagesDto(
      houseFrontPictureFile: parseFile(json['houseFrontPictureFile']),
      landmarkFile: parseFile(json['landmarkFile']),
      secondNearestLandmarkFile: parseFile(json['secondNearestLandmarkFile']),
      governmentValidIdFile: parseFile(json['governmentValidIdFile']),
      secondGovernmentValidIdFile: parseFile(json['secondGovernmentValidIdFile']),
      proofOfBillingFile: parseFile(json['proofOfBillingFile']),
      documentPictureFile: parseFile(json['documentPictureFile']),
      pictureOfStatementBillingFromOtherProviderFile:
          parseFile(json['pictureOfStatementBillingFromOtherProviderFile']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (houseFrontPictureFile != null)
          'houseFrontPictureFile': houseFrontPictureFile!.toJson(),
        if (landmarkFile != null) 'landmarkFile': landmarkFile!.toJson(),
        if (secondNearestLandmarkFile != null)
          'secondNearestLandmarkFile': secondNearestLandmarkFile!.toJson(),
        if (governmentValidIdFile != null)
          'governmentValidIdFile': governmentValidIdFile!.toJson(),
        if (secondGovernmentValidIdFile != null)
          'secondGovernmentValidIdFile': secondGovernmentValidIdFile!.toJson(),
        if (proofOfBillingFile != null)
          'proofOfBillingFile': proofOfBillingFile!.toJson(),
        if (documentPictureFile != null)
          'documentPictureFile': documentPictureFile!.toJson(),
        if (pictureOfStatementBillingFromOtherProviderFile != null)
          'pictureOfStatementBillingFromOtherProviderFile':
              pictureOfStatementBillingFromOtherProviderFile!.toJson(),
      };

  /// True if at least one photo or document file is present.
  bool get hasAnyImage =>
      houseFrontPictureFile != null ||
      landmarkFile != null ||
      secondNearestLandmarkFile != null ||
      governmentValidIdFile != null ||
      secondGovernmentValidIdFile != null ||
      proofOfBillingFile != null ||
      documentPictureFile != null ||
      pictureOfStatementBillingFromOtherProviderFile != null;

  /// True if subscriber KYC verification documents are present.
  bool get hasKycDocuments =>
      governmentValidIdFile != null ||
      secondGovernmentValidIdFile != null ||
      proofOfBillingFile != null ||
      documentPictureFile != null ||
      pictureOfStatementBillingFromOtherProviderFile != null;
}
