import 'dart:async';
import '../../../core/database/daos/lcp_nap_dao.dart';
import '../../../core/network/api_client.dart';
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
}
