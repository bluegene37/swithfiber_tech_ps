import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/database/daos/lcp_nap_dao.dart';
import '../../../core/network/api_client.dart';
import '../models/lcp_nap_images_model.dart';
import '../models/lcp_nap_model.dart';

/// Repository coordinating LCP NAP locations between the API and the local database.
class LcpNapRepository {
  final LcpNapLocationsDao _dao;
  /*
  final ApiClient _api = ApiClient.instance;

  LcpNapRepository(this._dao);
  */
  // Gene - Oct 29, 2026: Allow optional ApiClient injection for unit testing upload and image endpoints.
  final ApiClient _api;

  LcpNapRepository(this._dao, [ApiClient? api])
      : _api = api ?? ApiClient.instance;

  /// Watch reactive stream of all locations from the local database
  Stream<List<LcpNapDto>> watchLocations() => _dao.watchAllLocations();

  /// Watch a specific location by ID
  Stream<LcpNapDto?> watchLocationById(int id) => _dao.watchLocationById(id);

  /// Fetch remote records from API and cache them locally
  Future<void> fetchRemoteLocations() async {
    // Purge test/sample demo locations permanently
    await _dao.deleteSampleLocations();

    try {
      final response = await _api.get('/LCPNapLocations');
      final data = response.data;

      if (data is List) {
        final sites = <LcpNapDto>[
          for (final item in data)
            if (item is Map<String, dynamic>) LcpNapDto.fromJson(item),
        ];
        if (sites.isNotEmpty) {
          await _dao.insertAllLocations(sites, synced: true);
        }
      }
    } catch (_) {
      // Offline fallback: do not re-seed test data
    }
  }

  /// Seed realistic fiber plant infrastructure data
  Future<void> seedSampleLocations() async {
    final now = DateTime.now();
    final sampleSites = [
      LcpNapDto(
        id: 1,
        lcp: 'LCP 01',
        nap: 'NAP 01',
        lcpNap: 'LCP 01 - NAP 01',
        portTotal: 8,
        coordinates: '14.5862, 121.0618',
        street: 'Sample Street',
        region: 'Rizal',
        barangay: 'San Antonio',
        city: 'Pasig',
        isSynced: true,
        updatedAt: now,
      ),
      LcpNapDto(
        id: 2,
        lcp: 'LCP 01',
        nap: 'NAP 02',
        lcpNap: 'LCP 01 - NAP 02',
        portTotal: 8,
        coordinates: '14.5875, 121.0632',
        street: 'Sample Street',
        region: 'Rizal',
        barangay: 'San Antonio',
        city: 'Pasig',
        isSynced: true,
        updatedAt: now,
      ),
      LcpNapDto(
        id: 3,
        lcp: 'LCP 02',
        nap: 'NAP 01',
        lcpNap: 'LCP 02 - NAP 01',
        portTotal: 16,
        coordinates: '14.6288, 121.1274',
        street: 'Sample Street',
        region: 'Rizal',
        barangay: 'San Roque',
        city: 'Antipolo',
        isSynced: true,
        updatedAt: now,
      ),
      LcpNapDto(
        id: 4,
        lcp: 'LCP 02',
        nap: 'NAP 02',
        lcpNap: 'LCP 02 - NAP 02',
        portTotal: 8,
        coordinates: '14.6295, 121.1290',
        street: 'Sample Street',
        region: 'Rizal',
        barangay: 'San Roque',
        city: 'Antipolo',
        isSynced: true,
        updatedAt: now,
      ),
      LcpNapDto(
        id: 5,
        lcp: 'LCP 03',
        nap: 'NAP 01',
        lcpNap: 'LCP 03 - NAP 01',
        portTotal: 8,
        coordinates: '14.6433, 121.0712',
        street: 'Sample Street',
        region: 'Rizal',
        barangay: 'Loyola Heights',
        city: 'Quezon City',
        isSynced: true,
        updatedAt: now,
      ),
    ];

    await _dao.insertAllLocations(sampleSites, synced: true);
  }

  // Gene - Oct 24, 2026: Cached LCP NAP location photos by site ID.
  final Map<int, LcpNapImagesDto> _imagesCache = {};

  /// Clear in-memory photos cache (useful for tests or refresh).
  void clearImagesCache() {
    _imagesCache.clear();
  }

