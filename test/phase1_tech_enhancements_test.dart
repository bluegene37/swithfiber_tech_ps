import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/database/daos/lcp_nap_dao.dart';
import 'package:swithfiber_tech_ps/core/network/network_exceptions.dart';
import 'package:swithfiber_tech_ps/core/services/draft_storage_service.dart';
import 'package:swithfiber_tech_ps/core/services/location_service.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/core/utils/data_url.dart';
import 'package:swithfiber_tech_ps/features/auth/models/user_model.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';
import 'package:swithfiber_tech_ps/features/diagnostics/screens/sync_error_log_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/models/lcp_nap_images_model.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/models/lcp_nap_model.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/screens/lcp_nap_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/screens/lcp_nap_list_screen.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/services/nap_port_occupancy.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';
import 'package:swithfiber_tech_ps/features/reports/screens/create_report_screen.dart';
import 'package:swithfiber_tech_ps/features/reports/signals/report_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/service_orders/services/service_orders_api.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';
import 'package:swithfiber_tech_ps/features/settings/screens/settings_screen.dart';

class _FakeJobsApi extends JobOrdersApi {
  bool failUpdate = false;
  int updateCalls = 0;

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
  Future<void> update(int id, Map<String, dynamic> body) async {
    updateCalls++;
    if (failUpdate) {
      throw ApiException(
        message: 'Validation error on job',
        statusCode: 422,
        requestMethod: 'PUT',
        requestUrl: '/api/JobOrders/1',
      );
    }
  }
}

class _FakeServiceOrdersApi extends ServiceOrdersApi {
  bool failUpdate = false;
  int statusCode = 500;
  int updateCalls = 0;

  @override
  Future<List<ServiceOrderDto>> fetchServiceOrders() async => [];

  @override
  Future<bool> updateServiceOrder(int id, Map<String, dynamic> payload) async {
    updateCalls++;
    if (failUpdate) {
      throw ApiException(
        message: 'Server busy',
        statusCode: statusCode,
        requestMethod: 'PUT',
        requestUrl: '/api/ServiceOrders/$id',
      );
    }
    return true;
  }
}

final _sigDataUrl = DataUrl.encode(
  Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]),
  mimeType: 'image/png',
);

