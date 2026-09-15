import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/reports/screens/create_report_screen.dart';
import 'package:swithfiber_tech_ps/features/reports/signals/report_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Router Serial Scanner Tests', () {
    testWidgets('CreateReportScreen scans and populates router serial number',
        (tester) async {
      late AppDatabase db;
      late JobsSignals jobsSignals;
      late ReportSignals reportSignals;

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        jobsSignals =
            JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
      });

      final testJob = JobOrderDto(
        id: 101,
        ticketNumber: 'JO-101',
        customerName: 'Alice Smith',
        address: '123 Fiber Way',
        status: 'Scheduled',
        modemRouterSN: '',
      );

      reportSignals = ReportSignals()..setJobOrder(testJob);

      var scanCalled = false;
      Future<String?> mockScan(BuildContext context) async {
        scanCalled = true;
        return 'HWTC88997711';
      }

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: CreateReportScreen(
          jobsSignals: jobsSignals,
          reportSignals: reportSignals,
          pickImage: (_) async => null,
          scanBarcode: mockScan,
        ),
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      final scanBtn = find.byKey(const ValueKey('scan_router_serial_button'));
      expect(scanBtn, findsOneWidget);

      await tester.ensureVisible(scanBtn);
      await tester.tap(scanBtn);
      await tester.pumpAndSettle();

      expect(scanCalled, isTrue);
      expect(reportSignals.routerSerial.value, 'HWTC88997711');
      expect(find.text('HWTC88997711'), findsOneWidget);

      await tester.runAsync(() async {
        await jobsSignals.dispose();
        await db.close();
      });
    });

    testWidgets(
        'ServiceOrderDetailScreen scans and populates replacement and pullout serial',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final order = ServiceOrderDto(
        id: 202,
        accountNumber: 'ACC-202',
        fullName: 'Bob Johnson',
        contactNumber: '09170001122',
        emailAddress: 'bob@example.com',
        address: '456 Signal Rd',
        routerModemSN: 'OLD-SN-001',
      );

      final signals = ServiceOrdersSignals();
      signals.allOrders.value = [order];

      String nextScan = '';
      Future<String?> mockScan(BuildContext context) async {
        return nextScan;
      }

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ServiceOrderDetailScreen(
          orderId: 202,
          signals: signals,
          scanBarcode: mockScan,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Scan pullout SN
      nextScan = 'PULLOUT-999';
      final pulloutScanBtn =
          find.byKey(const ValueKey('scan_pullout_serial_button'));
      expect(pulloutScanBtn, findsOneWidget);
      await tester.ensureVisible(pulloutScanBtn);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(pulloutScanBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('PULLOUT-999'), findsOneWidget);

      // Scan replacement SN
      nextScan = 'REPLACE-888';
      final replaceScanBtn =
          find.byKey(const ValueKey('scan_replacement_serial_button'));
      expect(replaceScanBtn, findsOneWidget);
      await tester.ensureVisible(replaceScanBtn);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(replaceScanBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('REPLACE-888'), findsOneWidget);
    });
  });
}
