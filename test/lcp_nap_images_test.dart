// Gene - Oct 24, 2026: Comprehensive unit and widget tests for LCP NAP Site Enclosure and Optical Power Reading photos.
// Gene - Oct 29, 2026: Added unit and widget tests for LCP NAP photo upload and update flows.
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// import 'package:image_picker/image_picker.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/database/daos/lcp_nap_dao.dart';
import 'package:swithfiber_tech_ps/core/network/api_client.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/models/lcp_nap_images_model.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/models/lcp_nap_model.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/screens/lcp_nap_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';
// Gene - Nov, 12, 2026: Imported LcpNapPhotoSlotCard to verify standalone per-slot upload cards.
import 'package:swithfiber_tech_ps/features/lcp_nap/widgets/lcp_nap_photo_slot_card.dart';

// Gene - Oct 29, 2026: Recording adapter to intercept and verify multipart photo upload payloads.
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

// Gene - Nov, 12, 2026: Stateful HTTP adapter for widget upload/delete flows so GET /GetLCPNAPLocationImages and /GetReadingImage reflect PUT changes cleanly.
class _StatefulPhotosAdapter implements HttpClientAdapter {
  final Map<String, dynamic> imagesState;

  _StatefulPhotosAdapter({Map<String, dynamic>? initial})
      : imagesState = Map<String, dynamic>.from(initial ?? const {});

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = options.path;
    if (options.method.toUpperCase() == 'PUT' && options.data is FormData) {
      final formData = options.data as FormData;
      for (final entry in formData.files) {
        final slot = entry.key == 'Image'
            ? 'image'
            : (entry.key == 'Image2' ? 'image2' : 'readingImage');
        if (entry.value.length == 0) {
          imagesState[slot] = null;
        } else {
          final bytes = await entry.value
              .clone()
              .finalize()
              .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
          imagesState[slot] = {
            'fileContents': base64Encode(bytes),
            'contentType': 'image/jpeg',
            'fileDownloadName': entry.value.filename ?? '$slot.jpg',
          };
        }
      }
      return ResponseBody.fromString('{}', 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    if (path.endsWith('/GetReadingImage')) {
      return ResponseBody.fromBytes(
        const <int>[],
        200,
        headers: {
          Headers.contentTypeHeader: ['image/jpeg'],
        },
      );
    }
    if (path.endsWith('/GetLCPNAPLocationImages')) {
      return ResponseBody.fromString(jsonEncode(imagesState), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 1x1 transparent pixel base64 for testing image decoding
  const sampleBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

  group('LcpNapImageFileDto Tests', () {
    test('parses from valid JSON and extracts properties', () {
      final json = {
        'fileContents': sampleBase64,
        'contentType': 'image/png',
        'fileDownloadName': 'exterior.png',
      };
      final dto = LcpNapImageFileDto.fromJson(json);

      expect(dto.fileContents, sampleBase64);
      expect(dto.contentType, 'image/png');
      expect(dto.fileDownloadName, 'exterior.png');
      expect(dto.hasImage, isTrue);

      final bytes = dto.bytes;
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(0));

      final dataUrl = dto.dataUrl;
      expect(dataUrl, startsWith('data:image/png;base64,'));

      final outJson = dto.toJson();
      expect(outJson['contentType'], 'image/png');
      expect(outJson['fileDownloadName'], 'exterior.png');
    });

    test('handles empty and null fileContents gracefully', () {
      final dtoNull = LcpNapImageFileDto.fromJson({});
      expect(dtoNull.hasImage, isFalse);
      expect(dtoNull.bytes, isNull);
      expect(dtoNull.dataUrl, isNull);

      final dtoEmpty = const LcpNapImageFileDto(fileContents: '   ');
      expect(dtoEmpty.hasImage, isFalse);
      expect(dtoEmpty.bytes, isNull);
      expect(dtoEmpty.dataUrl, isNull);
    });

    test('decodes data: URL prefix in fileContents correctly', () {
      final dataUrlStr = 'data:image/jpeg;base64,$sampleBase64';
      final dto = LcpNapImageFileDto(
        fileContents: dataUrlStr,
        contentType: 'image/jpeg',
      );

      expect(dto.hasImage, isTrue);
      expect(dto.dataUrl, dataUrlStr);
      final bytes = dto.bytes;
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(0));
    });
  });

  group('LcpNapImagesDto Tests', () {
    test('parses payload with all three site photos', () {
      final json = {
        'image': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'exterior.jpg',
        },
        'image2': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'interior.jpg',
        },
        'readingImage': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'reading.jpg',
        },
      };

      final dto = LcpNapImagesDto.fromJson(json);
      expect(dto.hasAnyPhoto, isTrue);
      expect(dto.image?.hasImage, isTrue);
      expect(dto.image2?.hasImage, isTrue);
      expect(dto.readingImage?.hasImage, isTrue);

      final outJson = dto.toJson();
      expect(outJson.containsKey('image'), isTrue);
      expect(outJson.containsKey('image2'), isTrue);
      expect(outJson.containsKey('readingImage'), isTrue);
    });

    test('handles snake_case reading_image and null entries', () {
      final json = {
        'image': null,
        'image2': null,
        'reading_image': {
          'fileContents': sampleBase64,
          'contentType': 'image/png',
        },
      };

      final dto = LcpNapImagesDto.fromJson(json);
      expect(dto.hasAnyPhoto, isTrue);
      expect(dto.image, isNull);
      expect(dto.image2, isNull);
      expect(dto.readingImage?.hasImage, isTrue);
    });

    test('reports hasAnyPhoto false when all photos are empty or null', () {
      final dto = LcpNapImagesDto.fromJson({});
      expect(dto.hasAnyPhoto, isFalse);
      expect(dto.image, isNull);
      expect(dto.image2, isNull);
      expect(dto.readingImage, isNull);
    });

    // Gene - Oct 31, 2026: Test that LcpNapImagesDto parses raw Base64 string fields properly.
    test('parses raw Base64 strings for image, image2, and readingImage', () {
      final json = {
        'image': sampleBase64,
        'image2': sampleBase64,
        'readingImage': sampleBase64,
      };
      final dto = LcpNapImagesDto.fromJson(json);
      expect(dto.hasAnyPhoto, isTrue);
      expect(dto.image?.hasImage, isTrue);
      expect(dto.image2?.hasImage, isTrue);
      expect(dto.readingImage?.hasImage, isTrue);
    });
  });

  // Gene - Oct 31, 2026: Unit tests for LcpNapDto image fields parsing ASP.NET IFormFile map metadata and base64.
  group('LcpNapDto Image Fields Parsing Tests', () {
    test(
        'ignores IFormFile map metadata without fileContents and preserves null',
        () {
      final json = {
        'id': 1503,
        'lcp': 'CAR LCP 001',
        'nap': 'NAP 001',
        'image': {
          'contentType': 'image/jpeg',
          'contentDisposition': '',
          'headers': {
            'Content-Type': ['image/jpeg']
          },
          'length': 22399,
          'name': 'CAR LCP 001 NAP 001-Image..jpg',
          'fileName': 'CAR LCP 001 NAP 001-Image..jpg',
        },
        'image2': null,
        'readingImage': null,
      };
      final dto = LcpNapDto.fromJson(json);
      expect(dto.image, isNull);
      expect(dto.image2, isNull);
      expect(dto.readingImage, isNull);
    });

    test('parses FileContentResult map with fileContents into data URL', () {
      final json = {
        'id': 1503,
        'lcp': 'CAR LCP 001',
        'nap': 'NAP 001',
        'readingImage': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'reading.jpg',
        },
      };
      final dto = LcpNapDto.fromJson(json);
      expect(dto.readingImage, startsWith('data:image/jpeg;base64,'));
    });
  });

  group('LcpNapRepository Cache Tests', () {
    test('clearing cache resets in-memory map without error', () {
      final db = AppDatabase.forTesting();
      final repository = LcpNapRepository(LcpNapLocationsDao(db));

      expect(() => repository.clearImagesCache(), returnsNormally);
      db.close();
    });
  });

  group('LcpNapDetailScreen Site Photos Widget Tests', () {
    late AppDatabase db;
    late LcpNapRepository repository;
    late LcpNapSignals signals;

    setUp(() async {
      db = AppDatabase.forTesting();
      repository = LcpNapRepository(LcpNapLocationsDao(db));
      signals = LcpNapSignals(repository);

      // Seed a location record
      await repository.seedSampleLocations();
      await Future.delayed(const Duration(milliseconds: 50));
    });

    tearDown(() async {
      await signals.dispose();
      await db.close();
    });

    testWidgets('renders Site Enclosure & Reading Photos with 3 photos badge',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final samplePhoto = LcpNapImageFileDto(
        fileContents: sampleBase64,
        contentType: 'image/png',
        fileDownloadName: 'sample.png',
      );
      final testImages = LcpNapImagesDto(
        image: samplePhoto,
        image2: samplePhoto,
        readingImage: samplePhoto,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LcpNapDetailScreen(
            locationId: 1,
            signals: signals,
            initialImagesForTesting: testImages,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify title and badge
      expect(find.text('Site Enclosure & Reading Photos'), findsOneWidget);
      /*
      expect(find.text('3 photos'), findsOneWidget);
      */
      // Gene - Nov, 12, 2026: Verify '3 of 3 photos' badge and 3 standalone LcpNapPhotoSlotCards.
      expect(find.text('3 of 3 photos'), findsOneWidget);
      expect(find.byType(LcpNapPhotoSlotCard), findsNWidgets(3));
      expect(find.text('CAPTURED'), findsNWidgets(3));

      // Verify all photo labels are rendered
      expect(find.text('Enclosure Exterior'), findsOneWidget);
      expect(find.text('NAP Box Enclosure 1'), findsOneWidget);
      expect(find.text('Enclosure Interior'), findsOneWidget);
      expect(find.text('NAP Splicing Tray / Ports'), findsOneWidget);
      expect(find.text('Optical Power Reading'), findsOneWidget);
      expect(find.text('OPM Power Capture'), findsOneWidget);

      // Verify Pinch / Zoom hint indicators exist
      expect(find.text('Pinch / Zoom'), findsNWidgets(3));
    });

    testWidgets('renders empty placeholder when no photos are uploaded',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const emptyImages = LcpNapImagesDto();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LcpNapDetailScreen(
            locationId: 1,
            signals: signals,
            initialImagesForTesting: emptyImages,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Site Enclosure & Reading Photos'), findsOneWidget);
      /*
      expect(find.text('No enclosure or optical reading photos uploaded yet.'),
          findsOneWidget);
      expect(find.text('3 photos'), findsNothing);
      */
      // Gene - Nov, 12, 2026: Verify 3 separate empty LcpNapPhotoSlotCards are rendered when 0 photos exist.
      expect(find.text('0 of 3 photos'), findsOneWidget);
      expect(find.byKey(const ValueKey('photoSlotCard_enc1')), findsOneWidget);
      expect(find.byKey(const ValueKey('photoSlotCard_enc2')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('photoSlotCard_reading')), findsOneWidget);
      expect(find.text('EMPTY'), findsNWidgets(3));
      expect(find.byKey(const ValueKey('btnTakePhoto_enc1')), findsOneWidget);
      expect(find.byKey(const ValueKey('btnTakePhoto_enc2')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('btnTakePhoto_reading')), findsOneWidget);
    });

    testWidgets('renders properly in dark mode without RenderFlex overflow',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final samplePhoto = LcpNapImageFileDto(
        fileContents: sampleBase64,
        contentType: 'image/png',
        fileDownloadName: 'sample.png',
      );
      final testImages = LcpNapImagesDto(
        image: samplePhoto,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: LcpNapDetailScreen(
            locationId: 1,
            signals: signals,
            initialImagesForTesting: testImages,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Site Enclosure & Reading Photos'), findsOneWidget);
      /*
      expect(find.text('1 photos'), findsOneWidget);
      */
      // Gene - Nov, 12, 2026: Verify '1 of 3 photos' badge with 1 CAPTURED card and 2 separate EMPTY cards on scroll.
      expect(find.text('1 of 3 photos'), findsOneWidget);
      expect(find.text('Enclosure Exterior'), findsOneWidget);
      expect(find.text('CAPTURED'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Optical Power Reading'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Optical Power Reading'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // Gene - Oct 29, 2026: Added tests for Upload Site Photos button and bottom sheet modal interaction.
    testWidgets(
        'renders Upload Site Photos button when empty and opens upload sheet',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const emptyImages = LcpNapImagesDto();

      /*
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LcpNapDetailScreen(
            locationId: 1,
            signals: signals,
            initialImagesForTesting: emptyImages,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Upload Site Photos'), findsOneWidget);

      // Tap Upload Site Photos button
      await tester.tap(find.text('Upload Site Photos'));
      // Gene - Oct 29, 2026: Use discrete pumps to prevent timeout from infinite map progress spinner animations.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify the modal sheet opens with title and 3 photo slots
      expect(find.text('Upload Site Photos'),
          findsNWidgets(2)); // Card button + Sheet title
      expect(find.text('Enclosure Exterior'), findsOneWidget);
      expect(find.text('Enclosure Interior'), findsOneWidget);
      expect(find.text('Optical Power Reading'), findsOneWidget);
      expect(find.text('Save & Upload Photos'), findsOneWidget);
      */
      // Gene - Nov, 12, 2026: Verify 1-tap inline Take Photo button on empty Enclosure Exterior card captures & uploads onto that single slot while keeping the other 2 cards empty.
      FlutterSecureStorage.setMockInitialValues({});
      final prevAdapter = ApiClient.instance.dio.httpClientAdapter;
      ApiClient.blockNetworkForTesting = false;
      ApiClient.instance.dio.httpClientAdapter = _StatefulPhotosAdapter();
      addTearDown(() {
        ApiClient.blockNetworkForTesting = true;
        ApiClient.instance.dio.httpClientAdapter = prevAdapter;
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LcpNapDetailScreen(
            locationId: 1,
            signals: signals,
            initialImagesForTesting: emptyImages,
            pickImageForTesting: (_) async =>
                'data:image/png;base64,$sampleBase64',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('0 of 3 photos'), findsOneWidget);
      expect(find.byKey(const ValueKey('btnTakePhoto_enc1')), findsOneWidget);

      await tester
          .ensureVisible(find.byKey(const ValueKey('btnTakePhoto_enc1')));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('btnTakePhoto_enc1')));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('1 of 3 photos'), findsOneWidget);
      expect(find.text('CAPTURED'), findsOneWidget);
      expect(find.text('EMPTY'), findsNWidgets(2));
    });

    // Gene - Oct 29, 2026: Added test for Update button in header when photos are present.
    testWidgets('renders Update button in header when photos are present',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final samplePhoto = LcpNapImageFileDto(
        fileContents: sampleBase64,
        contentType: 'image/png',
        fileDownloadName: 'sample.png',
      );
      final testImages = LcpNapImagesDto(
        image: samplePhoto,
      );

      /*
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LcpNapDetailScreen(
            locationId: 1,
            signals: signals,
            initialImagesForTesting: testImages,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Update'), findsOneWidget);

      // Tap Update button
      await tester.tap(find.text('Update'));
      // Gene - Oct 29, 2026: Use discrete pumps to prevent timeout from infinite map progress spinner animations.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify sheet opens
      expect(find.text('Save & Upload Photos'), findsOneWidget);
      */
      // Gene - Nov, 12, 2026: Verify filled card exposes 48dp Retake / Gallery / Delete strip and deleting returns that card to EMPTY while keeping all 3 standalone cards visible.
      FlutterSecureStorage.setMockInitialValues({});
      final prevAdapter = ApiClient.instance.dio.httpClientAdapter;
      ApiClient.blockNetworkForTesting = false;
      final adapter = _StatefulPhotosAdapter(
        initial: {
          'image': samplePhoto.toJson(),
          'image2': null,
          'readingImage': null,
        },
      );
      ApiClient.instance.dio.httpClientAdapter = adapter;
      addTearDown(() {
        ApiClient.blockNetworkForTesting = true;
        ApiClient.instance.dio.httpClientAdapter = prevAdapter;
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LcpNapDetailScreen(
            locationId: 1,
            signals: signals,
            initialImagesForTesting: testImages,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('btnRetakePhoto_enc1')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('btnReplaceGallery_enc1')), findsOneWidget);
      expect(find.byKey(const ValueKey('btnDeletePhoto_enc1')), findsOneWidget);

      await tester
          .ensureVisible(find.byKey(const ValueKey('btnDeletePhoto_enc1')));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('btnDeletePhoto_enc1')));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Delete Enclosure Exterior?'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('0 of 3 photos'), findsOneWidget);
      expect(find.text('EMPTY'), findsNWidgets(3));
    });

    // Gene - Nov, 12, 2026: Verify LcpNapDetailScreen with 3 photo cards has zero layout overflow at 200% text scale on a 402dp phone viewport.
    testWidgets(
        'renders 3 photo cards and Port Matrix at 200% text scale on 402dp phone without overflow',
        (tester) async {
      tester.view.devicePixelRatio = 2.625;
      tester.view.physicalSize = const Size(402 * 2.625, 874 * 2.625);
      addTearDown(tester.view.reset);

      final errors = <String>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d.toString());
      addTearDown(() => FlutterError.onError = originalOnError);

      final samplePhoto = LcpNapImageFileDto(
        fileContents: sampleBase64,
        contentType: 'image/png',
        fileDownloadName: 'sample.png',
      );
      final mixedImages = LcpNapImagesDto(image: samplePhoto);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: LcpNapDetailScreen(
              locationId: 1,
              signals: signals,
              initialImagesForTesting: mixedImages,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.scrollUntilVisible(
        find.text('Port Matrix & Capacity'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      FlutterError.onError = originalOnError;
      tester.takeException();
      final overflows = errors.where((e) => e.contains('overflowed')).toList();
      expect(overflows, isEmpty, reason: overflows.join('\n'));
    });

    // Gene - Nov, 8, 2026: Regression test verifying LCP NAP full-screen photo viewer opens and closes cleanly.
    testWidgets(
        'tapping an LCP NAP photo opens full-screen viewer and close button dismisses it',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final samplePhoto = LcpNapImageFileDto(
        fileContents: sampleBase64,
        contentType: 'image/png',
        fileDownloadName: 'sample.png',
      );
      final testImages = LcpNapImagesDto(
        image: samplePhoto,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: LcpNapDetailScreen(
            locationId: 1,
            signals: signals,
            initialImagesForTesting: testImages,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Tap the photo card to open full-screen viewer
      await tester.tap(find.text('Pinch / Zoom'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(InteractiveViewer), findsOneWidget);
      final closeBtn = find.byKey(const ValueKey('photo_viewer_close_button'));
      expect(closeBtn, findsOneWidget);

      await tester.tap(closeBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.text('Site Enclosure & Reading Photos'), findsOneWidget);
    });
  });

  // Gene - Oct 29, 2026: Unit tests for LCP NAP photo upload multipart request formatting.
  group('LcpNapRepository Upload Photos Tests', () {
    late _RecordingAdapter adapter;
    late AppDatabase db;
    late LcpNapRepository repository;
    late LcpNapSignals signals;

    setUp(() {
      // Gene - Oct 29, 2026: Provide mock secure storage store for ApiClient auth token lookup during tests.
      FlutterSecureStorage.setMockInitialValues({});
      adapter = _RecordingAdapter();
      final dio = ApiClient.instance.dio;
      ApiClient.blockNetworkForTesting = false;
      final original = dio.httpClientAdapter;
      dio.httpClientAdapter = adapter;

      db = AppDatabase.forTesting();
      repository = LcpNapRepository(LcpNapLocationsDao(db));
      signals = LcpNapSignals(repository);

      addTearDown(() {
        ApiClient.blockNetworkForTesting = true;
        dio.httpClientAdapter = original;
        signals.dispose();
        db.close();
      });
    });

    test(
        'uploadLcpNapPhotos constructs multipart PUT request with fields and files',
        () async {
      final loc = LcpNapDto(
        id: 42,
        lcp: 'LCP 01',
        nap: 'NAP 02',
        lcpNap: 'LCP 01 - NAP 02',
        portTotal: 16,
        coordinates: '14.5862, 121.0618',
        street: 'Main Street',
        barangay: 'San Antonio',
        city: 'Pasig',
        region: 'Rizal',
      );

      final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

      final success = await repository.uploadLcpNapPhotos(
        locationId: 42,
        location: loc,
        imageBytes: dummyBytes,
        image2Bytes: dummyBytes,
        readingImageBytes: dummyBytes,
      );

      expect(success, isTrue);
      expect(adapter.captured.length, 1);

      final req = adapter.captured.single;
      expect(req.method, 'PUT');
      expect(req.path, '/LCPNapLocations/42');
      expect(req.data, isA<FormData>());

      final formData = req.data as FormData;
      final fields = Map.fromEntries(formData.fields);
      expect(fields['LCP'], 'LCP 01');
      expect(fields['NAP'], 'NAP 02');
      expect(fields['LCPNAP'], 'LCP 01 - NAP 02');
      expect(fields['PortTotal'], '16');
      expect(fields['Coordinates'], '14.5862, 121.0618');
      expect(fields['Street'], 'Main Street');
      expect(fields['Barangay'], 'San Antonio');
      expect(fields['City'], 'Pasig');
      expect(fields['Region'], 'Rizal');

      final files = Map.fromEntries(formData.files);
      expect(files.containsKey('Image'), isTrue);
      expect(files.containsKey('Image2'), isTrue);
      expect(files.containsKey('ReadingImage'), isTrue);
    });

    // Gene - Oct 31, 2026: Test that clearing an image sends an empty file per backend API specification.
    test('uploadLcpNapPhotos with clearImage sends empty image file to delete',
        () async {
      final loc = LcpNapDto(
        id: 55,
        lcp: 'CAR LCP 001',
        nap: 'NAP 001',
        lcpNap: 'CAR LCP 001 NAP 001',
      );

      final success = await repository.uploadLcpNapPhotos(
        locationId: 55,
        location: loc,
        clearImage: true,
      );

      expect(success, isTrue);
      expect(adapter.captured.length, 1);

      final req = adapter.captured.single;
      final formData = req.data as FormData;
      final files = Map.fromEntries(formData.files);
      expect(files.containsKey('Image'), isTrue);
      expect(files['Image']?.length, 0);
    });

    test('uploadLocationPhotos on signals delegates to repository', () async {
      final loc = LcpNapDto(
        id: 10,
        lcp: 'LCP 10',
        nap: 'NAP 01',
        lcpNap: 'LCP 10 - NAP 01',
      );

      final success = await signals.uploadLocationPhotos(
        locationId: 10,
        location: loc,
      );

      expect(success, isTrue);
      expect(adapter.captured.length, 1);
      final req = adapter.captured.single;
      expect(req.method, 'PUT');
      expect(req.path, '/LCPNapLocations/10');
    });

    // Gene - Nov, 8, 2026: Verify deleting one image preserves sibling photo and clears local SQLite column.
    test(
        'uploadLcpNapPhotos with clearImage clears local SQLite column and preserves sibling photos',
        () async {
      final dataUrl = 'data:image/png;base64,$sampleBase64';
      final loc = LcpNapDto(
        id: 77,
        lcp: 'CAR LCP 077',
        nap: 'NAP 007',
        lcpNap: 'CAR LCP 077 NAP 007',
        image: dataUrl,
        image2: dataUrl,
      );
      await LcpNapLocationsDao(db).insertOrUpdateLocation(loc);

      final success = await repository.uploadLcpNapPhotos(
        locationId: 77,
        location: loc,
        clearImage: true,
      );

      expect(success, isTrue);
      final req = adapter.captured.single;
      final formData = req.data as FormData;
      final files = Map.fromEntries(formData.files);
      expect(files['Image']?.length, 0,
          reason: 'Deleted slot must send 0-byte file');
      expect(files['Image2']?.length, greaterThan(0),
          reason: 'Sibling photo from SQLite must be preserved');

      final updatedRow =
          await LcpNapLocationsDao(db).watchLocationById(77).first;
      expect(updatedRow, isNotNull);
      expect(updatedRow!.image, isNull,
          reason: 'Deleted image must be cleared in local SQLite');
      expect(updatedRow.image2, isNotNull,
          reason: 'Sibling image2 must remain in local SQLite');
    });
  });
}
