// Gene - Oct 24, 2026: Comprehensive unit and widget tests for LCP NAP Site Enclosure and Optical Power Reading photos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/database/daos/lcp_nap_dao.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/models/lcp_nap_images_model.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/screens/lcp_nap_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';

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
      expect(find.text('3 photos'), findsOneWidget);

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
      expect(
          find.text('No enclosure or optical reading photos uploaded yet.'),
          findsOneWidget);
      expect(find.text('3 photos'), findsNothing);
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
      expect(find.text('1 photos'), findsOneWidget);
      expect(find.text('Enclosure Exterior'), findsOneWidget);
    });
  });
}