  /// Fetches site enclosure photos and optical power reading image for an LCP NAP location.
  /// Calls GET /api/LCPNapLocations/{id}/GetLCPNAPLocationImages
  /// and fallback GET /api/LCPNapLocations/{id}/GetReadingImage.
  Future<LcpNapImagesDto?> getLcpNapLocationImages(
    int locationId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _imagesCache.containsKey(locationId)) {
      return _imagesCache[locationId];
    }

    try {
      final response = await _api
          .get('/LCPNapLocations/$locationId/GetLCPNAPLocationImages');
      final data = response.data;
      if (data is Map<String, dynamic>) {
        var dto = LcpNapImagesDto.fromJson(data);

        // Fallback to GetReadingImage if readingImage was not included in JSON payload
        if (dto.readingImage == null) {
          try {
            final readingRes = await _api.get(
              '/LCPNapLocations/$locationId/GetReadingImage',
              options: Options(responseType: ResponseType.bytes),
            );
            if (readingRes.data is List<int> &&
                (readingRes.data as List<int>).isNotEmpty) {
              final b64 = base64Encode(readingRes.data as List<int>);
              final readingFile = LcpNapImageFileDto(
                fileContents: b64,
                contentType: 'image/jpeg',
                fileDownloadName: 'reading_$locationId.jpg',
              );
              dto = LcpNapImagesDto(
                image: dto.image,
                image2: dto.image2,
                readingImage: readingFile,
              );
            }
          } catch (_) {}
        }

        /*
        if (dto.hasAnyPhoto) {
          _imagesCache[locationId] = dto;
        }
        return dto;
        */
        // Gene - Oct 31, 2026: Cache photo result whenever a valid response is returned.
        _imagesCache[locationId] = dto;
        return dto;
      }
    } catch (_) {
      // Offline fallback or test mock
      // Gene - Oct 31, 2026: Fallback to single record endpoint GET /api/LCPNapLocations/{id} if GetLCPNAPLocationImages is unavailable.
      try {
        final singleRes = await _api.get('/LCPNapLocations/$locationId');
        final singleData = singleRes.data;
        if (singleData is Map<String, dynamic>) {
          final dto = LcpNapImagesDto.fromJson(singleData);
          if (dto.hasAnyPhoto) {
            _imagesCache[locationId] = dto;
            return dto;
          }
        }
      } catch (_) {}
    }
    return _imagesCache[locationId];
  }

  // Gene - Oct 29, 2026: Uploads LCP NAP site enclosure and optical power reading photos via multipart/form-data PUT /api/LCPNapLocations/{id}.
  // Gene - Oct 31, 2026: Added clear flags (clearImage, clearImage2, clearReadingImage) to support deleting/clearing photos by sending empty image file/omission per backend API contract.
  Future<bool> uploadLcpNapPhotos({
    required int locationId,
    required LcpNapDto location,
    Uint8List? imageBytes,
    Uint8List? image2Bytes,
    Uint8List? readingImageBytes,
    bool clearImage = false,
    bool clearImage2 = false,
    bool clearReadingImage = false,
  }) async {
    try {
      final map = <String, dynamic>{
        'LCP': location.lcp,
        'NAP': location.nap,
        'LCPNAP': location.lcpNap,
        'PortTotal': location.portTotal.toString(),
        if (location.coordinates != null) 'Coordinates': location.coordinates,
        if (location.street != null) 'Street': location.street,
        if (location.barangay != null) 'Barangay': location.barangay,
        if (location.city != null) 'City': location.city,
        if (location.region != null) 'Region': location.region,
      };

      // 1. Enclosure Exterior (image)
      if (clearImage) {
        // Gene - Oct 31, 2026: Send empty 0-byte file when explicitly clearing/deleting photo per backend team instructions
        map['Image'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (imageBytes != null && imageBytes.isNotEmpty) {
        map['Image'] =
            MultipartFile.fromBytes(imageBytes, filename: 'image.jpg');
      } else {
        final existingBytes = _imagesCache[locationId]?.image?.bytes;
        if (existingBytes != null && existingBytes.isNotEmpty) {
          map['Image'] =
              MultipartFile.fromBytes(existingBytes, filename: 'image.jpg');
        }
      }

      // 2. Enclosure Interior (image2)
      if (clearImage2) {
        map['Image2'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (image2Bytes != null && image2Bytes.isNotEmpty) {
        map['Image2'] =
            MultipartFile.fromBytes(image2Bytes, filename: 'image2.jpg');
      } else {
        final existingBytes = _imagesCache[locationId]?.image2?.bytes;
        if (existingBytes != null && existingBytes.isNotEmpty) {
          map['Image2'] =
              MultipartFile.fromBytes(existingBytes, filename: 'image2.jpg');
        }
      }

      // 3. Optical Power Reading (readingImage)
      if (clearReadingImage) {
        map['ReadingImage'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (readingImageBytes != null && readingImageBytes.isNotEmpty) {
        map['ReadingImage'] = MultipartFile.fromBytes(readingImageBytes,
            filename: 'readingImage.jpg');
      } else {
        final existingBytes = _imagesCache[locationId]?.readingImage?.bytes;
        if (existingBytes != null && existingBytes.isNotEmpty) {
          map['ReadingImage'] = MultipartFile.fromBytes(existingBytes,
              filename: 'readingImage.jpg');
        }
      }

      final formData = FormData.fromMap(map);
      final response = await _api.put(
        '/LCPNapLocations/$locationId',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      final isSuccess =
          response.statusCode == 200 || response.statusCode == 204;
      /*
      if (isSuccess) {
        _imagesCache.remove(locationId);
        await getLcpNapLocationImages(locationId, forceRefresh: true);
      }
      */
      // Gene - Oct 29, 2026: Invalidate image cache upon successful upload; callers refresh on demand.
      if (isSuccess) {
        _imagesCache.remove(locationId);
      }
      return isSuccess;
    } catch (_) {
      return false;
    }
  }

  // Gene - Oct 31, 2026: Updates LCP NAP location coordinates and address fields via multipart/form-data PUT /api/LCPNapLocations/{id} and saves to local SQLite.
  Future<bool> updateLocationCoordinates({
    required int locationId,
    required LcpNapDto location,
    required String coordinates,
    String? street,
    String? barangay,
    String? city,
    String? region,
  }) async {
    try {
      final map = <String, dynamic>{
        'LCP': location.lcp,
        'NAP': location.nap,
        'LCPNAP': location.lcpNap,
        'PortTotal': location.portTotal.toString(),
        'Coordinates': coordinates,
        if (street != null || location.street != null)
          'Street': street ?? location.street,
        if (barangay != null || location.barangay != null)
          'Barangay': barangay ?? location.barangay,
        if (city != null || location.city != null)
          'City': city ?? location.city,
        if (region != null || location.region != null)
          'Region': region ?? location.region,
      };

      // Preserve existing cached photos if available
      final existingEnc1 = _imagesCache[locationId]?.image?.bytes;
      if (existingEnc1 != null && existingEnc1.isNotEmpty) {
        map['Image'] =
            MultipartFile.fromBytes(existingEnc1, filename: 'image.jpg');
      }
      final existingEnc2 = _imagesCache[locationId]?.image2?.bytes;
      if (existingEnc2 != null && existingEnc2.isNotEmpty) {
        map['Image2'] =
            MultipartFile.fromBytes(existingEnc2, filename: 'image2.jpg');
      }
      final existingReading = _imagesCache[locationId]?.readingImage?.bytes;
      if (existingReading != null && existingReading.isNotEmpty) {
        map['ReadingImage'] = MultipartFile.fromBytes(existingReading,
            filename: 'readingImage.jpg');
      }

      final formData = FormData.fromMap(map);
      final response = await _api.put(
        '/LCPNapLocations/$locationId',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      final isSuccess =
          response.statusCode == 200 || response.statusCode == 204;
      if (isSuccess) {
        final updatedDto = location.copyWith(
          coordinates: coordinates,
          street: street ?? location.street,
          barangay: barangay ?? location.barangay,
          city: city ?? location.city,
          region: region ?? location.region,
          isSynced: true,
          updatedAt: DateTime.now(),
        );
        await _dao.insertOrUpdateLocation(updatedDto, synced: true);
      }
      return isSuccess;
    } catch (_) {
      // Local optimistic fallback when offline
      final updatedDto = location.copyWith(
        coordinates: coordinates,
        street: street ?? location.street,
        barangay: barangay ?? location.barangay,
        city: city ?? location.city,
        region: region ?? location.region,
        isSynced: false,
        updatedAt: DateTime.now(),
      );
      await _dao.insertOrUpdateLocation(updatedDto, synced: false);
      return true;
    }
  }
}
