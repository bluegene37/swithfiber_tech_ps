import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/core/utils/data_url.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/reports/screens/create_report_screen.dart';
import 'package:swithfiber_tech_ps/features/reports/signals/report_signals.dart';

class _QuietApi implements JobOrdersApi {
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

void main() {
  group('Job Order Materials Tracking & Serialization', () {
    test('JobOrderDto parses and serializes materials to API format', () {
      final json = {
        'id': 123,
        'ticketNumber': 'JO-123',
        'firstName': 'John',
        'lastName': 'Doe',
        'address': '789 Fiber St',
        'itemName1': 'Drop Cable (m)',
        'itemQuantity1': '45',
        'itemName2': 'SC/APC Fast Connector',
        'itemQuantity2': 2,
        'itemName3': 'S-Clamp',
        'itemQuantity3': 1,
      };

      final dto = JobOrderDto.fromJson(json);
      expect(dto.materialsUsed['Drop Cable (m)'], 45);
      expect(dto.materialsUsed['SC/APC Fast Connector'], 2);
      expect(dto.materialsUsed['S-Clamp'], 1);

      final apiJson = dto.toApiJson();
      expect(apiJson['itemName1'], 'Drop Cable (m)');
      expect(apiJson['itemQuantity1'], '45');
      expect(apiJson['itemName2'], 'SC/APC Fast Connector');
      expect(apiJson['itemQuantity2'], '2');
      expect(apiJson['itemName3'], 'S-Clamp');
      expect(apiJson['itemQuantity3'], '1');
      expect(apiJson['itemName4'], '');
      expect(apiJson['itemQuantity4'], '');
    });

    test(
        'JobOrdersDao persists materialsUsed in rawJson and fromRow restores it',
        () async {
      final db = AppDatabase.forTesting();
      final dao = db.jobOrdersDao;

      final initialJob = JobOrderDto(
        id: 501,
        ticketNumber: 'JO-501',
        customerName: 'Maria Santos',
        address: 'Blk 5 Lot 10',
        status: 'Scheduled',
      );

      await dao.insertOrUpdateJob(initialJob);

      await dao.updateJobCompletion(
        id: 501,
        onsiteStatus: 'Done',
        onsiteRemarks: 'Installed ONT and ran 35m drop cable',
        modemRouterSN: 'HWTC12345678',
        materialsUsed: {
          'Drop Cable (m)': 35,
          'SC/APC Fast Connector': 2,
          'S-Clamp': 3,
        },
      );

      final updatedRow = await dao.getJobById(501);
      expect(updatedRow, isNotNull);

      final restoredDto = updatedRow!;
      expect(restoredDto.materialsUsed['Drop Cable (m)'], 35);
      expect(restoredDto.materialsUsed['SC/APC Fast Connector'], 2);
      expect(restoredDto.materialsUsed['S-Clamp'], 3);

      final decodedRaw = jsonDecode(updatedRow.rawJson!);
      expect(decodedRaw['itemName1'], 'Drop Cable (m)');
      expect(decodedRaw['itemQuantity1'], 35);

      await db.close();
    });
  });

  group('Job Order Materials UI Integration', () {
    testWidgets(
        'CreateReportScreen modifies materials counters and submits with report',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late AppDatabase db;
      late JobsSignals jobsSignals;
      late ReportSignals reportSignals;

      final testJob = JobOrderDto(
        id: 701,
        ticketNumber: 'JO-701',
        customerName: 'Carlos Garcia',
        address: 'Corner St',
        status: 'Scheduled',
        modemRouterSN: '',
        clientSignature: DataUrl.encode(Uint8List.fromList([1, 2, 3, 4])),
      );

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        jobsSignals =
            JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
        await db.jobOrdersDao.insertOrUpdateJob(testJob);
      });

      reportSignals = ReportSignals()..setJobOrder(testJob);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: CreateReportScreen(
          jobsSignals: jobsSignals,
          reportSignals: reportSignals,
          pickImage: (_) async => null,
          scanBarcode: (_) async => 'SCANNED-SN-999',
        ),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Materials Consumed On-Site'), findsOneWidget);

      /*
      final plusDrop = find.byKey(const ValueKey('counter_plus_drop_cable'));
      final plusFast =
          find.byKey(const ValueKey('counter_plus_fast_connectors'));
      final plusClamp = find.byKey(const ValueKey('counter_plus_s_clamps'));

      await tester.ensureVisible(plusDrop);
      await tester.tap(plusDrop);
      await tester.pump();
      await tester.tap(plusDrop);
      await tester.pump();

      await tester.ensureVisible(plusFast);
      await tester.tap(plusFast);
      await tester.pump();

      await tester.ensureVisible(plusClamp);
      await tester.tap(plusClamp);
      await tester.pump();
      */
      // Gene - Oct 13, 2026: Dynamically select and add materials using searchable picker and Add Material button.
      Future<void> addMaterial(String name, [String? qty]) async {
        final picker = find.byKey(const ValueKey('material_select_field'));
        await tester.scrollUntilVisible(picker, 300,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();

        /*
        if (qty != null) {
          final qtyField = find.byKey(const ValueKey('material_add_qty_field'));
          await tester.enterText(qtyField, qty);
          await tester.pump();
        }

        final addBtn = find.byKey(const ValueKey('add_material_button'));
        await tester.tap(addBtn);
        await tester.pumpAndSettle();
        */
        // Gene - Oct 13, 2026: Added materials default to 1; tap Add Material then increment quantity via counter buttons.
        final addBtn = find.byKey(const ValueKey('add_material_button'));
        await tester.tap(addBtn);
        await tester.pumpAndSettle();

        if (qty != null && qty != '1') {
          String slug = 'drop_cable';
          if (name.contains('Fast Connector')) slug = 'fast_connectors';
          if (name.contains('S-Clamp')) slug = 's_clamps';
          final plusBtn = find.byKey(ValueKey('counter_plus_$slug'));
          await tester.tap(plusBtn);
          await tester.pump();
        }
      }

      await addMaterial('Drop Cable (m)', '2');
      await addMaterial('SC/APC Fast Connector', '1');
      await addMaterial('S-Clamp', '1');

      expect(reportSignals.materialsUsed.value['Drop Cable (m)'], 2);
      expect(reportSignals.materialsUsed.value['SC/APC Fast Connector'], 1);
      expect(reportSignals.materialsUsed.value['S-Clamp'], 1);

      reportSignals.routerSerial.value = 'SN-VERIFIED';

      await tester.runAsync(() async {
        final success =
            await reportSignals.submitReport(jobsSignals.repository);
        expect(success, isTrue);

        final saved = await db.jobOrdersDao.getJobById(701);
        final savedDto = saved!;
        expect(savedDto.materialsUsed['Drop Cable (m)'], 2);
        expect(savedDto.materialsUsed['SC/APC Fast Connector'], 1);
        expect(savedDto.materialsUsed['S-Clamp'], 1);

        await Future<void>.delayed(const Duration(milliseconds: 300));
        await jobsSignals.dispose();
        await db.close();
      });
      await tester.pumpAndSettle();
    });

    testWidgets(
        'JobOrderDetailScreen renders Materials Used card when materials are present',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late AppDatabase db;
      late JobsSignals jobsSignals;

      final jobWithMaterials = JobOrderDto(
        id: 801,
        ticketNumber: 'JO-801',
        customerName: 'Diana Prince',
        address: 'Paradise Island',
        status: 'Activated',
        materialsUsed: {
          'Drop Cable (m)': 60,
          'SC/APC Fast Connector': 2,
          'S-Clamp': 4,
        },
      );

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        jobsSignals =
            JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
        await db.jobOrdersDao.insertOrUpdateJob(jobWithMaterials);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: JobOrderDetailScreen(
          jobId: 801,
          jobsSignals: jobsSignals,
          readOnly: true,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final bomCardTitle = find.text('Materials Used (BOM)');
      expect(bomCardTitle, findsOneWidget);

      await tester.ensureVisible(bomCardTitle);
      await tester.pump();

      expect(find.text('Drop Cable (m)'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('SC/APC Fast Connector'), findsOneWidget);
      expect(find.text('S-Clamp'), findsOneWidget);

      await tester.runAsync(() async {
        await jobsSignals.dispose();
        await db.close();
      });
    });

    // Gene - Oct 13, 2026: Test dynamic material searching, adding with custom quantity, stepper interaction, and removal.
    testWidgets(
        'Dynamic materials selector filters with search, adds with custom count, and removes item',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late AppDatabase db;
      late JobsSignals jobsSignals;
      late ReportSignals reportSignals;

      final testJob = JobOrderDto(
        id: 901,
        ticketNumber: 'JO-901',
        customerName: 'Test Tech',
        address: 'Fiber Zone',
        status: 'Scheduled',
      );

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        jobsSignals =
            JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
        await db.jobOrdersDao.insertOrUpdateJob(testJob);
      });

      reportSignals = ReportSignals()..setJobOrder(testJob);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: CreateReportScreen(
          jobsSignals: jobsSignals,
          reportSignals: reportSignals,
          pickImage: (_) async => null,
        ),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('No materials added yet'), findsOneWidget);

