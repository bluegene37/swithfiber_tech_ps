// Gene - Nov 5, 2026: Comprehensive unit and widget tests for Job Order photo proofs and multipart upload.
// Gene - Nov 07, 2026: Commented out unused dart:convert and dart:typed_data imports to satisfy static analysis and pre-release verification gates.
// import 'dart:convert';
// import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_images_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/sync_worker.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/widgets/job_photo_gallery.dart';
import 'package:swithfiber_tech_ps/features/jobs/widgets/job_site_photos_card.dart';

class _RecordingJobApi implements JobOrdersApi {
  final List<String> calls = [];
  final Map<int, FormData> multipartUpdates = {};
  final Map<int, Map<String, dynamic>> jsonUpdates = {};
  Map<String, dynamic>? mockImagesResponse;

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
  Future<Map<String, dynamic>?> fetchImages(int id) async {
    calls.add('fetchImages($id)');
    return mockImagesResponse;
  }

  @override
  Future<void> update(int id, Map<String, dynamic> body) async {
    calls.add('update($id)');
    jsonUpdates[id] = body;
  }

  @override
  Future<void> updateMultipart(int id, FormData formData) async {
    calls.add('updateMultipart($id)');
    multipartUpdates[id] = formData;
  }

  // Gene - Nov, 25, 2026: Stubbed timing methods on _RecordingJobApi test double.
  @override
  Future<void> createTiming({
    required int joId,
    required String techId,
    required DateTime startTime,
    DateTime? endTime,
  }) async {
    calls.add('createTiming($joId)');
  }

