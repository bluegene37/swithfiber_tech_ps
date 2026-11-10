// Gene - Nov, 11, 2026: Comprehensive TDD test suite for LCP NAP Location Image Upload & GPS Auto-Sync (Online, Offline Queue, Reconnect, Cross-Device Remote Sync, Pull-to-Refresh, Re-entry, and TechnicianShell lifecycle triggers).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/database/daos/lcp_nap_dao.dart';
import 'package:swithfiber_tech_ps/core/network/api_client.dart';
import 'package:swithfiber_tech_ps/core/network/network_connectivity_service.dart';
import 'package:swithfiber_tech_ps/core/services/photo_storage_service.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/auth/models/user_model.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/models/lcp_nap_images_model.dart';
// import 'package:swithfiber_tech_ps/features/lcp_nap/models/lcp_nap_model.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/screens/lcp_nap_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/services/service_orders_api.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';
import 'package:swithfiber_tech_ps/features/shell/technician_shell.dart';

const _samplePngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

final _samplePngBytes = base64Decode(_samplePngBase64);

class _OfflineTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(Uint8List.fromList(_samplePngBytes));
}

/// Programmable HTTP adapter simulating the Switch Fiber `/LCPNapLocations` backend,
/// including network outages, remote technician uploads, and server-side state mutations.
class _SimulatedPlantBackendAdapter implements HttpClientAdapter {
  bool isOnline = true;
  final capturedRequests = <RequestOptions>[];

  /// Server-side plant location records keyed by ID.
  final Map<int, Map<String, dynamic>> serverLocations = {};

  /// Server-side image payloads keyed by ID (`image`, `image2`, `readingImage`).
  final Map<int, Map<String, dynamic>> serverImages = {};

  int getListCalls = 0;
  int getImagesCalls = 0;
  int putCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedRequests.add(options);

