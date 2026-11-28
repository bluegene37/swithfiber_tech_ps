import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/data_url.dart';
import 'exif_service.dart';
import 'location_service.dart';
import 'photo_storage_service.dart';

/// Captures a photo from the camera or gallery, compresses it (1280px, ~72% quality JPEG),
/// injects GPS coordinates and technician metadata into EXIF, and writes/returns it cleanly.
class ImageCaptureService {
  static final ImageCaptureService instance = ImageCaptureService();

  /*
  static const double maxDimension = 1600;
  static const int quality = 80;
  */
  // Gene - Nov, 28, 2026: Tighten photo compression to 1280px / quality 72 (~200-400 KB) via flutter_image_compress and support disk-backed pending_media capture.
  static const double maxDimension = 1280;
  static const int quality = 72;

  final ImagePicker _picker;
  final LocationService _locationService;
  final ExifService _exifService;

  ImageCaptureService({
    ImagePicker? picker,
    LocationService? locationService,
    ExifService? exifService,
  })  : _picker = picker ?? ImagePicker(),
        _locationService = locationService ?? LocationService.instance,
        _exifService = exifService ?? ExifService.instance;

  /// Null when the technician cancels.
  /// Compresses the image and embeds GPS EXIF tags directly into the JPEG file.
  Future<String?> pickAsDataUrl(
    ImageSource source, {
    double? fallbackLat,
    double? fallbackLng,
    String? technicianEmail,
  }) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: quality,
      requestFullMetadata: true,
    );
    if (file == null) return null;

    Uint8List bytes = await file.readAsBytes();
    // Gene - Nov, 28, 2026: Compress JPEG to max 1280px / quality 72 (~200-400 KB) while preserving EXIF metadata; gracefully falls back if codec plugin is unavailable (tests).
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1280,
        minHeight: 1280,
        quality: quality,
        keepExif: true,
        format: CompressFormat.jpeg,
      );
      if (compressed.isNotEmpty) {
        bytes = compressed;
      }
    } catch (_) {}

    // Query current high-accuracy GPS fix from device
    double? lat = fallbackLat;
    double? lng = fallbackLng;
    double? alt;

    try {
      final pos = await _locationService.getCurrentPosition();
      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
        alt = pos.altitude;
      }
    } catch (_) {}

    // Only inject GPS EXIF if a verified GPS fix or explicit coordinates were acquired.
    // Never fall back to dummy/plant center coordinates to avoid spoofing unverified locations.
    if (lat != null && lng != null) {
      bytes = _exifService.injectGpsExif(
        bytes,
        latitude: lat,
        longitude: lng,
        altitude: alt,
        timestamp: DateTime.now(),
        technicianEmail: technicianEmail,
      );
    }

    return DataUrl.encode(bytes, mimeType: _mimeTypeFor(file));
  }

  /// Captures a photo, compresses it to max 1280px / ~72% JPEG, injects EXIF,
  /// and saves it directly into `<appDocumentsDir>/pending_media/<uuid>.jpg`.
  Future<String?> pickAsPendingMediaFile(
    ImageSource source, {
    double? fallbackLat,
    double? fallbackLng,
    String? technicianEmail,
  }) async {
    final dataUrl = await pickAsDataUrl(
      source,
      fallbackLat: fallbackLat,
      fallbackLng: fallbackLng,
      technicianEmail: technicianEmail,
    );
    if (dataUrl == null) return null;
    return PhotoStorageService.instance.savePendingMediaFromValue(dataUrl);
  }

  static String _mimeTypeFor(XFile file) {
    final declared = file.mimeType;
    if (declared != null && declared.startsWith('image/')) return declared;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}