class _TestLocationService extends LocationService {
  final Position? fixed;
  _TestLocationService(this.fixed);
  @override
  Position? get lastKnownPosition => fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    DraftStorageService.instance.resetForTesting();
    LocationService.instance = LocationService();
  });

  group('Step 1.1 Draft Auto-Save & PopScope', () {
    test('DraftStorageService saves, loads, and clears JSON on disk', () async {
      final dir = Directory.systemTemp.createTempSync('sf_draft_test_');
      addTearDown(() {
        DraftStorageService.instance.resetForTesting();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      DraftStorageService.instance.resetForTesting(baseDir: dir);
      await DraftStorageService.instance.saveDraft('job_report_77', {
        'routerSerial': 'HWTC777',
        'remarks': 'Good splice',
      });

      final loaded =
          await DraftStorageService.instance.loadDraft('job_report_77');
      expect(loaded, isNotNull);
      expect(loaded!['routerSerial'], 'HWTC777');
      expect(loaded['remarks'], 'Good splice');

      await DraftStorageService.instance.clearDraft('job_report_77');
      expect(
        await DraftStorageService.instance.loadDraft('job_report_77'),
        isNull,
      );
    });

    testWidgets(
        'CreateReportScreen restores draft, can discard it, and PopScope guards unsaved edits',
        (tester) async {
      late AppDatabase db;
      late JobsSignals jobsSignals;
      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        jobsSignals =
            JobsSignals(JobRepository(db.jobOrdersDao, api: _FakeJobsApi()));
        await db.jobOrdersDao.insertOrUpdateJob(JobOrderDto(
          id: 91,
          ticketNumber: 'SF-91',
          customerName: 'Juan Dela Cruz',
          address: 'Lot 91',
          status: 'Scheduled',
          modemRouterSN: 'ORIG91',
        ));
        await DraftStorageService.instance.saveDraft('job_report_91', {
          'routerSerial': 'DRAFT91',
          'remarks': 'Saved before speedtest',
        });
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      addTearDown(() async {
        await jobsSignals.dispose();
        await db.close();
      });

      final rep = ReportSignals()..setJobOrder(jobsSignals.allJobs.value.first);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CreateReportScreen(
                    jobsSignals: jobsSignals,
                    reportSignals: rep,
                    pickImage: (_) async => null,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('report_draft_restored_banner')),
          findsOneWidget);
      expect(rep.routerSerial.value, 'DRAFT91');

      // Pressing system back triggers PopScope confirmation dialog
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Leave report?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Discarding restores original job serial and hides banner
      await tester
          .tap(find.byKey(const ValueKey('discard_report_draft_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('report_draft_restored_banner')),
          findsNothing);
      expect(rep.routerSerial.value, 'ORIG91');
    });

    testWidgets('ServiceOrderDetailScreen restores draft and clears on discard',
        (tester) async {
      late AppDatabase db;
      late ServiceOrdersSignals soSignals;
      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        soSignals = ServiceOrdersSignals(
          dao: db.serviceOrdersDao,
          api: _FakeServiceOrdersApi(),
        );
        await db.serviceOrdersDao.insertOrUpdateOrder(ServiceOrderDto(
          id: 505,
          accountNumber: 'ACC-505',
          fullName: 'Maria Clara',
          contactNumber: '09171234567',
          emailAddress: 'maria@example.com',
          address: 'Batingan',
          concern: 'No Connection',
          supportStatus: 'Pending',
        ));
        await DraftStorageService.instance.saveDraft('service_order_505', {
          'newSn': 'ZTE-NEW-505',
          'remarks': 'Halfway done',
        });
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      addTearDown(() async {
        soSignals.dispose();
        await db.close();
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ServiceOrderDetailScreen(
          orderId: 505,
          signals: soSignals,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('service_order_draft_restored_banner')),
          findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('ZTE-NEW-505'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('ZTE-NEW-505'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('discard_service_order_draft_button')),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
          find.byKey(const ValueKey('discard_service_order_draft_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('service_order_draft_restored_banner')),
          findsNothing);
    });
  });

  group('Step 1.2 & 1.4 Job Detail Edit Report + NAP Pole Deep Link', () {
    testWidgets(
        'JobOrderDetailScreen offers Edit completion report & opens assigned NAP pole',
        (tester) async {
      late AppDatabase db;
      late JobsSignals jobsSignals;
      late LcpNapSignals lcpNapSignals;
      var openedReport = 0;

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        jobsSignals =
            JobsSignals(JobRepository(db.jobOrdersDao, api: _FakeJobsApi()));
        lcpNapSignals = LcpNapSignals(LcpNapRepository(LcpNapLocationsDao(db)));

        await db.lcpNapLocationsDao.insertOrUpdateLocation(LcpNapDto(
          id: 12,
          lcp: 'LCP 01',
          nap: 'NAP 008',
          lcpNap: 'LCP 01 - NAP 008',
          portTotal: 8,
          barangay: 'Batingan',
          city: 'Binangonan',
        ));
        await db.jobOrdersDao.insertOrUpdateJob(JobOrderDto(
          id: 42,
          ticketNumber: 'SF-42',
          customerName: 'Subscriber Santos',
          address: 'Lot 42',
          status: 'Scheduled',
          onsiteStatus: 'Done',
          lcpId: 1,
          napId: 12,
          nap: 'NAP 008',
          portId: 'PORT 003',
          modemRouterSN: 'HWTC42',
          clientSignature: _sigDataUrl,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      addTearDown(() async {
        await jobsSignals.dispose();
        await lcpNapSignals.dispose();
        await db.close();
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: JobOrderDetailScreen(
          jobId: 42,
          jobsSignals: jobsSignals,
          lcpNapSignals: lcpNapSignals,
          onOpenReport: (_) => openedReport++,
        ),
      ));
      await tester.pumpAndSettle();

      // AppBar Edit Report button + inline Edit completion report button
      expect(find.byKey(const ValueKey('appbar_edit_report_button')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('appbar_edit_report_button')));
      await tester.pump();
      expect(openedReport, 1);

      // Copy drift fixed + inline Edit completion report button
      final editBtn =
          find.byKey(const ValueKey('edit_completion_report_button'));
      await tester.scrollUntilVisible(
        editBtn,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Tap "Complete job"'), findsOneWidget);
      expect(find.textContaining('Mark as Completed'), findsNothing);
      await tester.tap(editBtn);
      await tester.pump();
      expect(openedReport, 2);

      // Deep link to assigned NAP pole (scroll back up to Plant card)
      final napBtn = find.byKey(const ValueKey('open_nap_pole_button'));
      await tester.scrollUntilVisible(
        napBtn,
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(napBtn, findsOneWidget);
      await tester.tap(napBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LcpNapDetailScreen), findsOneWidget);
    });
  });

  group('Step 1.3 Live NAP Port Occupancy & Nearby Free Ports', () {
    test('computeNapPortOccupancy and countFreePorts match jobs & repairs', () {
      final loc = LcpNapDto(
        id: 10,
        lcp: 'LCP 01',
        nap: 'NAP 008',
        lcpNap: 'LCP 01 - NAP 008',
        portTotal: 8,
      );
      final jobs = [
        JobOrderDto(
          id: 1,
          ticketNumber: 'T-1',
          customerName: 'Pedro',
          address: 'A',
          status: 'Activated',
          lcpId: 1,
          nap: 'NAP-008',
          portId: 'PORT 002',
        ),
        JobOrderDto(
          id: 2,
          ticketNumber: 'T-2',
          customerName: 'Ana',
          address: 'B',
          status: 'Rescheduled',
          lcpId: 1,
          nap: 'NAP 008',
          portId: 'PORT 003',
        ),
      ];
      final repairs = [
        ServiceOrderDto(
          id: 9,
          accountNumber: 'A-9',
          fullName: 'Liza',
          contactNumber: '0917',
          emailAddress: 'liza@example.com',
          address: 'C',
          concern: 'High Loss',
          supportStatus: 'Pending',
          lcp: 'LCP 01',
          nap: 'NAP 008',
          port: 'P5',
        ),
      ];

      final map = computeNapPortOccupancy(
        location: loc,
        jobs: jobs,
        serviceOrders: repairs,
      );
      expect(map.keys, containsAll([2, 5]));
      expect(map.containsKey(3), isFalse);
      expect(countFreePorts(loc, jobs: jobs, serviceOrders: repairs), 6);
    });

    testWidgets(
        'LcpNapDetailScreen renders real port occupancy and subscriber sheet on tap',
        (tester) async {
      late AppDatabase db;
      late JobsSignals jobsSignals;
      late LcpNapSignals lcpNapSignals;

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        jobsSignals =
            JobsSignals(JobRepository(db.jobOrdersDao, api: _FakeJobsApi()));
        lcpNapSignals = LcpNapSignals(LcpNapRepository(LcpNapLocationsDao(db)));
        await db.lcpNapLocationsDao.insertOrUpdateLocation(LcpNapDto(
          id: 20,
          lcp: 'LCP 01',
          nap: 'NAP 002',
          lcpNap: 'LCP 01 - NAP 002',
          portTotal: 2,
        ));
        await db.jobOrdersDao.insertOrUpdateJob(JobOrderDto(
          id: 1,
          ticketNumber: 'T-OCC-1',
          customerName: 'Marco Polo',
          address: 'Street 1',
          status: 'Activated',
          lcpId: 1,
          napId: 20,
          nap: 'NAP 002',
          portId: 'PORT 001',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      addTearDown(() async {
        await jobsSignals.dispose();
        await lcpNapSignals.dispose();
        await db.close();
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: LcpNapDetailScreen(
          locationId: 20,
          signals: lcpNapSignals,
          jobsSignals: jobsSignals,
          initialImagesForTesting: const LcpNapImagesDto(),
        ),
      ));
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('1 free · 1 used / 2'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(find.text('1 free · 1 used / 2'), findsOneWidget);
      final port1 = find.byKey(const ValueKey('nap_port_tile_1'));
      await tester.ensureVisible(port1);
      await tester.tap(port1);
      await tester.pumpAndSettle();

      expect(find.text('Marco Polo'), findsOneWidget);
      expect(find.textContaining('T-OCC-1'), findsOneWidget);
    });

    testWidgets(
        'LcpNapListScreen Nearby free ports filter excludes full NAPs and sorts nearest first',
        (tester) async {
      LocationService.instance = _TestLocationService(Position(
        latitude: 14.5000,
        longitude: 121.1800,
        timestamp: DateTime(2026, 11, 23),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ));

      late AppDatabase db;
      late JobsSignals jobsSignals;
      late LcpNapSignals lcpNapSignals;

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        jobsSignals =
            JobsSignals(JobRepository(db.jobOrdersDao, api: _FakeJobsApi()));
        lcpNapSignals = LcpNapSignals(LcpNapRepository(LcpNapLocationsDao(db)));
        await db.lcpNapLocationsDao.insertAllLocations([
          LcpNapDto(
            id: 1,
            lcp: 'LCP 01',
            nap: 'NAP FULL',
            lcpNap: 'LCP 01 - NAP FULL',
            portTotal: 1,
            coordinates: '14.5001, 121.1801',
          ),
          LcpNapDto(
            id: 2,
            lcp: 'LCP 01',
            nap: 'NAP FAR',
            lcpNap: 'LCP 01 - NAP FAR',
            portTotal: 4,
            coordinates: '14.5500, 121.2200',
          ),
          LcpNapDto(
            id: 3,
            lcp: 'LCP 01',
            nap: 'NAP NEAR',
            lcpNap: 'LCP 01 - NAP NEAR',
            portTotal: 4,
            coordinates: '14.5002, 121.1802',
          ),
        ]);
        await db.jobOrdersDao.insertOrUpdateJob(JobOrderDto(
          id: 99,
          ticketNumber: 'T-FULL',
          customerName: 'Full Sub',
          address: 'X',
          status: 'Activated',
          napId: 1,
          nap: 'NAP FULL',
          portId: 'PORT 001',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      addTearDown(() async {
        await jobsSignals.dispose();
        await lcpNapSignals.dispose();
        await db.close();
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: LcpNapListScreen(
          signals: lcpNapSignals,
          jobsSignals: jobsSignals,
        ),
      ));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey('plant_nearby_free_ports_chip')));
      await tester.pumpAndSettle();

      expect(find.textContaining('NAP FULL'), findsNothing);
      expect(find.textContaining('NAP NEAR'), findsOneWidget);
      expect(find.textContaining('NAP FAR'), findsOneWidget);
      final nearY = tester.getTopLeft(find.textContaining('NAP NEAR')).dy;
      final farY = tester.getTopLeft(find.textContaining('NAP FAR')).dy;
      expect(nearY, lessThan(farY));
    });
  });

  group('Step 1.5 Sync Error Log, Retry & Sign-Out Guard', () {
    test(
        'ServiceOrdersSyncWorker logs failures and resolves on syncSingleOrder',
        () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);

      final api = _FakeServiceOrdersApi()..failUpdate = true;
      final soSignals = ServiceOrdersSignals(
        dao: db.serviceOrdersDao,
        api: api,
        errorLog: db.syncErrorLogsDao,
      );
      addTearDown(soSignals.dispose);

      await db.serviceOrdersDao.insertOrUpdateOrder(
        ServiceOrderDto(
          id: 77,
          accountNumber: 'ACC-77',
          fullName: 'Repair Tech Test',
          contactNumber: '0917',
          emailAddress: 'repair@example.com',
          address: 'Batingan',
          concern: 'High Loss',
          supportStatus: 'Resolved',
          isSynced: false,
        ),
        synced: false,
      );

      final res = await soSignals.syncWorker!.syncPendingOrders();
      expect(res.success, isFalse);
      final logs = await db.syncErrorLogsDao.getAll(onlyUnresolved: true);
      expect(logs, hasLength(1));
      expect(logs.single.entityType, 'SERVICE_ORDER');
      expect(logs.single.statusCode, 500);
      expect(logs.single.payloadBytes, greaterThan(0));

      api.failUpdate = false;
      final retried = await soSignals.syncWorker!.syncSingleOrder(77);
      expect(retried, isTrue);
      expect(
        await db.syncErrorLogsDao.getAll(onlyUnresolved: true),
        isEmpty,
      );
    });

    test('SyncWorker.syncSingleJob syncs one job and resolves error log',
        () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
      final api = _FakeJobsApi()..failUpdate = true;
      final repo = JobRepository(
        db.jobOrdersDao,
        api: api,
        errorLog: db.syncErrorLogsDao,
      );
      await db.jobOrdersDao.insertOrUpdateJob(
        JobOrderDto(
          id: 88,
          ticketNumber: 'SF-88',
          customerName: 'Job Test',
          address: 'Street 88',
          status: 'Completed',
          isSynced: false,
        ),
        synced: false,
      );

      await repo.syncWorker.syncPendingJobs();
      expect(await db.syncErrorLogsDao.countUnresolved(), 1);

      api.failUpdate = false;
      final ok = await repo.syncWorker.syncSingleJob(88);
      expect(ok, isTrue);
      expect(await db.syncErrorLogsDao.countUnresolved(), 0);
    });

    testWidgets('SyncErrorLogScreen displays friendly hint and Retry button',
        (tester) async {
      late AppDatabase db;
      var retriedId = -1;
      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        await db.syncErrorLogsDao.log(
          entityType: 'SERVICE_ORDER',
          entityId: 77,
          reference: 'SO-0077',
          operation: 'repair',
          statusCode: 413,
          message: 'Entity too large',
          payloadBytes: 2048,
        );
      });
      addTearDown(db.close);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: SyncErrorLogScreen(
          dao: db.syncErrorLogsDao,
          onRetryItem: (log) async {
            retriedId = log.entityId;
            return true;
          },
        ),
      ));
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pumpAndSettle();

      expect(find.textContaining('size limit'), findsOneWidget);
      final retryBtn = find.text('Retry');
      expect(retryBtn, findsOneWidget);
      await tester.tap(retryBtn);
      await tester.pumpAndSettle();
      expect(retriedId, 77);
      expect(find.textContaining('Synced SO-0077'), findsOneWidget);
    });

    testWidgets(
        'SettingsScreen shows combined pending queue and warns on Sign Out when unsynced',
        (tester) async {
      late AppDatabase db;
      late JobsSignals jobsSignals;
      late ServiceOrdersSignals soSignals;
      late LcpNapSignals lcpSignals;

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        jobsSignals =
            JobsSignals(JobRepository(db.jobOrdersDao, api: _FakeJobsApi()));
        soSignals = ServiceOrdersSignals(
          dao: db.serviceOrdersDao,
          api: _FakeServiceOrdersApi(),
        );
        lcpSignals = LcpNapSignals(LcpNapRepository(LcpNapLocationsDao(db)));

        await db.jobOrdersDao.insertOrUpdateJob(
          JobOrderDto(
            id: 1,
            ticketNumber: 'SF-1',
            customerName: 'J1',
            address: 'A1',
            status: 'Completed',
            isSynced: false,
          ),
          synced: false,
        );
        await db.serviceOrdersDao.insertOrUpdateOrder(
          ServiceOrderDto(
            id: 2,
            accountNumber: 'A-2',
            fullName: 'R2',
            contactNumber: '0917',
            emailAddress: 'r2@example.com',
            address: 'Addr',
            concern: 'High Loss',
            supportStatus: 'Resolved',
            isSynced: false,
          ),
          synced: false,
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      AuthSignals.instance.currentUser.value = UserModel(
        id: 1,
        username: 'tech1',
        fname: 'Juan',
        lname: 'Dela Cruz',
        email: 'juan@switchfiber.ph',
        accessLevelId: 1,
        active: true,
        menus: const ['JobOrders'],
      );
      addTearDown(() async {
        AuthSignals.instance.currentUser.value = null;
        await jobsSignals.dispose();
        soSignals.dispose();
        await lcpSignals.dispose();
        await db.close();
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: SettingsScreen(
          authSignals: AuthSignals.instance,
          jobsSignals: jobsSignals,
          serviceOrdersSignals: soSignals,
          lcpNapSignals: lcpSignals,
        ),
      ));
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('2 offline updates'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('2 offline updates'), findsOneWidget);
      expect(find.text('Jobs 1 · Repairs 1 · Plant 0'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings_sync_now_button')),
          findsOneWidget);

      final signOutRow = find.text('Sign Out of Terminal');
      await tester.scrollUntilVisible(
        signOutRow,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(signOutRow);
      await tester.pumpAndSettle();

      expect(find.text('Unsynced work on phone'), findsOneWidget);
      expect(find.text('Sync & Sign Out'), findsOneWidget);
      expect(find.text('Sign Out Anyway'), findsOneWidget);
    });
  });
}
