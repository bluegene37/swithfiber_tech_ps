// Gene - Nov, 25, 2026: Unit, API wire-contract, and widget tests for Service Order remote images, multipart upload, and structured Repair Report.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/network/api_client.dart';
import 'package:swithfiber_tech_ps/core/services/draft_storage_service.dart';
import 'package:swithfiber_tech_ps/core/services/photo_storage_service.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_images_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/service_orders/services/service_orders_api.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/widgets/service_order_site_photos_card.dart';

class _RecordingServiceOrdersApi extends ServiceOrdersApi {
  final List<String> calls = [];
  Map<String, dynamic>? mockImagesResponse;
  final Map<int, Map<String, dynamic>> updatedPayloads = {};

  @override
  Future<List<ServiceOrderDto>> fetchServiceOrders() async => [];

  @override
  Future<ServiceOrderDto?> fetchServiceOrderById(int id) async => null;

  @override
  Future<Map<String, dynamic>?> fetchServiceOrderImages(int id) async {
    calls.add('fetchServiceOrderImages($id)');
    return mockImagesResponse;
  }

  @override
  Future<bool> updateServiceOrder(int id, Map<String, dynamic> payload) async {
    calls.add('updateServiceOrder($id)');
    updatedPayloads[id] = payload;
    return true;
  }
}