      // Open picker
      final picker = find.byKey(const ValueKey('material_select_field'));
      await tester.scrollUntilVisible(picker, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(picker);
      await tester.pumpAndSettle();

      // Search for clip
      final searchInput = find.byType(TextField).last;
      await tester.enterText(searchInput, 'clip');
      await tester.pumpAndSettle();

      expect(find.text('FLAT CABLE CLIP'), findsOneWidget);
      await tester.tap(find.text('FLAT CABLE CLIP'));
      await tester.pumpAndSettle();

      /*
      // Enter quantity 5 and tap Add Material
      final qtyField = find.byKey(const ValueKey('material_add_qty_field'));
      await tester.enterText(qtyField, '5');
      await tester.pump();

      final addBtn = find.byKey(const ValueKey('add_material_button'));
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      expect(reportSignals.materialsUsed.value['FLAT CABLE CLIP'], 5);
      expect(find.text('FLAT CABLE CLIP'), findsOneWidget);
      expect(find.widgetWithText(TextField, '5'), findsOneWidget);
      */
      // Gene - Oct 13, 2026: Added materials default to quantity 1; tap counter plus button to increment.
      final addBtn = find.byKey(const ValueKey('add_material_button'));
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      expect(reportSignals.materialsUsed.value['FLAT CABLE CLIP'], 1);
      expect(find.text('FLAT CABLE CLIP'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1'), findsOneWidget);

      // Tap counter plus button to fast increment quantity in the added materials list
      final plusBtn =
          find.byKey(const ValueKey('counter_plus_flat_cable_clip'));
      expect(plusBtn, findsOneWidget);
      await tester.tap(plusBtn);
      await tester.pump();

      expect(reportSignals.materialsUsed.value['FLAT CABLE CLIP'], 2);
      expect(find.widgetWithText(TextField, '2'), findsOneWidget);

      // Tap remove button
      final removeBtn = find.byKey(const ValueKey('remove_material_flat_cable_clip'));
      expect(removeBtn, findsOneWidget);
      await tester.tap(removeBtn);
      await tester.pumpAndSettle();

      expect(reportSignals.materialsUsed.value['FLAT CABLE CLIP'], isNull);
      expect(find.textContaining('No materials added yet'), findsOneWidget);

      await tester.runAsync(() async {
        await jobsSignals.dispose();
        await db.close();
      });
    });
  });
}
