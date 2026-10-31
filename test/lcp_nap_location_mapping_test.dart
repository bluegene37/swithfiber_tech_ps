// Gene - Oct 31, 2026: Comprehensive tests for LCP NAP Location Mapping, GPS acquisition, Map Pinning, and coordinate update flows.

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/database/daos/lcp_nap_dao.dart';
import 'package:swithfiber_tech_ps/core/network/api_client.dart';
import 'package:swithfiber_tech_ps/core/services/location_service.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/models/lcp_nap_model.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/models/lcp_nap_images_model.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/screens/lcp_nap_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/widgets/lcp_nap_location_picker_sheet.dart';

final _blankTile = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _OfflineTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(Uint8List.fromList(_blankTile));
}

class _RecordingAdapter implements HttpClientAdapter {
  final captured = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    captured.add(options);
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

class _FakeLocationService extends LocationService {
  final Position? fakePosition;
  _FakeLocationService({this.fakePosition});

  @override
  Future<Position?> getCurrentPosition({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    return fakePosition;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final samplePosition = Position(
    latitude: 14.586200,
    longitude: 121.061800,
    timestamp: DateTime.now(),
    accuracy: 5.0,
    altitude: 10.0,
    altitudeAccuracy: 1.0,
    heading: 0.0,
    headingAccuracy: 1.0,
    speed: 0.0,
    speedAccuracy: 0.0,
  );

  group('LcpNapDto copyWith Tests', () {
    test('creates updated instance preserving unchanged properties', () {
      final original = LcpNapDto(
        id: 10,
        lcp: 'LCP 05',
        nap: 'NAP 02',
        lcpNap: 'LCP 05 - NAP 02',
        portTotal: 16,
        coordinates: '14.5000, 121.1000',
        street: 'Old Street',
        barangay: 'Old Barangay',
        city: 'Old City',
        region: 'Old Region',
      );

      final updated = original.copyWith(
        coordinates: '14.586200, 121.061800',
        street: 'New Street',
        city: 'Pasig City',
      );

      expect(updated.id, 10);
      expect(updated.lcp, 'LCP 05');
      expect(updated.nap, 'NAP 02');
      expect(updated.coordinates, '14.586200, 121.061800');
      expect(updated.street, 'New Street');
      expect(updated.barangay, 'Old Barangay');
      expect(updated.city, 'Pasig City');
      expect(updated.region, 'Old Region');
      expect(updated.portTotal, 16);
    });
  });

  group('LcpNapRepository updateLocationCoordinates Tests', () {
    late AppDatabase db;
    late LcpNapLocationsDao dao;
    late _RecordingAdapter adapter;
    late HttpClientAdapter original;
    late LcpNapRepository repo;
    late LcpNapSignals signals;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      adapter = _RecordingAdapter();
      final dio = ApiClient.instance.dio;
      ApiClient.blockNetworkForTesting = false;
      original = dio.httpClientAdapter;
      dio.httpClientAdapter = adapter;

      db = AppDatabase.forTesting();
      dao = LcpNapLocationsDao(db);
      repo = LcpNapRepository(dao);
      signals = LcpNapSignals(repo);

      addTearDown(() async {
        ApiClient.blockNetworkForTesting = true;
        ApiClient.instance.dio.httpClientAdapter = original;
        await signals.dispose();
        await db.close();
      });
    });

    test('sends multipart PUT to /LCPNapLocations/{id} and updates local DB',
        () async {
      final loc = LcpNapDto(
        id: 42,
        lcp: 'LCP 01',
        nap: 'NAP 08',
        lcpNap: 'LCP 01 - NAP 08',
        portTotal: 8,
      );
      await dao.insertOrUpdateLocation(loc);

      final success = await repo.updateLocationCoordinates(
        locationId: 42,
        location: loc,
        coordinates: '14.586200, 121.061800',
        street: 'Emerald Ave',
        barangay: 'San Antonio',
        city: 'Pasig',
        region: 'NCR',
      );

      expect(success, isTrue);
      expect(adapter.captured.length, 1);
      final req = adapter.captured.first;
      expect(req.method, 'PUT');
      expect(req.path, '/LCPNapLocations/42');
      expect(req.data, isA<FormData>());

      final formData = req.data as FormData;
      final fieldMap = {
        for (final entry in formData.fields) entry.key: entry.value
      };
      expect(fieldMap['Coordinates'], '14.586200, 121.061800');
      expect(fieldMap['Street'], 'Emerald Ave');
      expect(fieldMap['Barangay'], 'San Antonio');
      expect(fieldMap['City'], 'Pasig');
      expect(fieldMap['Region'], 'NCR');
      expect(fieldMap['LCP'], 'LCP 01');
      expect(fieldMap['NAP'], 'NAP 08');

      // Check that local database was updated
      final fromDb = await dao.getAllLocations();
      final updatedLoc = fromDb.firstWhere((l) => l.id == 42);
      expect(updatedLoc.coordinates, '14.586200, 121.061800');
      expect(updatedLoc.street, 'Emerald Ave');
      expect(updatedLoc.barangay, 'San Antonio');
      expect(updatedLoc.city, 'Pasig');
      expect(updatedLoc.isSynced, isTrue);
    });

    test('signals updateLocationCoordinates delegates to repository', () async {
      final loc = LcpNapDto(
        id: 15,
        lcp: 'LCP 02',
        nap: 'NAP 03',
        lcpNap: 'LCP 02 - NAP 03',
      );
      await dao.insertOrUpdateLocation(loc);

      final success = await signals.updateLocationCoordinates(
        locationId: 15,
        location: loc,
        coordinates: '14.600000, 121.050000',
      );

      expect(success, isTrue);
      expect(adapter.captured.length, 1);
      final req = adapter.captured.last;
      expect(req.path, '/LCPNapLocations/15');
    });
  });