class _CapturingHttpAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;
  String? capturedBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    if (requestStream != null) {
      final chunks = <int>[];
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
      capturedBody = utf8.decode(chunks, allowMalformed: true);
    } else {
      capturedBody = null;
    }
    return ResponseBody.fromString('{"ok":true}', 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

  ServiceOrderDto makeOrder({
    int id = 501,
    String? routerModel = 'Huawei 5v5',
    String? image1,
    String? image2,
    String? image3,
    String? houseFrontPicture,
    String? clientSignature,
    double serviceCharge = 0.0,
    bool isSynced = true,
    String? rawJson,
  }) =>
      ServiceOrderDto(
        id: id,
        accountNumber: 'ACC-2026-501',
        fullName: 'Example Subscriber',
        contactNumber: '09170000001',
        emailAddress: 'subscriber@example.com',
        address: '123 Sample Street, Barangay Uno',
        lcp: 'LCP 01',
        nap: 'NAP 004',
        port: 'PORT 002',
        vlan: '100',
        concern: 'No Connection',
        priorityLevel: 'Urgent',
        supportStatus: 'Open',
        visitStatus: 'Pending',
        routerModel: routerModel,
        image1: image1,
        image2: image2,
        image3: image3,
        houseFrontPicture: houseFrontPicture,
        clientSignature: clientSignature,
        serviceCharge: serviceCharge,
        isSynced: isSynced,
        rawJson: rawJson,
      );

  group('ServiceOrderImagesDto parsing', () {
    test('parses live *File response keys and decodes bytes / dataUrl', () {
      final dto = ServiceOrderImagesDto.fromJson({
        'clientSignatureFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/png',
          'fileDownloadName': 'sig.png',
        },
        'image1File': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'img1.jpg',
        },
        'image2File': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'img2.jpg',
        },
        'image3File': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'img3.jpg',
        },
        'houseFrontPictureFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
          'fileDownloadName': 'hf.jpg',
        },
      });

      expect(dto.hasAnyPhoto, isTrue);
      expect(dto.clientSignature?.bytes, isNotNull);
      expect(
          dto.clientSignature?.dataUrl, startsWith('data:image/png;base64,'));
      expect(dto.image1?.hasImage, isTrue);
      expect(dto.image2?.hasImage, isTrue);
      expect(dto.image3?.hasImage, isTrue);
      expect(dto.houseFrontPicture?.hasImage, isTrue);
    });

    test('handles fallback keys, null slots, and invalid base64 safely', () {
      final dto = ServiceOrderImagesDto.fromJson({
        'image1': 'data:image/jpeg;base64,$sampleBase64',
        'image2File': null,
        'image3File': {'fileContents': '%%%not-valid-base64%%%'},
      });

      expect(dto.image1?.hasImage, isTrue);
      expect(dto.image2, isNull);
      expect(dto.image3?.hasImage, isTrue);
      expect(dto.image3?.bytes, isNull);
      expect(dto.houseFrontPicture, isNull);
    });
  });

  group('ServiceOrderDto Repair Report persistence & rawJson round-trip', () {
    late AppDatabase db;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    test(
        'fromJson -> toRow -> fromRow -> toJson preserves report & rawJson fields',
        () async {
      final serverJson = {
        'id': 777,
        'accountNumber': 'ACC-777',
        'fullName': 'Sample User',
        'contactNumber': '09171112222',
        'emailAddress': 'user@example.com',
        'address': 'Lot 9 Sample Ave',
        'supportStatus': 'Open',
        'concern': 'Transfer LCP / NAP / PORT',
        'createdDate': '2026-11-20T08:00:00Z',
        'requestedBy': 'dispatch@example.com',
        'supportRemarks': 'Check splice box',
        'visitWith': 'Tech Partner',
        'visitWithOthers': 'Helper One',
        'repairCategory': 'Transfer LCP / NAP / PORT',
        'connectionRemarks': 'Rx -20.5 dBm',
        'newLCP': 'LCP 02',
        'newNAP': 'NAP 008',
        'newPORT': 'PORT 003',
        'newVLAN': '200',
        'newPLAN': 'SwitchNet - P999',
        'pulloutRouterModel': 'ZTE F670L',
        'pulloutRouterModelSN': 'OLD-SN-1',
        'pulloutCPESN': 'CPE-999',
        'serviceCharge': 250.0,
        'itemName1': 'Drop Cable (m)',
        'itemQuantity1': 30,
        'itemName2': 'Old Connector',
        'itemQuantity2': 2,
      };

      final parsed = ServiceOrderDto.fromJson(serverJson);
      expect(parsed.hasReportDetails, isTrue);
      expect(parsed.visitWith, 'Tech Partner');
      expect(parsed.pulloutCPESN, 'CPE-999');

      // Remove Old Connector in local edit
      final edited = parsed.copyWith(
        materialsUsed: const {'Drop Cable (m)': 45},
        visitStatus: 'Done',
      );
      await db.serviceOrdersDao.insertOrUpdateOrder(edited, synced: false);

      final loaded = await db.serviceOrdersDao.getOrderById(777);
      expect(loaded, isNotNull);
      expect(loaded!.visitWith, 'Tech Partner');
      expect(loaded.visitWithOthers, 'Helper One');
      expect(loaded.repairCategory, 'Transfer LCP / NAP / PORT');
      expect(loaded.connectionRemarks, 'Rx -20.5 dBm');
      expect(loaded.newPLAN, 'SwitchNet - P999');
      expect(loaded.pulloutCPESN, 'CPE-999');
      expect(loaded.serviceCharge, 250.0);

      final outJson = loaded.toJson();
      expect(outJson['requestedBy'], 'dispatch@example.com');
      expect(outJson['supportRemarks'], 'Check splice box');
      expect(outJson['itemName1'], 'Drop Cable (m)');
      expect(outJson['itemQuantity1'], 45);
      // Removed slot 2 must be cleared rather than replayed from rawJson.
      expect(outJson['itemName2'], isNull);
      expect(outJson['itemQuantity2'], isNull);
    });
  });

  group('ServiceOrdersSignals image cache & ServiceOrdersApi wire contract',
      () {
    late AppDatabase db;
    late _RecordingServiceOrdersApi api;
    late ServiceOrdersSignals signals;
    late Directory tempDir;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      db = AppDatabase.forTesting();
      api = _RecordingServiceOrdersApi();
      signals = ServiceOrdersSignals(api: api, dao: db.serviceOrdersDao);
      tempDir = Directory.systemTemp.createTempSync('so_images_test_');
      PhotoStorageService.instance.setDirectoryForTesting(tempDir);
    });

    tearDown(() async {
      signals.dispose();
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
        'getServiceOrderImages caches and invalidates on forceRefresh & submitCompletion',
        () async {
      api.mockImagesResponse = {
        'image1File': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
        },
      };

      final first = await signals.getServiceOrderImages(501);
      expect(first?.image1?.hasImage, isTrue);
      expect(api.calls, ['fetchServiceOrderImages(501)']);

      api.calls.clear();
      await signals.getServiceOrderImages(501);
      expect(api.calls, isEmpty);

      await signals.getServiceOrderImages(501, forceRefresh: true);
      expect(api.calls, ['fetchServiceOrderImages(501)']);

      await signals.submitCompletion(makeOrder(id: 501));
      api.calls.clear();
      await signals.getServiceOrderImages(501);
      expect(api.calls, ['fetchServiceOrderImages(501)']);
    });

    test(
        'ServiceOrdersApi.updateServiceOrder sends PascalCase queryParameters and multipart IFormFile parts',
        () async {
      final originalAdapter = ApiClient.instance.dio.httpClientAdapter;
      final originalBlock = ApiClient.blockNetworkForTesting;
      final adapter = _CapturingHttpAdapter();
      FlutterSecureStorage.setMockInitialValues({'jwt_token': 'test-token'});
      ApiClient.instance.dio.httpClientAdapter = adapter;
      ApiClient.blockNetworkForTesting = false;

      try {
        final realApi = ServiceOrdersApi(ApiClient.instance);
        final ok = await realApi.updateServiceOrder(501, {
          'id': 501,
          'accountNumber': 'ACC-501',
          'visitStatus': 'Done',
          'repairCategory': 'Resplice',
          'visitWith': 'Tech Partner',
          'serviceCharge': 150.0,
          'image1': 'data:image/jpeg;base64,$sampleBase64',
          'image2': '', // explicit removal
          'image3': 'server_existing_img3.jpg', // untouched server ref
          'clientSignature': 'data:image/png;base64,$sampleBase64',
        });

        expect(ok, isTrue);
        final req = adapter.lastOptions!;
        expect(req.path, '/ServiceOrders/501');
        expect(req.queryParameters['AccountNumber'], 'ACC-501');
        expect(req.queryParameters['VisitStatus'], 'Done');
        expect(req.queryParameters['RepairCategory'], 'Resplice');
        expect(req.queryParameters['VisitWith'], 'Tech Partner');
        expect(req.queryParameters['ServiceCharge'], '150.0');
        // Never leak base64 images into queryParameters
        expect(req.queryParameters.containsKey('Image1'), isFalse);
        expect(req.queryParameters.containsKey('ClientSignature'), isFalse);

        final form = req.data as FormData;
        expect(
          form.files.any(
              (f) => f.key == 'Image1' && f.value.filename == 'image1.jpg'),
          isTrue,
        );
        expect(
          form.files.any((f) =>
              f.key == 'ClientSignature' &&
              f.value.filename == 'clientsignature.png'),
          isTrue,
        );
        expect(
          form.files.any(
              (f) => f.key == 'Image2' && (f.value.filename ?? '').isEmpty),
          isTrue,
        );
        expect(form.files.any((f) => f.key == 'Image3'), isFalse);
      } finally {
        ApiClient.instance.dio.httpClientAdapter = originalAdapter;
        ApiClient.blockNetworkForTesting = originalBlock;
      }
    });
  });

  group('ServiceOrderSitePhotosCard & ServiceOrderDetailScreen Widget Tests',
      () {
    late ServiceOrdersSignals signals;
    late _RecordingServiceOrdersApi api;
    late Directory tempDir;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      DraftStorageService.instance.resetForTesting();
      tempDir = Directory.systemTemp.createTempSync('so_widget_test_');
      PhotoStorageService.instance.setDirectoryForTesting(tempDir);
      api = _RecordingServiceOrdersApi();
      signals = ServiceOrdersSignals(api: api);
    });

    tearDown(() {
      DraftStorageService.instance.resetForTesting();
      signals.dispose();
      PhotoStorageService.instance.setDirectoryForTesting(null);
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
        'ServiceOrderSitePhotosCard renders 5 proof slots and clears stale local photo when synced',
        (tester) async {
      final order = makeOrder(
        id: 801,
        image1: 'data:image/jpeg;base64,$sampleBase64',
        isSynced: true,
      );
      api.mockImagesResponse = {
        'houseFrontPictureFile': {
          'fileContents': sampleBase64,
          'contentType': 'image/jpeg',
        },
        'image1File': null,
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServiceOrderSitePhotosCard(
                order: order,
                signals: signals,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Site Photo Proofs'), findsOneWidget);
      expect(find.text('1 / 5'), findsOneWidget);
      expect(find.text('House Front'), findsOneWidget);
      expect(find.text('Modem Setup'), findsOneWidget);
      expect(find.text('Drop / NAP'), findsOneWidget);
      expect(find.text('Repair Proof'), findsOneWidget);
      expect(find.text('Signature'), findsOneWidget);
    });

    testWidgets(
        'ServiceOrderDetailScreen renders 4 distinct photo slots and Repair Report fields without overflow at 1.0x and 2.0x',
        (tester) async {
      for (final scale in [1.0, 2.0]) {
        final overflows = <String>[];
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          final msg = details.toString();
          if (msg.contains('overflowed')) overflows.add(msg);
        };

        try {
          signals.allOrders.value = [makeOrder(id: 901, serviceCharge: 100.0)];
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = const Size(402, 915);
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: ServiceOrderDetailScreen(
                  key: ValueKey('detail_$scale'),
                  orderId: 901,
                  signals: signals,
                ),
              ),
            ),
          );
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump(const Duration(milliseconds: 200));

          final scroller = find.byType(Scrollable).first;

          // Verify Repair Report card exists
          final reportCard =
              find.byKey(const ValueKey('service_order_repair_report_card'));
          await tester.scrollUntilVisible(reportCard, 300,
              scrollable: scroller);
          expect(reportCard, findsOneWidget);
          expect(find.byKey(const ValueKey('service_order_visit_status_done')),
              findsOneWidget);
          expect(
              find.byKey(const ValueKey('service_order_repair_category_field')),
              findsOneWidget);

          // Verify 4 distinct photo capture tiles
          final photosGrid =
              find.byKey(const ValueKey('service_order_photos_grid'));
          await tester.scrollUntilVisible(photosGrid, 300,
              scrollable: scroller);
          await tester.pump();
          expect(find.byKey(const ValueKey('service_order_photo_tile_1')),
              findsOneWidget);
          expect(find.byKey(const ValueKey('service_order_photo_tile_2')),
              findsOneWidget);
          expect(find.byKey(const ValueKey('service_order_photo_tile_3')),
              findsOneWidget);
          expect(
              find.byKey(
                  const ValueKey('service_order_photo_tile_house_front')),
              findsOneWidget);
        } finally {
          FlutterError.onError = originalOnError;
        }
        tester.takeException();
        expect(overflows, isEmpty,
            reason: 'Overflow at textScale=$scale:\n${overflows.join('\n')}');
      }
    });

    testWidgets(
        'submitting ServiceOrderDetailScreen persists Repair Report fields, 4 independent photos, and copies report summary',
        (tester) async {
      final order = makeOrder(
        id: 902,
        serviceCharge: 200.0,
        rawJson: jsonEncode({
          'id': 902,
          'accountNumber': 'ACC-2026-501',
          'createdDate': '2026-11-24T10:00:00Z',
          'requestedBy': 'ops@example.com',
        }),
      );
      signals.allOrders.value = [order];

      String? copiedClipboard;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedClipboard = (call.arguments as Map?)?['text']?.toString();
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(402, 915);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ServiceOrderDetailScreen(
            orderId: 902,
            signals: signals,
            pickImage: (_) async => 'data:image/jpeg;base64,$sampleBase64',
          ),
        ),
      );
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 200));

      // Copy summary from AppBar
      await tester
          .tap(find.byKey(const ValueKey('service_order_share_report_button')));
      await tester.pump();
      expect(copiedClipboard, contains('SO-0902'));
      await tester.pump(const Duration(seconds: 5));

      final scroller = find.byType(Scrollable).first;
      Future<void> scrollIntoCenter(Finder finder) async {
        await tester.scrollUntilVisible(finder, 250, scrollable: scroller);
        await Scrollable.ensureVisible(
          tester.element(finder),
          alignment: 0.5,
          duration: Duration.zero,
        );
        await tester.pump();
      }

      // Switch visit status to In Progress and back to Done, edit remarks & charge
      final inProgChip =
          find.byKey(const ValueKey('service_order_visit_status_in_progress'));
      await scrollIntoCenter(inProgChip);
      await tester.tap(inProgChip);
      await tester.pump();
      expect(find.text('Save repair report'), findsOneWidget);

      final doneChip =
          find.byKey(const ValueKey('service_order_visit_status_done'));
      await scrollIntoCenter(doneChip);
      await tester.tap(doneChip);
      await tester.pump();
      expect(find.text('Complete service order'), findsOneWidget);

      final chargeField =
          find.byKey(const ValueKey('service_order_service_charge_field'));
      await scrollIntoCenter(chargeField);
      await tester.enterText(chargeField, '350');

      final connField =
          find.byKey(const ValueKey('service_order_connection_remarks_field'));
      await scrollIntoCenter(connField);
      await tester.enterText(connField, 'Rx -18.9 dBm');

      // Capture Repair Proof (photo 3) and House Front separately
      final tile3 = find.byKey(const ValueKey('service_order_photo_tile_3'));
      await scrollIntoCenter(tile3);
      await tester.tap(tile3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('Take photo with GPS'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Submit
      await tester.tap(find.text('Complete service order'));
      for (var i = 0; i < 40 && !api.updatedPayloads.containsKey(902); i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 350));

      expect(api.updatedPayloads.containsKey(902), isTrue,
          reason: 'syncError=${signals.syncError.value}');
      final sent = api.updatedPayloads[902]!;
      expect(sent['visitStatus'], 'Done');
      expect(sent['supportStatus'], 'Resolved');
      expect(sent['serviceCharge'], 350.0);
      expect(sent['connectionRemarks'], 'Rx -18.9 dBm');
      expect(sent['requestedBy'], 'ops@example.com');
      expect(sent['image3'], startsWith('data:image/jpeg;base64,'));
      expect(sent['houseFrontPicture'], isNull);
    });
  });
}
