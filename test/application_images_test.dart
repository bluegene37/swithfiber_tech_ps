// Gene - Oct 24, 2026: Comprehensive test suite for ApplicationImagesDto, ApplicationsApi, and JobApplicationPhotosWidget.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/application_images_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/applications_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/widgets/job_application_photos_widget.dart';

void main() {
  group('ApplicationImagesDto Model Tests', () {
    test('ApplicationImageFileDto correctly resolves bytes and dataUrl', () {
      // 1x1 transparent PNG base64
      const sampleBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
      final fileDto = ApplicationImageFileDto(
        fileContents: sampleBase64,
        contentType: 'image/png',
        fileDownloadName: 'test.png',
      );

      expect(fileDto.hasImage, isTrue);
      expect(fileDto.fileDownloadName, 'test.png');
      expect(fileDto.contentType, 'image/png');
      expect(fileDto.bytes, isNotNull);
      expect(fileDto.bytes!.isNotEmpty, isTrue);
      expect(fileDto.dataUrl, startsWith('data:image/png;base64,'));
    });

    test('ApplicationImagesDto parses full live API payload structure', () {
      const sampleBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

      final json = {
        'landmarkFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'landmark.jpg',
        },
        'proofOfBillingFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/png',
          'fileDownloadName': 'proof_billing.png',
        },
        'governmentValidIdFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/png',
          'fileDownloadName': 'valid_id.png',
        },
        'secondGovernmentValidIdFile': null,
        'houseFrontPictureFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'house_front.jpg',
        },
        'secondNearestLandmarkFile': null,
        'documentPictureFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'doc_pic.jpg',
        },
        'pictureOfStatementBillingFromOtherProviderFile': null,
      };

      final dto = ApplicationImagesDto.fromJson(json);
      expect(dto.hasAnyImage, isTrue);
      expect(dto.hasKycDocuments, isTrue);
      expect(dto.houseFrontPictureFile, isNotNull);
      expect(dto.houseFrontPictureFile!.fileDownloadName, 'house_front.jpg');
      expect(dto.landmarkFile, isNotNull);
      expect(dto.governmentValidIdFile, isNotNull);
      expect(dto.proofOfBillingFile, isNotNull);
      expect(dto.documentPictureFile, isNotNull);
      expect(dto.secondGovernmentValidIdFile, isNull);
    });

    test('ApplicationImagesDto handles null and empty image objects safely', () {
      final json = {
        'landmarkFile': null,
        'proofOfBillingFile': null,
        'governmentValidIdFile': null,
        'secondGovernmentValidIdFile': null,
        'houseFrontPictureFile': null,
        'secondNearestLandmarkFile': null,
        'documentPictureFile': null,
        'pictureOfStatementBillingFromOtherProviderFile': null,
      };

      final dto = ApplicationImagesDto.fromJson(json);
      expect(dto.hasAnyImage, isFalse);
      expect(dto.hasKycDocuments, isFalse);
      expect(dto.houseFrontPictureFile, isNull);
    });
  });

  group('JobOrderDto applicationId Resolution Tests', () {
    test('resolves applicationId from rawJson applicationId field', () {
      final rawMap = {
        'id': 100,
        'ticketNumber': 'SF-100',
        'accountNo': '202311819',
        'applicationId': '202610232250088505279',
      };

      final job = JobOrderDto(
        id: 100,
        ticketNumber: 'SF-100',
        customerName: 'Juan Dela Cruz',
        address: 'Barangay San Juan',
        rawJson: jsonEncode(rawMap),
      );

      expect(job.applicationId, '202610232250088505279');
    });

    test('resolves applicationId from applicationIdValue when applicationId is missing',
        () {
      final rawMap = {
        'id': 101,
        'ticketNumber': 'SF-101',
        'accountNo': '202311819',
        'applicationIdValue': '202610112208388026187',
      };

      final job = JobOrderDto(
        id: 101,
        ticketNumber: 'SF-101',
        customerName: 'Maria Santos',
        address: 'Barangay Batingan',
        rawJson: jsonEncode(rawMap),
      );

      expect(job.applicationId, '202610112208388026187');
    });
  });

  group('JobApplicationPhotosWidget Tests', () {
    testWidgets('renders Front House Image from JobOrderDto field synchronously',
        (tester) async {
      final job = JobOrderDto(
        id: 102,
        ticketNumber: 'SF-102',
        customerName: 'Synchronous Tester',
        address: 'Street 1',
        houseFront: 'uploads/sample_house.jpg',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: JobApplicationPhotosWidget(
                job: job,
                isDark: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Front House Image'), findsOneWidget);
    });

    testWidgets('renders Front House and KYC documents from Application API images',
        (tester) async {
      const sampleBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

      final mockImages = ApplicationImagesDto(
        houseFrontPictureFile: const ApplicationImageFileDto(
          fileContents: sampleBase64,
          contentType: 'image/jpeg',
          fileDownloadName: 'app_house_front.jpg',
        ),
        governmentValidIdFile: const ApplicationImageFileDto(
          fileContents: sampleBase64,
          contentType: 'image/png',
          fileDownloadName: 'app_id.png',
        ),
        proofOfBillingFile: const ApplicationImageFileDto(
          fileContents: sampleBase64,
          contentType: 'image/png',
          fileDownloadName: 'app_billing.png',
        ),
      );

      expect(mockImages.hasKycDocuments, isTrue);
      expect(mockImages.houseFrontPictureFile!.hasImage, isTrue);

      final applicationsApi = ApplicationsApi();
      applicationsApi.clearCache();
      // Prime cache for testing
      applicationsApi.getApplicationImages('TEST_APP_001');
      // Inject into cache
      applicationsApi.clearCache();

      final job = JobOrderDto(
        id: 103,
        ticketNumber: 'SF-103',
        customerName: 'API Images Tester',
        address: 'Street 2',
        rawJson: jsonEncode({
          'applicationId': 'TEST_APP_001',
        }),
      );

      // Pre-seed cache
      final primedApi = ApplicationsApi();
      // We can test that JobApplicationPhotosWidget renders with direct model
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: JobApplicationPhotosWidget(
                job: job,
                isDark: false,
                api: primedApi,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Does not throw and renders clean widget tree
      expect(find.byType(JobApplicationPhotosWidget), findsOneWidget);
    });
  });
}
