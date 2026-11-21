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
// Gene - Nov, 12, 2026: Imported CabinetNapsScreen, LcpNapListScreen, and LcpNapMapView to test bottom floating add buttons and searchable cabinet picker.
import 'package:swithfiber_tech_ps/features/lcp_nap/screens/cabinet_naps_screen.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/screens/lcp_nap_list_screen.dart';
// Gene - Nov, 11, 2026: Imported MapTiles to test high-zoom tile configuration on the map pin picker.
import 'package:swithfiber_tech_ps/features/lcp_nap/services/map_tiles.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/widgets/lcp_nap_location_picker_sheet.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/widgets/lcp_nap_map_view.dart';

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

  /*
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    captured.add(options);
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }
  */
  // Gene - Nov, 21, 2026: Return empty 204 for GetReadingImage binary fallback so photoSyncRevision refreshes do not decode '{}' as invalid image bytes.
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    captured.add(options);
    if (options.path.contains('GetReadingImage')) {
      return ResponseBody.fromBytes(const <int>[], 204);
    }
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
      final coordField = tester
          .widget<TextField>(find.byKey(const ValueKey('inputCoordinates')));
      expect(coordField.controller?.text, '14.586200, 121.061800');

      // Verify reverse-geocoded address fields are populated
      final streetField =
          tester.widget<TextField>(find.byKey(const ValueKey('inputStreet')));
      expect(streetField.controller?.text, 'Ortigas Ave');

      final barangayField =
          tester.widget<TextField>(find.byKey(const ValueKey('inputBarangay')));
      expect(barangayField.controller?.text, 'San Antonio');

      final cityField =
          tester.widget<TextField>(find.byKey(const ValueKey('inputCity')));
      expect(cityField.controller?.text, 'Pasig');
    });

    testWidgets(
        'renders validation error when saving without valid coordinates',
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
      expect(
          find.byKey(const ValueKey('btnConfirmPinLocation')), findsOneWidget);
      // Gene - Nov, 11, 2026: Verify zoom in/out controls and high-resolution maxZoom/maxNativeZoom settings on LcpNapMapPickerScreen.
      expect(find.byKey(const ValueKey('btnPickerZoomIn')), findsOneWidget);
      expect(find.byKey(const ValueKey('btnPickerZoomOut')), findsOneWidget);

      final tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(tileLayer.maxZoom, MapTiles.streetMaxZoom);
      expect(tileLayer.maxNativeZoom, MapTiles.streetMaxNativeZoom);
      expect(MapTiles.streetMaxZoom, 22);
      expect(MapTiles.streetMaxNativeZoom, 21);

      // Tap zoom in button several times up to maxZoom
      await tester.tap(find.byKey(const ValueKey('btnPickerZoomIn')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('btnPickerZoomOut')));
      await tester.pump();

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
      expect(find.byKey(const ValueKey('btnUpdateSiteCoordinates')),
          findsOneWidget);
      /*
      expect(
          find.byKey(const ValueKey('btnHeaderMapLocation')), findsOneWidget);
      */
      // Gene - Nov, 12, 2026: Verify unified Location & GPS card with MAPPED stamp and Navigate CTA (duplicate header button removed).
      expect(find.text('Location & GPS'), findsOneWidget);
      expect(find.text('MAPPED'), findsOneWidget);
      expect(find.byKey(const ValueKey('btnNavigateSite')), findsOneWidget);
      // Gene - Nov, 11, 2026: Verify Edit Site Details button is rendered in AppBar.
      expect(find.byKey(const ValueKey('btnEditSiteDetails')), findsOneWidget);
    });

    // Gene - Nov, 11, 2026: Verify creating a new LCP NAP location via LcpNapLocationPickerSheet.create and editing details.
    testWidgets(
        'LcpNapLocationPickerSheet.create creates a new LCP NAP location and updates capacity/details',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      LcpNapDto? createdCallbackDto;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LcpNapLocationPickerSheet.create(
              signals: signals,
              initialLcp: 'LCP 009 - ANG',
              initialNap: 'NAP 004',
              initialPortTotal: 16,
              initialCity: 'Angono',
              initialRegion: 'Rizal',
              tileProvider: _OfflineTileProvider(),
              onCreated: (dto) => createdCallbackDto = dto,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create LCP NAP Location'), findsWidgets);
      expect(find.byKey(const ValueKey('inputLcp')), findsOneWidget);
      expect(find.byKey(const ValueKey('inputNap')), findsOneWidget);
      expect(find.byKey(const ValueKey('inputLcpNap')), findsOneWidget);
      expect(find.byKey(const ValueKey('inputPortTotal')), findsOneWidget);

      // Select 24 Ports chip
      await tester.tap(find.byKey(const ValueKey('chipPort_24')));
      await tester.pumpAndSettle();

      final portField = tester
          .widget<TextField>(find.byKey(const ValueKey('inputPortTotal')));
      expect(portField.controller?.text, '24');

      // Enter street and coordinates
      await tester.enterText(
          find.byKey(const ValueKey('inputStreet')), 'M.L. Quezon Ave');
      await tester.enterText(find.byKey(const ValueKey('inputCoordinates')),
          '14.526200, 121.153800');
      await tester.pumpAndSettle();

      // Save / Create
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('btnSaveLocation')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(createdCallbackDto, isNotNull);
      expect(createdCallbackDto!.lcp, 'LCP 009 - ANG');
      expect(createdCallbackDto!.nap, 'NAP 004');
      expect(createdCallbackDto!.lcpNap, 'LCP 009 - ANG NAP 004');
      expect(createdCallbackDto!.portTotal, 24);
      expect(createdCallbackDto!.coordinates, '14.526200, 121.153800');
      expect(createdCallbackDto!.street, 'M.L. Quezon Ave');
      expect(createdCallbackDto!.city, 'Angono');
    });

    // Gene - Nov, 12, 2026: Verify searchable LcpCabinetPickerSheet filters cabinets and updates inputLcp.
    testWidgets(
        'btnPickExistingLcp opens searchable cabinet sheet and populates LCP field',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.runAsync(() async {
        await dao.insertOrUpdateLocation(LcpNapDto(
          id: 1,
          lcp: 'CAR LCP 001',
          nap: 'NAP 001',
          lcpNap: 'CAR LCP 001 NAP 001',
        ));
        await dao.insertOrUpdateLocation(LcpNapDto(
          id: 2,
          lcp: 'BIN LCP 042',
          nap: 'NAP 001',
          lcpNap: 'BIN LCP 042 NAP 001',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LcpNapLocationPickerSheet.create(
              signals: signals,
              tileProvider: _OfflineTileProvider(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('btnPickExistingLcp')));
      await tester.pumpAndSettle();

      expect(find.text('Select LCP Cabinet'), findsOneWidget);
      expect(find.text('CAR LCP 001'), findsOneWidget);
      expect(find.text('BIN LCP 042'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('inputSearchCabinetPicker')),
          matching: find.byType(TextField),
        ),
        'BIN',
      );
      await tester.pumpAndSettle();

      expect(find.text('CAR LCP 001'), findsNothing);
      expect(find.text('BIN LCP 042'), findsOneWidget);

      await tester.tap(find.text('BIN LCP 042'));
      await tester.pumpAndSettle();

      final lcpField =
          tester.widget<TextField>(find.byKey(const ValueKey('inputLcp')));
      expect(lcpField.controller?.text, 'BIN LCP 042');
    });

    // Gene - Nov, 12, 2026: Verify bottom floating Add pills on LcpNapListScreen, CabinetNapsScreen, and LcpNapMapView (including pin popup auto-hide).
    testWidgets(
        'renders floating bottom Add pills on List, Cabinet NAPs, and Map view (hiding when pin popup opens)',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final loc = LcpNapDto(
        id: 501,
        lcp: 'TAY LCP 005',
        nap: 'NAP 001',
        lcpNap: 'TAY LCP 005 NAP 001',
        coordinates: '14.558200, 121.132800',
        city: 'Taytay',
      );
      await tester.runAsync(() async {
        await dao.insertOrUpdateLocation(loc);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      // 1. LcpNapListScreen floating bottom-right pill
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LcpNapListScreen(signals: signals),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final listAddBtn = find.byKey(const ValueKey('btnCreateLcpNap'));
      expect(listAddBtn, findsOneWidget);
      expect(find.text('Add LCP NAP'), findsOneWidget);
      expect(tester.getCenter(listAddBtn).dy, greaterThan(700));

      // 2. CabinetNapsScreen floating bottom-right pill
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: CabinetNapsScreen(
            cabinet: 'TAY LCP 005',
            signals: signals,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final cabAddBtn = find.byKey(const ValueKey('btnAddCabinetNap'));
      expect(cabAddBtn, findsOneWidget);
      expect(find.text('Add NAP'), findsOneWidget);
      expect(tester.getCenter(cabAddBtn).dy, greaterThan(700));

      // 3. LcpNapMapView bottom-left pill visible when selected == null, hidden when pin popup opens
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LcpNapMapView(
              signals: signals,
              onOpenDetails: (_) {},
              onCreateSite: () {},
              tileProvider: _OfflineTileProvider(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final mapAddBtn = find.byKey(const ValueKey('btnCreateLcpNapMap'));
      expect(mapAddBtn, findsOneWidget);

      // Tap pin -> pin popup opens and floating add button auto-hides
      await tester.tap(find.byKey(const ValueKey('lcpNapPin_501')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('btnCreateLcpNapMap')), findsNothing);
    });

    // Gene - Nov, 21, 2026: Verify mini preview map camera moves on auto-locate and opens interactive map picker on tap.
    testWidgets(
        'LcpNapLocationPickerSheet auto-locate moves mini preview map camera and tap opens LcpNapMapPickerScreen without overlap',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final loc = LcpNapDto(
        id: 201,
        lcp: 'LCP 20',
        nap: 'NAP 01',
        lcpNap: 'LCP 20 - NAP 01',
        coordinates: '14.500000, 121.100000',
      );
      final fakeLocationService =
          _FakeLocationService(fakePosition: samplePosition);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LcpNapLocationPickerSheet(
              location: loc,
              signals: signals,
              tileProvider: _OfflineTileProvider(),
              locationService: fakeLocationService,
              reverseGeocodeForTesting: (_, __) async => const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(initialMap.mapController!.camera.center.latitude,
          closeTo(14.500000, 0.0001));
      expect(initialMap.mapController!.camera.center.longitude,
          closeTo(121.100000, 0.0001));

      // Auto-locate via Current GPS button: field, marker, and preview camera must all move.
      await tester.tap(find.byKey(const ValueKey('btnCurrentLocation')));
      await tester.pumpAndSettle();

      final coordField = tester
          .widget<TextField>(find.byKey(const ValueKey('inputCoordinates')));
      expect(coordField.controller?.text, '14.586200, 121.061800');

      final updatedMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(updatedMap.mapController!.camera.center.latitude,
          closeTo(14.586200, 0.0001));
      expect(updatedMap.mapController!.camera.center.longitude,
          closeTo(121.061800, 0.0001));

      // Clear and reset, then enter another coordinate and tap the mini preview map to open the full picker.
      await tester.enterText(
        find.byKey(const ValueKey('inputCoordinates')),
        '14.500000, 121.100000',
      );
      await tester.pumpAndSettle();

      await tester
          .ensureVisible(find.byKey(const ValueKey('btnPreviewMapOpenPicker')));
      await tester.tap(find.byKey(const ValueKey('btnPreviewMapOpenPicker')));
      await tester.pumpAndSettle();

      expect(find.text('Pin Location on Map'), findsOneWidget);

      // Verify auto-locate FAB sits strictly above the confirmation Card (no overlap).
      final fabRect =
          tester.getRect(find.byKey(const ValueKey('fabCenterGps')));
      final cardRect = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const ValueKey('btnConfirmPinLocation')),
              matching: find.byType(Card),
            )
            .first,
      );
      expect(fabRect.bottom, lessThanOrEqualTo(cardRect.top));

      // Tap auto-locate FAB inside LcpNapMapPickerScreen: pin, user GPS marker, and map camera all move.
      await tester.tap(find.byKey(const ValueKey('fabCenterGps')));
      await tester.pumpAndSettle();

      final pickerMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(pickerMap.mapController!.camera.center.latitude,
          closeTo(14.586200, 0.0001));
      expect(pickerMap.mapController!.camera.center.longitude,
          closeTo(121.061800, 0.0001));
      expect(find.byKey(const Key('pickerUserGpsMarker')), findsOneWidget);
      expect(find.text('14.586200, 121.061800'), findsOneWidget);

      // Confirm and verify sheet updates both coordinates and preview map camera.
      await tester.tap(find.byKey(const ValueKey('btnConfirmPinLocation')));
      await tester.pumpAndSettle();

      expect(coordField.controller?.text, '14.586200, 121.061800');
      final returnedMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(returnedMap.mapController!.camera.center.latitude,
          closeTo(14.586200, 0.0001));
      expect(returnedMap.mapController!.camera.center.longitude,
          closeTo(121.061800, 0.0001));
    });

    // Gene - Nov, 21, 2026: Verify tapping LcpNapDetailScreen mini-map opens interactive map with pin & auto-locate and saves coordinates.
    testWidgets(
        'tapping LcpNapDetailScreen mini-map opens LcpNapMapPickerScreen, auto-locates, and saves updated coordinates',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      FlutterSecureStorage.setMockInitialValues({});
      final adapter = _RecordingAdapter();
      final dio = ApiClient.instance.dio;
      final originalAdapter = dio.httpClientAdapter;
      ApiClient.blockNetworkForTesting = false;
      dio.httpClientAdapter = adapter;
      addTearDown(() {
        ApiClient.blockNetworkForTesting = true;
        dio.httpClientAdapter = originalAdapter;
      });

      final mappedLoc = LcpNapDto(
        id: 202,
        lcp: 'LCP 21',
        nap: 'NAP 02',
        lcpNap: 'LCP 21 - NAP 02',
        coordinates: '14.500000, 121.100000',
      );
      await tester.runAsync(() async {
        await dao.insertOrUpdateLocation(mappedLoc);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      final fakeLocationService =
          _FakeLocationService(fakePosition: samplePosition);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LcpNapDetailScreen(
            locationId: 202,
            signals: signals,
            tileProvider: _OfflineTileProvider(),
            initialImagesForTesting: const LcpNapImagesDto(),
            locationServiceForTesting: fakeLocationService,
            reverseGeocodeForTesting: (_, __) async => [
              const geo.Placemark(
                street: 'Meralco Ave',
                subLocality: 'Ugong',
                locality: 'Pasig',
                administrativeArea: 'NCR',
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
          find.byKey(const ValueKey('btnDetailMapOpenFull')), findsOneWidget);
      await tester
          .ensureVisible(find.byKey(const ValueKey('detailMiniMapTapArea')));
      await tester.tap(find.byKey(const ValueKey('detailMiniMapTapArea')));
      await tester.pumpAndSettle();

      expect(find.text('Pin Location on Map'), findsOneWidget);
      expect(find.text('Save Pin Location'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('fabCenterGps')));
      await tester.pumpAndSettle();

      final pickerMap = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(pickerMap.mapController!.camera.center.latitude,
          closeTo(14.586200, 0.0001));
      expect(pickerMap.mapController!.camera.center.longitude,
          closeTo(121.061800, 0.0001));

      await tester.tap(find.byKey(const ValueKey('btnConfirmPinLocation')));
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        final current =
            signals.allLocations.value.where((l) => l.id == 202).firstOrNull;
        if (current?.coordinates == '14.586200, 121.061800') break;
      }
      await tester.pumpAndSettle();

      expect(
        adapter.captured
            .any((r) => r.method == 'PUT' && r.path == '/LCPNapLocations/202'),
        isTrue,
      );
      expect(
        signals.allLocations.value.firstWhere((l) => l.id == 202).coordinates,
        '14.586200, 121.061800',
        reason: 'signals.allLocations must update after confirm save',
      );
      expect(find.text('14.586200, 121.061800'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('minimap_202_14.586200, 121.061800')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    // Gene - Nov, 21, 2026: Verify LcpNapMapView My Location button acquires GPS, draws user dot, and moves map camera.
    testWidgets(
        'LcpNapMapView My Location button locates technician and moves map camera',
        (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final loc = LcpNapDto(
        id: 203,
        lcp: 'LCP 22',
        nap: 'NAP 01',
        lcpNap: 'LCP 22 - NAP 01',
        coordinates: '14.500000, 121.100000',
      );
      await tester.runAsync(() async {
        await dao.insertOrUpdateLocation(loc);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      final fakeLocationService =
          _FakeLocationService(fakePosition: samplePosition);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LcpNapMapView(
              signals: signals,
              tileProvider: _OfflineTileProvider(),
              locationService: fakeLocationService,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final myLocationBtn =
          find.byKey(const ValueKey('btnLcpNapMapMyLocation'));
      expect(myLocationBtn, findsOneWidget);

      await tester.tap(myLocationBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lcpNapUserLocationPin')), findsOneWidget);
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.mapController!.camera.center.latitude,
          closeTo(14.586200, 0.0001));
      expect(map.mapController!.camera.center.longitude,
          closeTo(121.061800, 0.0001));
    });
  });
}
