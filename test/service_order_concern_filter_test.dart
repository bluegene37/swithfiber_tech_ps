import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/services/photo_storage_service.dart';
import 'package:swithfiber_tech_ps/core/utils/data_url.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/service_orders/services/service_orders_api.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/widgets/service_order_card.dart';

class _MockApi extends ServiceOrdersApi {
  @override
  Future<List<ServiceOrderDto>> fetchServiceOrders() async => [];

  @override
  Future<bool> updateServiceOrder(int id, Map<String, dynamic> body) async {
    return true;
  }
}

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() {
    db = AppDatabase.forTesting();
    tempDir =
        Directory.systemTemp.createTempSync('service_orders_concern_test_');
    PhotoStorageService.instance.setDirectoryForTesting(tempDir);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  const samplePullout = ServiceOrderDto(
    id: 101,
    accountNumber: 'SO-101',
    fullName: 'Alice Johnson',
    contactNumber: '09171111111',
    emailAddress: 'alice@example.com',
    address: '101 Apple St',
    concern: 'Pullout',
    priorityLevel: 'Normal',
    isSynced: true,
  );

  const sampleNoConnection = ServiceOrderDto(
    id: 102,
    accountNumber: 'SO-102',
    fullName: 'Bob Smith',
    contactNumber: '09172222222',
    emailAddress: 'bob@example.com',
    address: '102 Banana St',
    concern: 'No Connection',
    priorityLevel: 'Urgent',
    isSynced: false,
  );

  const sampleHighLoss = ServiceOrderDto(
    id: 103,
    accountNumber: 'SO-103',
    fullName: 'Charlie Davis',
    contactNumber: '09173333333',
    emailAddress: 'charlie@example.com',
    address: '103 Cherry St',
    concern: 'High Loss',
    priorityLevel: 'High',
    isSynced: true,
  );

  group('Concern Filtering in ServiceOrdersSignals', () {
    test('filters orders by concern accurately', () {
      final signals = ServiceOrdersSignals(dao: db.serviceOrdersDao);
      addTearDown(signals.dispose);

      signals.allOrders.value = [
        samplePullout,
        sampleNoConnection,
        sampleHighLoss,
      ];

      expect(signals.filteredOrders.value.length, 3);

      // Filter by Pullout
      signals.concernFilter.value = 'Pullout';
      expect(signals.filteredOrders.value.length, 1);
      expect(signals.filteredOrders.value.single.id, 101);

      // Filter by No Connection
      signals.concernFilter.value = 'No Connection';
      expect(signals.filteredOrders.value.length, 1);
      expect(signals.filteredOrders.value.single.id, 102);

      // Filter by High Loss
      signals.concernFilter.value = 'High Loss';
      expect(signals.filteredOrders.value.length, 1);
      expect(signals.filteredOrders.value.single.id, 103);

      // Combined with priority
      signals.concernFilter.value = 'All';
      signals.priorityFilter.value = 'Urgent';
      expect(signals.filteredOrders.value.length, 1);
      expect(signals.filteredOrders.value.single.id, 102);

      // Reset
      signals.priorityFilter.value = 'All';
      signals.concernFilter.value = 'All';
      expect(signals.filteredOrders.value.length, 3);
    });
  });

  group('ServiceOrderCard UI indicators', () {
    testWidgets('shows cloud_upload icon when isSynced is false',
        (tester) async {
      final signals = ServiceOrdersSignals(dao: db.serviceOrdersDao);
      addTearDown(signals.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServiceOrderCard(
              order: sampleNoConnection, // isSynced == false
              signals: signals,
            ),
          ),
        ),
      );

      expect(find.byIcon(CupertinoIcons.cloud_upload), findsOneWidget);
    });

    testWidgets('hides cloud_upload icon when isSynced is true',
        (tester) async {
      final signals = ServiceOrdersSignals(dao: db.serviceOrdersDao);
      addTearDown(signals.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ServiceOrderCard(
              order: samplePullout, // isSynced == true
              signals: signals,
            ),
          ),
        ),
      );

      expect(find.byIcon(CupertinoIcons.cloud_upload), findsNothing);
    });
  });

  group('ServiceOrderDetailScreen Pullout Remarks', () {
    testWidgets(
        'renders pullout remarks text field and persists pullout remarks',
        (tester) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(402 * 3.0, 874 * 3.0);
      addTearDown(tester.view.reset);

      final mockApi = _MockApi();
      final signals =
          ServiceOrdersSignals(api: mockApi, dao: db.serviceOrdersDao);
      addTearDown(signals.dispose);

      await tester.runAsync(() async {
        await db.serviceOrdersDao
            .insertOrUpdateOrder(samplePullout, synced: true);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: ServiceOrderDetailScreen(
            orderId: 101,
            signals: signals,
          ),
        ),
      );
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      // Pullout remarks field exists
      final remarksFinder = find.byKey(const ValueKey('pullout_remarks_field'));
      expect(remarksFinder, findsOneWidget);

      // Enter remarks
      await tester.enterText(
          remarksFinder, 'Recovered ONU SN HWTC123 with 12V adapter.');
      await tester.pump();

      // Complete service order
      final completeButton = find.text('Complete service order');
      expect(completeButton, findsOneWidget);
      await tester.tap(completeButton);
      await tester.pumpAndSettle();

      // Check SQLite order was updated with pulloutRemarks
      // The tap's write and this read both run on PowerSync's isolate, on
      // real time, so wait outside the fake-async zone and give the write a
      // moment to commit before reading it back.
      final updatedInDb = await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return db.serviceOrdersDao.getOrderById(101);
      });
      expect(updatedInDb, isNotNull);
      expect(updatedInDb!.pulloutRemarks,
          'Recovered ONU SN HWTC123 with 12V adapter.');
      expect(updatedInDb.visitStatus, 'Done');
    });

    test(
        'submitCompletion offloads and saves houseFrontPicture to the local database',
        () async {
      final mockApi = _MockApi();
      final signals =
          ServiceOrdersSignals(api: mockApi, dao: db.serviceOrdersDao);
      addTearDown(signals.dispose);

      final dummyPngBytes =
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final houseFrontDataUrl =
          DataUrl.encode(dummyPngBytes, mimeType: 'image/png');

      final updated = samplePullout.copyWith(
        houseFrontPicture: houseFrontDataUrl,
        visitStatus: 'Done',
      );

      final success = await signals.submitCompletion(updated);
      expect(success, isTrue);

      final saved = await db.serviceOrdersDao.getOrderById(101);
      expect(saved, isNotNull);
      expect(saved!.houseFrontPicture, isNotNull);
      expect(saved.houseFrontPicture, contains('house_front'));
      expect(File(saved.houseFrontPicture!).existsSync(), isTrue);
    });
  });
}
