import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/database/daos/lcp_nap_dao.dart';
import '../../../core/network/api_client.dart';
import '../models/lcp_nap_images_model.dart';
import '../models/lcp_nap_model.dart';

/// Repository coordinating LCP NAP locations between the API and the local database.
class LcpNapRepository {
  final LcpNapLocationsDao _dao;
  final ApiClient _api = ApiClient.instance;

  LcpNapRepository(this._dao);

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
      final response =
          await _api.get('/LCPNapLocations/$locationId/GetLCPNAPLocationImages');
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

        if (dto.hasAnyPhoto) {
          _imagesCache[locationId] = dto;
        }
        return dto;
      }
    } catch (_) {
      // Offline fallback or test mock
    }
    return _imagesCache[locationId];
  }
}