  @override
  Future<void> updateTiming({
    required int joId,
    required String techId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    calls.add('updateTiming($joId)');
  }
}

JobOrderDto _createJob({
  required int id,
  required String ticketNumber,
  String status = 'Scheduled',
  String customerName = 'Juan Dela Cruz',
  String address = '123 Rizal St, Antipolo',
  String? setupImage,
  String? routerReadingImage,
  String? boxReadingImage,
  String? signedContractImage,
  String? clientSignature,
  String? houseFront,
  bool isSynced = true,
}) {
  return JobOrderDto(
    id: id,
    ticketNumber: ticketNumber,
    customerName: customerName,
    address: address,
    status: status,
    setupImage: setupImage,
    routerReadingImage: routerReadingImage,
    boxReadingImage: boxReadingImage,
    signedContractImage: signedContractImage,
    clientSignature: clientSignature,
    houseFront: houseFront,
    isSynced: isSynced,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 1x1 transparent pixel base64 for testing image decoding
  const sampleBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

  group('JobOrderImageFileDto Tests', () {
    test('parses from valid JSON and extracts properties and bytes', () {
      final json = {
        'fileContents': sampleBase64,
        'contentType': 'image/jpeg',
        'fileDownloadName': 'setup.jpg',
      };
      final dto = JobOrderImageFileDto.fromJson(json);

      expect(dto.fileContents, sampleBase64);
      expect(dto.contentType, 'image/jpeg');
      expect(dto.fileDownloadName, 'setup.jpg');
      expect(dto.hasImage, isTrue);

      final bytes = dto.bytes;
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(0));
      expect(dto.dataUrl, startsWith('data:image/jpeg;base64,'));
    });

    test('handles empty or null JSON fields cleanly', () {
      final dto = JobOrderImageFileDto.fromJson({});
      expect(dto.fileContents, isNull);
      expect(dto.hasImage, isFalse);
      expect(dto.bytes, isNull);
      expect(dto.dataUrl, isNull);
    });
  });

  group('JobOrderImagesDto Tests', () {
    test('parses complete GetJobOrderImage response payload', () {
      final json = {
        'setupImageFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'setup.jpg',
        },
        'clientSignatureFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/png',
          'fileDownloadName': 'sig.png',
        },
        'signedContractImageFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'contract.jpg',
        },
        'boxReadingImageFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'box.jpg',
        },
        'routerReadingImageFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'router.jpg',
        },
        'portLabelImageFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'port.jpg',
        },
        'houseFrontFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'house.jpg',
        },
      };

      final dto = JobOrderImagesDto.fromJson(json);

      expect(dto.hasAnyPhoto, isTrue);
      expect(dto.setupImage?.hasImage, isTrue);
      expect(dto.clientSignature?.hasImage, isTrue);
      expect(dto.signedContractImage?.hasImage, isTrue);
      expect(dto.boxReadingImage?.hasImage, isTrue);
      expect(dto.routerReadingImage?.hasImage, isTrue);
      expect(dto.portLabelImage?.hasImage, isTrue);
      expect(dto.houseFront?.hasImage, isTrue);
    });

    test('parses payload with alternative key names without File suffix', () {
      final json = {
        'setupImage': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
        },
        'houseFront': 'data:image/jpeg;base64,$sampleBase64',
      };

      final dto = JobOrderImagesDto.fromJson(json);

      expect(dto.hasAnyPhoto, isTrue);
      expect(dto.setupImage?.hasImage, isTrue);
      expect(dto.houseFront?.hasImage, isTrue);
      expect(dto.boxReadingImage, isNull);
    });
  });

  group('JobRepository Images Caching & API Tests', () {
    late AppDatabase db;
    late _RecordingJobApi api;
    late JobRepository repository;
    late JobsSignals signals;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      db = AppDatabase.forTesting();
      api = _RecordingJobApi();
      repository = JobRepository(db.jobOrdersDao, api: api);
      signals = JobsSignals(repository);
    });

    tearDown(() async {
      await signals.dispose();
      await db.close();
    });

    test('fetches images, caches them, and avoids redundant network calls',
        () async {
      api.mockImagesResponse = {
        'setupImageFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'setup.jpg',
        },
      };

      // First call fetches from API
      final res1 = await repository.getJobOrderImages(4119);
      expect(res1, isNotNull);
      expect(res1!.setupImage?.hasImage, isTrue);
      expect(api.calls, contains('fetchImages(4119)'));

      // Second call uses in-memory cache without repeating network request
      api.calls.clear();
      final res2 = await repository.getJobOrderImages(4119);
      expect(res2, isNotNull);
      expect(api.calls, isEmpty);

      // Force refresh bypasses cache
      final res3 = await repository.getJobOrderImages(4119, forceRefresh: true);
      expect(res3, isNotNull);
      expect(api.calls, contains('fetchImages(4119)'));
    });

    test('clearImagesCache invalidates cached photos', () async {
      api.mockImagesResponse = {
        'setupImageFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
        },
      };

      await repository.getJobOrderImages(4119);
      repository.clearImagesCache(4119);

      api.calls.clear();
      await repository.getJobOrderImages(4119);
      expect(api.calls, contains('fetchImages(4119)'));
    });
  });

  group('JobOrderDto Multipart Upload & SyncWorker Tests', () {
    late AppDatabase db;
    late _RecordingJobApi api;
    late SyncWorker syncWorker;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      db = AppDatabase.forTesting();
      api = _RecordingJobApi();
      syncWorker = SyncWorker(db.jobOrdersDao, api: api);
    });

    tearDown(() async {
      await db.close();
    });

    test('hasCapturedPhotos detects data URLs and local photos', () {
      final jobNoPhotos = _createJob(
        id: 1,
        ticketNumber: 'JO-001',
        status: 'Scheduled',
      );
      expect(jobNoPhotos.hasCapturedPhotos, isFalse);

      final jobWithDataUrl = _createJob(
        id: 2,
        ticketNumber: 'JO-002',
        status: 'Completed',
        setupImage: 'data:image/jpeg;base64,$sampleBase64',
      );
      expect(jobWithDataUrl.hasCapturedPhotos, isTrue);

      final jobWithSignature = _createJob(
        id: 3,
        ticketNumber: 'JO-003',
        status: 'Completed',
        clientSignature: 'data:image/png;base64,$sampleBase64',
      );
      expect(jobWithSignature.hasCapturedPhotos, isTrue);
    });

    test('toMultipartFormData packages files and scalar form fields', () async {
      final job = _createJob(
        id: 4119,
        ticketNumber: 'JO-4119',
        customerName: 'Alpha Tester',
        status: 'Completed',
        setupImage: 'data:image/jpeg;base64,$sampleBase64',
        routerReadingImage: 'data:image/jpeg;base64,$sampleBase64',
        clientSignature: 'data:image/png;base64,$sampleBase64',
        houseFront: 'data:image/jpeg;base64,$sampleBase64',
      );

      final formData = await job.toMultipartFormData();

      expect(formData.files.any((f) => f.key == 'SetupImage'), isTrue);
      expect(formData.files.any((f) => f.key == 'RouterReadingImage'), isTrue);
      expect(formData.files.any((f) => f.key == 'ClientSignature'), isTrue);
      expect(formData.files.any((f) => f.key == 'HouseFront'), isTrue);

      // Verify scalar fields are present
      expect(
          formData.fields
              .any((f) => f.key == 'status' && f.value == 'Completed'),
          isTrue);
    });

    test('SyncWorker triggers updateMultipart when job has captured photos',
        () async {
      final job = _createJob(
        id: 501,
        ticketNumber: 'JO-501',
        customerName: 'Multipart Test Subscriber',
        status: 'Completed',
        setupImage: 'data:image/jpeg;base64,$sampleBase64',
        isSynced: false,
      );

      await db.jobOrdersDao.insertOrUpdateJob(job, synced: false);

      final result = await syncWorker.syncPendingJobs();
      expect(result.success, isTrue);
      expect(api.calls, contains('updateMultipart(501)'));
      expect(api.multipartUpdates.containsKey(501), isTrue);
    });

    test('SyncWorker triggers standard update when job has no captured photos',
        () async {
      final job = _createJob(
        id: 502,
        ticketNumber: 'JO-502',
        customerName: 'Status Only Subscriber',
        status: 'Inprogress',
        isSynced: false,
      );

      await db.jobOrdersDao.insertOrUpdateJob(job, synced: false);

      final result = await syncWorker.syncPendingJobs();
      expect(result.success, isTrue);
      expect(api.calls, contains('update(502)'));
      expect(api.jsonUpdates.containsKey(502), isTrue);
    });
  });

  group('JobSitePhotosCard & JobPhotoGallery Widget Tests', () {
    late AppDatabase db;
    late _RecordingJobApi api;
    late JobRepository repository;
    late JobsSignals signals;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      db = AppDatabase.forTesting();
      api = _RecordingJobApi();
      repository = JobRepository(db.jobOrdersDao, api: api);
      signals = JobsSignals(repository);
    });

    tearDown(() async {
      await signals.dispose();
      await db.close();
    });

    testWidgets('renders Site Photo Proofs card with count and thumbnails',
        (tester) async {
      final initialImages = JobOrderImagesDto(
        setupImage: const JobOrderImageFileDto(
          fileContents: sampleBase64,
          contentType: 'image/jpeg',
          fileDownloadName: 'setup.jpg',
        ),
        routerReadingImage: const JobOrderImageFileDto(
          fileContents: sampleBase64,
          contentType: 'image/jpeg',
          fileDownloadName: 'router.jpg',
        ),
      );

      final job = _createJob(
        id: 4119,
        ticketNumber: 'JO-4119',
        status: 'Scheduled',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: JobSitePhotosCard(
                job: job,
                jobsSignals: signals,
                initialImagesForTesting: initialImages,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Site Photo Proofs'), findsOneWidget);
      expect(find.text('2 / 6'), findsOneWidget);
      expect(find.text('Set Up'), findsOneWidget);
      expect(find.text('Router Rx'), findsOneWidget);
      expect(find.text('Box Reading'), findsOneWidget);
      expect(find.text('Signature'), findsOneWidget);
    });

    testWidgets('JobPhotoGallery renders serverImages Base64 thumbnails',
        (tester) async {
      final job = _createJob(
        id: 888,
        ticketNumber: 'JO-888',
        status: 'Completed',
        clientSignature: 'placeholder_sig',
      );

      final serverImages = JobOrderImagesDto(
        clientSignature: const JobOrderImageFileDto(
          fileContents: sampleBase64,
          contentType: 'image/png',
          fileDownloadName: 'sig.png',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: JobPhotoGallery(
              job: job,
              serverImages: serverImages,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Subscriber Signature'), findsOneWidget);
    });

    // Gene - Nov, 13, 2026: Regression test ensuring JobSitePhotosCard does not fall back to stale local job columns once GetJobOrderImage confirms a photo was deleted on live.
    testWidgets(
        'JobSitePhotosCard clears deleted server photo instead of falling back to stale local column on synced job',
        (tester) async {
      api.mockImagesResponse = {
        'setupImageFile': null,
        'houseFrontFile': null,
      };

      final job = _createJob(
        id: 4120,
        ticketNumber: 'JO-4120',
        status: 'Completed',
        setupImage: 'data:image/png;base64,$sampleBase64',
        isSynced: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: JobSitePhotosCard(
                job: job,
                jobsSignals: signals,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 / 6'), findsOneWidget);
    });
  });
}