  group('LcpNapLocationPickerSheet Widget Tests', () {
    late AppDatabase db;
    late LcpNapLocationsDao dao;
    late LcpNapSignals signals;
    late LcpNapRepository repo;

    setUp(() {
      db = AppDatabase.forTesting();
      dao = LcpNapLocationsDao(db);
      repo = LcpNapRepository(dao);
      signals = LcpNapSignals(repo);
    });

    tearDown(() async {
      await signals.dispose();
      await db.close();
    });

    testWidgets(
        'acquires GPS coordinates via Current GPS button and pre-fills address',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final loc = LcpNapDto(
        id: 1,
        lcp: 'LCP 01',
        nap: 'NAP 01',
        lcpNap: 'LCP 01 - NAP 01',
      );

      final fakeLocationService =
          _FakeLocationService(fakePosition: samplePosition);

      Future<List<geo.Placemark>> fakeReverseGeocode(
          double lat, double lng) async {
        return [
          const geo.Placemark(
            street: 'Ortigas Ave',
            subLocality: 'San Antonio',
            locality: 'Pasig',
            administrativeArea: 'NCR',
          ),
        ];
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LcpNapLocationPickerSheet(
              location: loc,
              signals: signals,
              tileProvider: _OfflineTileProvider(),
              locationService: fakeLocationService,
              reverseGeocodeForTesting: fakeReverseGeocode,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify buttons are rendered
      expect(find.byKey(const ValueKey('btnCurrentLocation')), findsOneWidget);
      expect(find.byKey(const ValueKey('btnPinOnMap')), findsOneWidget);

      // Tap Current GPS button
      await tester.tap(find.byKey(const ValueKey('btnCurrentLocation')));
      await tester.pumpAndSettle();

      // Verify coordinates input is filled
      final coordField = tester.widget<TextField>(
          find.byKey(const ValueKey('inputCoordinates')));
      expect(coordField.controller?.text, '14.586200, 121.061800');

      // Verify reverse-geocoded address fields are populated
      final streetField = tester
          .widget<TextField>(find.byKey(const ValueKey('inputStreet')));
      expect(streetField.controller?.text, 'Ortigas Ave');

      final barangayField = tester
          .widget<TextField>(find.byKey(const ValueKey('inputBarangay')));
      expect(barangayField.controller?.text, 'San Antonio');

      final cityField =
          tester.widget<TextField>(find.byKey(const ValueKey('inputCity')));
      expect(cityField.controller?.text, 'Pasig');
    });

    testWidgets('renders validation error when saving without valid coordinates',
        (tester) async {
      final loc = LcpNapDto(
        id: 2,
        lcp: 'LCP 02',
        nap: 'NAP 01',
        lcpNap: 'LCP 02 - NAP 01',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LcpNapLocationPickerSheet(
              location: loc,
              signals: signals,
              tileProvider: _OfflineTileProvider(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Save button without entering coordinates
      await tester.tap(find.byKey(const ValueKey('btnSaveLocation')));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Please enter or pick valid GPS coordinates (e.g. 14.586200, 121.061800).'),
        findsOneWidget,
      );
    });
  });

  group('LcpNapMapPickerScreen Widget Tests', () {
    testWidgets(
        'renders map pin picker with confirmation card and confirm button',
        (tester) async {
      final loc = LcpNapDto(
        id: 5,
        lcp: 'LCP 03',
        nap: 'NAP 05',
        lcpNap: 'LCP 03 - NAP 05',
        coordinates: '14.586200, 121.061800',
      );

      LatLng? confirmedPoint;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  confirmedPoint = await Navigator.of(context).push<LatLng>(
                    MaterialPageRoute(
                      builder: (_) => LcpNapMapPickerScreen(
                        location: loc,
                        initialLatLng: const LatLng(14.586200, 121.061800),
                        tileProvider: _OfflineTileProvider(),
                      ),
                    ),
                  );
                },
                child: const Text('Open Map Picker'),
              ),
            ),
          ),
        ),
      );

      // Open Map Picker
      await tester.tap(find.text('Open Map Picker'));
      await tester.pumpAndSettle();

      expect(find.text('Pin Location on Map'), findsOneWidget);
      expect(find.text('LCP 03 - NAP 05'), findsOneWidget);
      expect(find.byKey(const ValueKey('btnConfirmPinLocation')), findsOneWidget);

      // Tap confirm button
      await tester.tap(find.byKey(const ValueKey('btnConfirmPinLocation')));
      await tester.pumpAndSettle();

      expect(confirmedPoint, isNotNull);
      expect(confirmedPoint!.latitude, closeTo(14.586200, 0.0001));
      expect(confirmedPoint!.longitude, closeTo(121.061800, 0.0001));
    });
  });

  group('LcpNapDetailScreen Location Mapping UI Tests', () {
    late AppDatabase db;
    late LcpNapLocationsDao dao;
    late LcpNapSignals signals;
    late LcpNapRepository repo;

    setUp(() {
      db = AppDatabase.forTesting();
      dao = LcpNapLocationsDao(db);
      repo = LcpNapRepository(dao);
      signals = LcpNapSignals(repo);
    });

    tearDown(() async {
      await signals.dispose();
      await db.close();
    });

    testWidgets(
        'renders Map This Site button when site is unmapped and opens picker sheet',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final unmappedLoc = LcpNapDto(
        id: 99,
        lcp: 'LCP 99',
        nap: 'NAP 01',
        lcpNap: 'LCP 99 - NAP 01',
      );
      await tester.runAsync(() async {
        await dao.insertOrUpdateLocation(unmappedLoc);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LcpNapDetailScreen(
            locationId: 99,
            signals: signals,
            tileProvider: _OfflineTileProvider(),
            initialImagesForTesting: const LcpNapImagesDto(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Should display 'No GPS fix recorded'
      expect(find.text('No GPS fix recorded'), findsOneWidget);

      // Should render Map This Site (Set GPS) button
      final mapButton = find.byKey(const ValueKey('btnMapUnmappedSite'));
      expect(mapButton, findsOneWidget);

      // Tap button to open location mapping sheet
      await tester.tap(mapButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Map LCP NAP Location'), findsOneWidget);
      expect(find.byKey(const ValueKey('btnCurrentLocation')), findsOneWidget);
      expect(find.byKey(const ValueKey('btnPinOnMap')), findsOneWidget);
    });

    testWidgets(
        'renders Update GPS Coordinates button when site is already mapped',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mappedLoc = LcpNapDto(
        id: 77,
        lcp: 'LCP 77',
        nap: 'NAP 02',
        lcpNap: 'LCP 77 - NAP 02',
        coordinates: '14.586200, 121.061800',
      );
      await tester.runAsync(() async {
        await dao.insertOrUpdateLocation(mappedLoc);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LcpNapDetailScreen(
            locationId: 77,
            signals: signals,
            tileProvider: _OfflineTileProvider(),
            initialImagesForTesting: const LcpNapImagesDto(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('14.586200, 121.061800'), findsWidgets);
      expect(
          find.byKey(const ValueKey('btnUpdateSiteCoordinates')), findsOneWidget);
      expect(find.byKey(const ValueKey('btnHeaderMapLocation')), findsOneWidget);
    });
  });
}