    if (!isOnline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Simulated offline network',
      );
    }

    final path = options.path;
    final method = options.method.toUpperCase();

    // GET /LCPNapLocations
    if (method == 'GET' && path == '/LCPNapLocations') {
      getListCalls++;
      return ResponseBody.fromString(
        jsonEncode(serverLocations.values.toList()),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    // GET /LCPNapLocations/{id}/GetLCPNAPLocationImages
    final imagesMatch = RegExp(
      r'^/LCPNapLocations/(\d+)/GetLCPNAPLocationImages$',
    ).firstMatch(path);
    if (method == 'GET' && imagesMatch != null) {
      getImagesCalls++;
      final id = int.parse(imagesMatch.group(1)!);
      final payload = serverImages[id] ??
          <String, dynamic>{
            'image': null,
            'image2': null,
            'readingImage': null,
          };
      return ResponseBody.fromString(
        jsonEncode(payload),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    // GET /LCPNapLocations/{id}/GetReadingImage
    final readingMatch = RegExp(
      r'^/LCPNapLocations/(\d+)/GetReadingImage$',
    ).firstMatch(path);
    if (method == 'GET' && readingMatch != null) {
      return ResponseBody.fromBytes(
        const <int>[],
        200,
        headers: {
          Headers.contentTypeHeader: ['image/jpeg'],
        },
      );
    }

    // PUT /LCPNapLocations/{id}
    final putMatch = RegExp(r'^/LCPNapLocations/(\d+)$').firstMatch(path);
    if (method == 'PUT' && putMatch != null) {
      putCalls++;
      final id = int.parse(putMatch.group(1)!);
      final existingLoc = Map<String, dynamic>.from(
        serverLocations[id] ?? <String, dynamic>{'id': id},
      );
      final existingImg = Map<String, dynamic>.from(
        serverImages[id] ??
            <String, dynamic>{
              'image': null,
              'image2': null,
              'readingImage': null,
            },
      );

      final data = options.data;
      if (data is FormData) {
        final fields = {for (final e in data.fields) e.key: e.value};
        if (fields['LCP'] != null) existingLoc['lcp'] = fields['LCP'];
        if (fields['NAP'] != null) existingLoc['nap'] = fields['NAP'];
        if (fields['LCPNAP'] != null) existingLoc['lcpNap'] = fields['LCPNAP'];
        if (fields['PortTotal'] != null) {
          existingLoc['portTotal'] = int.tryParse(fields['PortTotal']!) ?? 8;
        }
        if (fields.containsKey('Coordinates')) {
          existingLoc['coordinates'] = fields['Coordinates'];
        }
        if (fields.containsKey('Street')) {
          existingLoc['street'] = fields['Street'];
        }
        if (fields.containsKey('Barangay')) {
          existingLoc['barangay'] = fields['Barangay'];
        }
        if (fields.containsKey('City')) {
          existingLoc['city'] = fields['City'];
        }
        if (fields.containsKey('Region')) {
          existingLoc['region'] = fields['Region'];
        }
        existingLoc['modifiedBy'] = fields['ModifiedBy'] ?? '1';
        existingLoc['modifiedDate'] =
            fields['ModifiedDate'] ?? DateTime.now().toUtc().toIso8601String();
        if (fields['UserEmail'] != null) {
          existingLoc['userEmail'] = fields['UserEmail'];
        }

        // Backend contract: PUT /LCPNapLocations/{id} replaces file slots based on submitted FormData files:
        // - omitted file when not resent = cleared on backend unless preserved by client!
        // - 0-byte file = explicitly cleared!
        final files = {for (final f in data.files) f.key: f.value};

        Future<Map<String, dynamic>?> decodeSlot(MultipartFile? mf) async {
          if (mf == null) return null;
          if (mf.length == 0) return null;
          // Note: Dio calls FormData.finalize() before HttpClientAdapter.fetch(),
          // so mf.isFinalized is already true here; mf.length accurately reflects
          // non-empty uploaded image bytes vs 0-byte delete markers.
          return <String, dynamic>{
            'fileContents': _samplePngBase64,
            'contentType': mf.contentType?.mimeType ?? 'image/png',
            'fileDownloadName': mf.filename ?? 'photo.jpg',
          };
        }

        // Consume requestStream if provided by Dio
        if (requestStream != null) {
          await requestStream.drain<void>();
        }

        existingImg['image'] = await decodeSlot(files['Image']);
        existingImg['image2'] = await decodeSlot(files['Image2']);
        existingImg['readingImage'] = await decodeSlot(files['ReadingImage']);
      }

      serverLocations[id] = existingLoc;
      serverImages[id] = existingImg;

      return ResponseBody.fromString(
        jsonEncode(existingLoc),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    // Default stub for unrelated endpoints (e.g., Auth profile refresh in TechnicianShell)
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _NoopJobsApi extends JobOrdersApi {
  @override
  Future<List<Map<String, dynamic>>> fetchByStatus(String status) async => [];

  @override
  Future<List<Map<String, dynamic>>> fetchByStatusAssigned({
    required String status,
    String? assignedEmail,
  }) async =>
      [];

  @override
  Future<List<Map<String, dynamic>>> fetchByStatusDate({
    String? status,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async =>
      [];

  @override
  Future<Map<String, dynamic>?> fetchById(int id) async => null;

  @override
  Future<void> update(int id, Map<String, dynamic> body) async {}
}

class _NoopServiceApi extends ServiceOrdersApi {
  @override
  Future<List<ServiceOrderDto>> fetchServiceOrders() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LCP NAP Image Upload & GPS Auto-Sync Comprehensive Suite', () {
    late Directory tempDir;
    late _SimulatedPlantBackendAdapter backend;
    late HttpClientAdapter originalAdapter;
    late AppDatabase db;
    late LcpNapLocationsDao dao;
    late LcpNapRepository repo;
    late LcpNapSignals signals;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('lcp_nap_autosync_test_');
      PhotoStorageService.instance.setDirectoryForTesting(tempDir);

      backend = _SimulatedPlantBackendAdapter();
      backend.serverLocations[101] = {
        'id': 101,
        'lcp': 'LCP 01',
        'nap': 'NAP 01',
        'lcpNap': 'LCP 01 - NAP 01',
        'portTotal': 8,
        'coordinates': '14.586200, 121.061800',
        'street': 'Emerald Ave',
        'barangay': 'San Antonio',
        'city': 'Pasig',
        'region': 'NCR',
        'modifiedBy': '1',
        'modifiedDate': '2026-11-10T08:00:00.000Z',
      };
      backend.serverImages[101] = {
        'image': null,
        'image2': null,
        'readingImage': null,
      };

      final dio = ApiClient.instance.dio;
      originalAdapter = dio.httpClientAdapter;
      dio.httpClientAdapter = backend;
      ApiClient.blockNetworkForTesting = false;

      db = AppDatabase.forTesting();
      dao = LcpNapLocationsDao(db);
      repo = LcpNapRepository(dao);
      signals = LcpNapSignals(repo);

      await repo.fetchRemoteLocations();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    tearDown(() async {
      ApiClient.blockNetworkForTesting = true;
      ApiClient.instance.dio.httpClientAdapter = originalAdapter;
      PhotoStorageService.instance.setDirectoryForTesting(null);
      NetworkConnectivityService.resetInstance();
      await signals.dispose();
      await db.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'TC1: Offline photo upload queues locally (isSynced=false), survives offline fetchRemote, and auto-syncs PUT when back online',
        () async {
      backend.isOnline = false;
      final loc = (await dao.getAllLocations()).single;

      // Upload exterior and reading photos while offline
      final savedLocally = await signals.uploadLocationPhotos(
        locationId: 101,
        location: loc,
        imageBytes: _samplePngBytes,
        readingImageBytes: _samplePngBytes,
      );

      expect(savedLocally, isTrue,
          reason:
              'Offline photo upload must save locally and queue for auto-sync rather than failing');
      expect(backend.putCalls, 0);

      final offlineRow = (await dao.getAllLocations()).single;
      expect(offlineRow.isSynced, isFalse,
          reason: 'Offline uploaded photo row must be marked isSynced=false');
      expect(offlineRow.image, isNotNull);
      expect(offlineRow.readingImage, isNotNull);

      // Periodic fetchRemote while still offline must NOT clobber unsynced local photo row
      await signals.fetchRemote();
      final stillPendingRow = (await dao.getAllLocations()).single;
      expect(stillPendingRow.isSynced, isFalse);
      expect(stillPendingRow.image, isNotNull);

      // Restore network connectivity and run auto-sync (fetchRemote)
      backend.isOnline = true;
      await signals.fetchRemote();

      expect(backend.putCalls, 1,
          reason:
              'Auto-sync must automatically push queued offline photo upload to PUT /LCPNapLocations/101');
      expect(backend.serverImages[101]!['image'], isNotNull);
      expect(backend.serverImages[101]!['readingImage'], isNotNull);

      final syncedRow = (await dao.getAllLocations()).single;
      expect(syncedRow.isSynced, isTrue,
          reason: 'Row must flip to isSynced=true after auto-sync completes');
    });

    test(
        'TC2: Offline single-photo deletion queues 0-byte clear marker while preserving sibling photo and auto-syncs on reconnect',
        () async {
      // First upload 2 photos while online
      final initialLoc = (await dao.getAllLocations()).single;
      await signals.uploadLocationPhotos(
        locationId: 101,
        location: initialLoc,
        imageBytes: _samplePngBytes,
        image2Bytes: _samplePngBytes,
      );
      expect(backend.serverImages[101]!['image'], isNotNull);
      expect(backend.serverImages[101]!['image2'], isNotNull);
      final putBeforeOffline = backend.putCalls;

      // Now go offline and delete slot 1 (clearImage: true)
      backend.isOnline = false;
      final withPhotosLoc = (await dao.getAllLocations()).single;
      final queuedDelete = await signals.uploadLocationPhotos(
        locationId: 101,
        location: withPhotosLoc,
        clearImage: true,
      );

      expect(queuedDelete, isTrue);
      final pendingRow = (await dao.getAllLocations()).single;
      expect(pendingRow.isSynced, isFalse);

      // Reconnect and auto-sync
      backend.isOnline = true;
      await signals.fetchRemote();

      expect(backend.putCalls, greaterThan(putBeforeOffline));
      expect(backend.serverImages[101]!['image'], isNull,
          reason: 'Deleted slot 1 must be cleared on server after reconnect');
      expect(backend.serverImages[101]!['image2'], isNotNull,
          reason: 'Sibling slot 2 must be preserved on server after reconnect');

      final finalRow = (await dao.getAllLocations()).single;
      expect(finalRow.isSynced, isTrue);
      expect(finalRow.image, isNull);
    });

    test(
        'TC3: Offline GPS coordinates update is NOT overwritten by fetchRemoteLocations and auto-syncs PUT with audit metadata when online',
        () async {
      backend.isOnline = false;
      final loc = (await dao.getAllLocations()).single;

      final savedOffline = await signals.updateLocationCoordinates(
        locationId: 101,
        location: loc,
        coordinates: '14.612345, 121.098765',
        street: 'Updated Offline Street',
        barangay: 'Ugong',
        city: 'Pasig',
        region: 'NCR',
      );
      expect(savedOffline, isTrue);

      final offlineRow = (await dao.getAllLocations()).single;
      expect(offlineRow.isSynced, isFalse);
      expect(offlineRow.coordinates, '14.612345, 121.098765');

      // Now server comes back online BEFORE pending sync — fetchRemote MUST push pending GPS first, NOT overwrite with old 14.586200!
      backend.isOnline = true;
      await signals.fetchRemote();

      expect(backend.putCalls, 1,
          reason:
              'Offline GPS update must be pushed to PUT /LCPNapLocations/101 during auto-sync');
      expect(
          backend.serverLocations[101]!['coordinates'], '14.612345, 121.098765');
      expect(
          backend.serverLocations[101]!['street'], 'Updated Offline Street');

      final lastPut = backend.capturedRequests
          .lastWhere((r) => r.method == 'PUT' && r.path == '/LCPNapLocations/101');
      final formFields = {
        for (final e in (lastPut.data as FormData).fields) e.key: e.value
      };
      expect(formFields['ModifiedDate'], isNotEmpty,
          reason: 'GPS PUT must include ModifiedDate so other devices detect change');
      expect(formFields['ModifiedBy'], isNotEmpty);

      final syncedRow = (await dao.getAllLocations()).single;
      expect(syncedRow.isSynced, isTrue);
      expect(syncedRow.coordinates, '14.612345, 121.098765');
    });

    test(
        'TC4: Online GPS update preserves existing server photos even when in-memory _imagesCache is cold',
        () async {
      // Simulate another technician having uploaded an image on the server
      backend.serverImages[101] = {
        'image': {
          'fileContents': _samplePngBase64,
          'contentType': 'image/png',
          'fileDownloadName': 'existing_server_photo.png',
        },
        'image2': null,
        'readingImage': null,
      };
      repo.clearImagesCache();

      final loc = (await dao.getAllLocations()).single;
      final ok = await signals.updateLocationCoordinates(
        locationId: 101,
        location: loc,
        coordinates: '14.650000, 121.070000',
      );

      expect(ok, isTrue);
      expect(backend.serverLocations[101]!['coordinates'],
          '14.650000, 121.070000');
      expect(
        backend.serverImages[101]!['image'],
        isNotNull,
        reason:
            'Updating GPS coordinates when _imagesCache is cold must NOT wipe existing server photos',
      );
    });

    test(
        'TC5: Combined offline GPS update + offline photo upload pushes BOTH coordinates and photos on reconnect',
        () async {
      backend.isOnline = false;
      final loc0 = (await dao.getAllLocations()).single;

      await signals.updateLocationCoordinates(
        locationId: 101,
        location: loc0,
        coordinates: '14.700000, 121.100000',
        street: 'Combined Ave',
      );

      final locWithGps = (await dao.getAllLocations()).single;
      await signals.uploadLocationPhotos(
        locationId: 101,
        location: locWithGps,
        imageBytes: _samplePngBytes,
      );

      backend.isOnline = true;
      await signals.fetchRemote();

      expect(backend.serverLocations[101]!['coordinates'],
          '14.700000, 121.100000');
      expect(backend.serverLocations[101]!['street'], 'Combined Ave');
      expect(backend.serverImages[101]!['image'], isNotNull);

      final syncedRow = (await dao.getAllLocations()).single;
      expect(syncedRow.isSynced, isTrue);
    });

    test(
        'TC6: Remote image uploaded by another user syncs after fetchRemote without closing & reopening app',
        () async {
      // 1. User visits NAP 101 when it has NO photos -> caches empty DTO in _imagesCache
      final initialPhotos = await repo.getLcpNapLocationImages(101);
      expect(initialPhotos?.hasAnyPhoto, isFalse);

      // 2. Another technician uploads an image on the server & modifiedDate advances
      backend.serverImages[101] = {
        'image': {
          'fileContents': _samplePngBase64,
          'contentType': 'image/png',
          'fileDownloadName': 'remote_tech_upload.png',
        },
        'image2': null,
        'readingImage': null,
      };
      backend.serverLocations[101]!['modifiedDate'] =
          '2026-11-11T05:30:00.000Z';

      // 3. Background sync runs fetchRemote() (without restarting the app!)
      await signals.fetchRemote();

      // 4. Subsequent getLcpNapLocationImages(101) MUST return the newly uploaded photo, NOT stale empty cache!
      final refreshedPhotos = await repo.getLcpNapLocationImages(101);
      expect(
        refreshedPhotos?.image?.hasImage,
        isTrue,
        reason:
            'Remote image upload must auto-sync after fetchRemote invalidates stale _imagesCache without restarting app',
      );
    });

    test(
        'TC7: Force refresh while offline preserves previously cached photos instead of wiping _imagesCache to null',
        () async {
      backend.serverImages[101] = {
        'image': {
          'fileContents': _samplePngBase64,
          'contentType': 'image/png',
          'fileDownloadName': 'cached.png',
        },
        'image2': null,
        'readingImage': null,
      };

      final loaded = await repo.getLcpNapLocationImages(101, forceRefresh: true);
      expect(loaded?.image?.hasImage, isTrue);

      // Phone drops offline and 15s background photo timer calls forceRefresh: true
      backend.isOnline = false;
      final offlineRefresh =
          await repo.getLcpNapLocationImages(101, forceRefresh: true);
      expect(
        offlineRefresh?.image?.hasImage,
        isTrue,
        reason:
            'Offline forceRefresh must retain last known cached photos instead of evicting before GET succeeds',
      );
    });

    testWidgets(
        'TC8: Re-opening LcpNapDetailScreen and pull-to-refresh immediately sync remote uploaded image without app restart',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // First visit: 0 photos on server -> caches empty DTO
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: LcpNapDetailScreen(
              locationId: 101,
              signals: signals,
              tileProvider: _OfflineTileProvider(),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      expect(
        find.text('No enclosure or optical reading photos uploaded yet.'),
        findsOneWidget,
      );

      // Remote user uploads Enclosure Exterior while screen is open -> user pulls to refresh
      backend.serverImages[101] = {
        'image': {
          'fileContents': _samplePngBase64,
          'contentType': 'image/png',
          'fileDownloadName': 'pulled.png',
        },
        'image2': null,
        'readingImage': null,
      };

      // Pull down from the top card to trigger RefreshIndicator.onRefresh,
      // then allow real SQLite + Dio async work to complete inside runAsync.
      await tester.fling(
        find.text('Port Matrix & Capacity'),
        const Offset(0, 500),
        1200,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text('1 photos'),
        findsOneWidget,
        reason:
            'Pull-to-refresh on LcpNapDetailScreen must pass forceRefresh: true and show newly uploaded remote photo',
      );

      // Now close screen, remote user uploads a 2nd photo (image2), and user re-opens LcpNapDetailScreen WITHOUT fetchRemote
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      backend.serverImages[101] = {
        'image': {
          'fileContents': _samplePngBase64,
          'contentType': 'image/png',
          'fileDownloadName': 'pulled.png',
        },
        'image2': {
          'fileContents': _samplePngBase64,
          'contentType': 'image/png',
          'fileDownloadName': 'second_remote.png',
        },
        'readingImage': null,
      };

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: LcpNapDetailScreen(
              locationId: 101,
              signals: signals,
              tileProvider: _OfflineTileProvider(),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('2 photos'),
        findsOneWidget,
        reason:
            'Re-entering LcpNapDetailScreen must force-refresh live server photos rather than staying stuck on stale _imagesCache',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
        'TC9: LcpNapDetailScreen live offline photo upload shows cloud_off and auto-flips to cloud_done + updates mini-map on GPS sync',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      backend.isOnline = false;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: LcpNapDetailScreen(
              locationId: 101,
              signals: signals,
              tileProvider: _OfflineTileProvider(),
              initialImagesForTesting: const LcpNapImagesDto(),
              pickImageForTesting: (_) async =>
                  'data:image/png;base64,$_samplePngBase64',
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);

      // Upload photo while offline via UI sheet
      await tester.tap(find.text('Upload Site Photos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Tap Enclosure Exterior PhotoCaptureTile to pick test image
      await tester.tap(find.text('Enclosure Exterior'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // If camera/gallery chooser opens, tap Camera or Gallery; otherwise tile picked directly
      if (find.text('Take photo with GPS').evaluate().isNotEmpty) {
        await tester.tap(find.text('Take photo with GPS'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      } else if (find.text('Choose from photo library').evaluate().isNotEmpty) {
        await tester.tap(find.text('Choose from photo library'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.runAsync(() async {
        await tester.tap(find.text('Save & Upload Photos'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Sheet should close, photo should appear optimistically, and sync badge must show cloud_off_rounded
      expect(find.text('1 photos'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget,
          reason: 'Offline uploaded photo must show unsynced cloud_off glyph');

      // Now network comes back and remote GPS also updates
      backend.isOnline = true;
      await tester.runAsync(() async {
        await signals.fetchRemote();
        // Now simulate remote GPS update on server and pull again
        backend.serverLocations[101]!['coordinates'] = '14.999999, 121.888888';
        backend.serverLocations[101]!['modifiedDate'] =
            '2026-11-11T06:00:00.000Z';
        await signals.fetchRemote();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();

      expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget,
          reason:
              'Sync glyph must automatically flip back to cloud_done_rounded once synced');
      expect(find.text('14.999999, 121.888888'), findsOneWidget,
          reason:
              'Remote GPS coordinates must auto-update live on LcpNapDetailScreen');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
        'TC10: TechnicianShell reconnect listener & Plant tab re-tap auto-sync pending LCP NAP uploads and remote updates',
        (tester) async {
      late JobRepository jobRepo;
      late JobsSignals jobsSignals;
      late ServiceOrdersSignals serviceSignals;
      late StreamController<bool> connController;

      await tester.runAsync(() async {
        connController = StreamController<bool>.broadcast();
        NetworkConnectivityService.instance = NetworkConnectivityService(
          connectionStream: connController.stream,
          initialConnected: false,
        );

        jobRepo = JobRepository(db.jobOrdersDao, api: _NoopJobsApi());
        jobsSignals = JobsSignals(jobRepo);
        jobsSignals.setTechnicianEmail('tech@switchfiber.ph');
        serviceSignals = ServiceOrdersSignals(api: _NoopServiceApi());

        // Queue an offline GPS + photo edit BEFORE shell reconnects
        backend.isOnline = false;
        final loc = (await dao.getAllLocations()).single;
        await signals.updateLocationCoordinates(
          locationId: 101,
          location: loc,
          coordinates: '14.555555, 121.444444',
        );
        final loc2 = (await dao.getAllLocations()).single;
        await signals.uploadLocationPhotos(
          locationId: 101,
          location: loc2,
          imageBytes: _samplePngBytes,
        );
      });

      addTearDown(() async {
        await connController.close();
        await jobsSignals.dispose();
        serviceSignals.dispose();
      });

      AuthSignals.instance.currentUser.value = UserModel(
        id: 1,
        username: 'tech_juan',
        fname: 'Juan',
        lname: 'Dela Cruz',
        email: 'tech@switchfiber.ph',
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: TechnicianShell(
              authSignals: AuthSignals.instance,
              jobsSignals: jobsSignals,
              lcpNapSignals: signals,
              serviceOrdersSignals: serviceSignals,
              enableAutoSync: false,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      });
      await tester.pump();

      expect(backend.putCalls, 0);

      // Restore online connectivity -> NetworkConnectivityService must flush pending LCP NAP edits!
      backend.isOnline = true;
      await tester.runAsync(() async {
        connController.add(true);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(
        backend.putCalls,
        greaterThanOrEqualTo(1),
        reason:
            'NetworkConnectivityService online transition in TechnicianShell must auto-sync pending LCP NAP edits',
      );
      expect(
          backend.serverLocations[101]!['coordinates'], '14.555555, 121.444444');
      expect(backend.serverImages[101]!['image'], isNotNull);

      // Switch to Plant tab, then re-tap Plant tab -> must trigger forced background sync
      await tester.runAsync(() async {
        await tester.tap(find.text('Plant'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();

      final listCallsAfterSwitch = backend.getListCalls;

      // Re-tap Plant bottom tab item while already on Plant tab
      await tester.runAsync(() async {
        await tester.tap(find.text('Plant').last);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();

      expect(
        backend.getListCalls,
        greaterThan(listCallsAfterSwitch),
        reason:
            'Re-tapping Plant tab must trigger immediate forced background sync',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
        'TC11: Open LcpNapDetailScreen auto-refreshes live when background fetchRemote runs after remote image upload',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: LcpNapDetailScreen(
              locationId: 101,
              signals: signals,
              tileProvider: _OfflineTileProvider(),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      expect(
        find.text('No enclosure or optical reading photos uploaded yet.'),
        findsOneWidget,
      );

      // Another technician uploads an image on the server while this user has LcpNapDetailScreen open
      backend.serverImages[101] = {
        'image': {
          'fileContents': _samplePngBase64,
          'contentType': 'image/png',
          'fileDownloadName': 'live_remote_upload.png',
        },
        'image2': null,
        'readingImage': null,
      };
      backend.serverLocations[101]!['modifiedDate'] =
          '2026-11-11T07:00:00.000Z';

      // Background sync runs (e.g., TechnicianShell periodic sync or reconnect)
      await tester.runAsync(() async {
        await signals.fetchRemote();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('1 photos'),
        findsOneWidget,
        reason:
            'Open LcpNapDetailScreen must reactively reload site photos when background fetchRemote runs',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
