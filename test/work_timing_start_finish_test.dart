// Gene - Nov, 25, 2026: Unit, wire-contract, widget, and text-scale tests for Job Order & Service Order Start/Finish timing and gating.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/database/models/work_timing_entry.dart';
import 'package:swithfiber_tech_ps/core/network/api_client.dart';
import 'package:swithfiber_tech_ps/core/services/draft_storage_service.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/core/widgets/status_rail_row.dart';
import 'package:swithfiber_tech_ps/core/widgets/sticky_action_bar.dart';
import 'package:swithfiber_tech_ps/core/widgets/work_timing_bar.dart';
import 'package:swithfiber_tech_ps/features/auth/models/user_model.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';
import 'package:swithfiber_tech_ps/features/diagnostics/screens/work_timing_history_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_orders_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/reports/screens/create_report_screen.dart';
import 'package:swithfiber_tech_ps/features/reports/signals/report_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_orders_screen.dart';
import 'package:swithfiber_tech_ps/features/service_orders/services/service_orders_api.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/widgets/service_order_card.dart';

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

class _TimingRecordingJobApi extends JobOrdersApi {
  final List<Map<String, dynamic>> created = [];
  final List<Map<String, dynamic>> updated = [];

  @override
  Future<List<Map<String, dynamic>>> fetchByStatus(String status) async => [];

  @override
  Future<Map<String, dynamic>?> fetchById(int id) async => null;

  @override
  Future<void> update(int id, Map<String, dynamic> body) async {}

  @override
  Future<void> createTiming({
    required int joId,
    required String techId,
    required DateTime startTime,
    DateTime? endTime,
  }) async {
    created.add({
      'joId': joId,
      'techId': techId,
      'startTime': startTime,
      'endTime': endTime ?? startTime,
    });
  }

  @override
  Future<void> updateTiming({
    required int joId,
    required String techId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    updated.add({
      'joId': joId,
      'techId': techId,
      'startTime': startTime,
      'endTime': endTime,
    });
  }
}

class _TimingRecordingServiceOrdersApi extends ServiceOrdersApi {
  final List<Map<String, dynamic>> created = [];
  final List<Map<String, dynamic>> updated = [];

  @override
  Future<List<ServiceOrderDto>> fetchServiceOrders() async => [];

  @override
  Future<bool> createTiming({
    required int joId,
    required String techId,
    required DateTime startTime,
    DateTime? endTime,
  }) async {
    created.add({
      'joId': joId,
      'techId': techId,
      'startTime': startTime,
      'endTime': endTime ?? startTime,
    });
    return true;
  }

  @override
  Future<bool> updateTiming({
    required int joId,
    required String techId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    updated.add({
      'joId': joId,
      'techId': techId,
      'startTime': startTime,
      'endTime': endTime,
    });
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Timing helper & model status unit tests', () {
    test('normalizeTimingTimestamp & parseTimingTimestamp filter C# sentinels',
        () {
      expect(normalizeTimingTimestamp(null), isNull);
      expect(normalizeTimingTimestamp(DateTime.utc(1, 1, 1)), isNull);
      expect(normalizeTimingTimestamp(DateTime.utc(1900, 12, 31)), isNull);
      final valid = DateTime.utc(2026, 11, 25, 9, 30);
      expect(normalizeTimingTimestamp(valid), equals(valid));

      expect(parseTimingTimestamp('0001-01-01T00:00:00Z'), isNull);
      expect(parseTimingTimestamp('null'), isNull);
      expect(parseTimingTimestamp('  '), isNull);
      expect(parseTimingTimestamp('2026-11-25T09:30:00Z'), equals(valid));
    });

    test('resolveWorkTimingStatus distinguishes notStarted/inProgress/finished',
        () {
      final start = DateTime.utc(2026, 11, 25, 8, 0);
      final sameEnd = DateTime.utc(2026, 11, 25, 8, 0);
      final laterEnd = DateTime.utc(2026, 11, 25, 9, 15);

      expect(resolveWorkTimingStatus(null, null), WorkTimingStatus.notStarted);
      expect(resolveWorkTimingStatus(DateTime.utc(1, 1, 1), laterEnd),
          WorkTimingStatus.notStarted);
      expect(resolveWorkTimingStatus(start, null), WorkTimingStatus.inProgress);
      expect(
          resolveWorkTimingStatus(start, sameEnd), WorkTimingStatus.inProgress);
      expect(
          resolveWorkTimingStatus(start, laterEnd), WorkTimingStatus.finished);
    });

    test('JobOrderDto and ServiceOrderDto round-trip timestamps through SQLite',
        () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);

      final start = DateTime.utc(2026, 11, 25, 8, 15);
      final end = DateTime.utc(2026, 11, 25, 9, 45);

      final job = JobOrderDto(
        id: 11,
        ticketNumber: 'SF-11',
        customerName: 'Example Customer',
        address: 'Lot 11',
        status: 'Scheduled',
        startTimeStamp: start,
        endTimeStamp: start,
      );
      expect(job.workTimingStatus, WorkTimingStatus.inProgress);
      expect(job.isWorkUnlocked, isTrue);

      await db.jobOrdersDao.insertOrUpdateJob(job, synced: true);
      final loadedJob = await db.jobOrdersDao.getJobById(11);
      expect(loadedJob?.workTimingStatus, WorkTimingStatus.inProgress);
      expect(loadedJob?.startTimeStamp?.toUtc(), equals(start));

      await db.jobOrdersDao.updateJobTiming(11, endTimeStamp: end);
      final finishedJob = await db.jobOrdersDao.getJobById(11);
      expect(finishedJob?.workTimingStatus, WorkTimingStatus.finished);
      expect(finishedJob?.isWorkUnlocked, isFalse);

      final order = ServiceOrderDto(
        id: 22,
        accountNumber: 'ACC-22',
        fullName: 'Example Subscriber',
        contactNumber: '09170000022',
        emailAddress: 'sub22@example.com',
        address: 'Lot 22',
        startTimestamp: start,
        stopTimestamp: end,
      );
      expect(order.workTimingStatus, WorkTimingStatus.finished);
      expect(order.isWorkUnlocked, isFalse);

      await db.serviceOrdersDao.insertOrUpdateOrder(order, synced: true);
      final loadedOrder = await db.serviceOrdersDao.getOrderById(22);
      expect(loadedOrder?.workTimingStatus, WorkTimingStatus.finished);
      expect(loadedOrder?.startTimestamp?.toUtc(), equals(start));
      expect(loadedOrder?.stopTimestamp?.toUtc(), equals(end));
    });
  });

  group('Timing API wire-contract tests', () {
    test(
        'JobOrdersApi & ServiceOrdersApi send expected POST createtiming and PUT updatetiming JSON payloads',
        () async {
      final originalAdapter = ApiClient.instance.dio.httpClientAdapter;
      final originalBlock = ApiClient.blockNetworkForTesting;
      final adapter = _CapturingHttpAdapter();
      FlutterSecureStorage.setMockInitialValues({'jwt_token': 'test-token'});
      ApiClient.instance.dio.httpClientAdapter = adapter;
      ApiClient.blockNetworkForTesting = false;

      try {
        final start = DateTime.utc(2026, 11, 25, 8, 0);
        final end = DateTime.utc(2026, 11, 25, 9, 0);

        final jobApi = DioJobOrdersApi(ApiClient.instance);
        await jobApi.createTiming(
          joId: 401,
          techId: '7',
          startTime: start,
        );
        expect(adapter.lastOptions?.method, 'POST');
        expect(adapter.lastOptions?.path, '/JobOrders/createtiming');
        expect(jsonDecode(adapter.capturedBody!), {
          'joId': 401,
          'techId': '7',
          'startTime': start.toIso8601String(),
          'endTime': start.toIso8601String(),
        });

        await jobApi.updateTiming(
          joId: 401,
          techId: '7',
          startTime: start,
          endTime: end,
        );
        expect(adapter.lastOptions?.method, 'PUT');
        expect(adapter.lastOptions?.path, '/JobOrders/updatetiming');
        expect(jsonDecode(adapter.capturedBody!), {
          'joId': 401,
          'techId': '7',
          'startTime': start.toIso8601String(),
          'endTime': end.toIso8601String(),
        });

        final soApi = ServiceOrdersApi(ApiClient.instance);
        final soCreated = await soApi.createTiming(
          joId: 501,
          techId: '9',
          startTime: start,
        );
        expect(soCreated, isTrue);
        expect(adapter.lastOptions?.method, 'POST');
        expect(adapter.lastOptions?.path, '/ServiceOrders/createtiming');
        expect(jsonDecode(adapter.capturedBody!), {
          'joId': 501,
          'techId': '9',
          'startTime': start.toIso8601String(),
          'endTime': start.toIso8601String(),
        });

        final soUpdated = await soApi.updateTiming(
          joId: 501,
          techId: '9',
          startTime: start,
          endTime: end,
        );
        expect(soUpdated, isTrue);
        expect(adapter.lastOptions?.method, 'PUT');
        expect(adapter.lastOptions?.path, '/ServiceOrders/updatetiming');
        expect(jsonDecode(adapter.capturedBody!), {
          'joId': 501,
          'techId': '9',
          'startTime': start.toIso8601String(),
          'endTime': end.toIso8601String(),
        });
      } finally {
        ApiClient.instance.dio.httpClientAdapter = originalAdapter;
        ApiClient.blockNetworkForTesting = originalBlock;
      }
    });
  });

  group('Job Order & Service Order Start -> Finish -> Locked lifecycle', () {
    testWidgets(
        'Job Order list Start unlocks report & detail controls, Finish re-locks them',
        (tester) async {
      final db = AppDatabase.forTesting();
      final api = _TimingRecordingJobApi();
      final repo = JobRepository(db.jobOrdersDao, api: api);
      final signals = JobsSignals(repo);
      signals.setTechnicianEmail('tech@example.com');
      addTearDown(() async {
        await signals.dispose();
        await db.close();
      });

      await tester.runAsync(() async {
        await db.jobOrdersDao.insertOrUpdateJob(
          JobOrderDto(
            id: 101,
            ticketNumber: 'SF-101',
            customerName: 'Juan Dela Cruz',
            address: '101 Sample St',
            status: 'Scheduled',
            onsiteStatus: 'Scheduled',
            assignedEmail: 'tech@example.com',
            updatedAt: DateTime.now(),
          ),
          synced: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(402, 950);
      addTearDown(tester.view.reset);

      var reportTapped = false;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: JobOrdersScreen(
          jobsSignals: signals,
          onSelectJobForReport: (_) => reportTapped = true,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Not started: Start button visible; report shortcut locked.
      final startFinder = find.byKey(const ValueKey('job_start_button_101'));
      final shortcutFinder =
          find.byKey(const ValueKey('job_report_shortcut_101'));
      expect(startFinder, findsOneWidget);
      expect(tester.widget<InkWell>(shortcutFinder).onTap, isNull);

      await tester.tap(shortcutFinder, warnIfMissed: false);
      await tester.pump();
      expect(reportTapped, isFalse);

      // Opening details before Start shows lock banner & hides report/status controls.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: JobOrderDetailScreen(jobId: 101, jobsSignals: signals),
      ));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('job_timing_lock_banner')), findsOneWidget);
      expect(find.text('Fill completion report'), findsNothing);
      expect(find.byKey(const ValueKey('job_status_change')), findsNothing);

      // Return to list and tap Start.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: JobOrdersScreen(
          jobsSignals: signals,
          onSelectJobForReport: (_) => reportTapped = true,
        ),
      ));
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(startFinder);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      // 2. In progress: API called, Finish button shown, shortcut enabled.
      expect(api.created.length, 1);
      expect(api.created.first['joId'], 101);
      final finishFinder = find.byKey(const ValueKey('job_finish_button_101'));
      expect(finishFinder, findsOneWidget);
      expect(tester.widget<InkWell>(shortcutFinder).onTap, isNotNull);

      await tester.tap(shortcutFinder);
      await tester.pump();
      expect(reportTapped, isTrue);

      // Detail screen now shows report & status controls.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: JobOrderDetailScreen(jobId: 101, jobsSignals: signals),
      ));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('job_timing_lock_banner')), findsNothing);
      expect(find.text('Fill completion report'), findsOneWidget);
      final statusChangeFinder =
          find.byKey(const ValueKey('job_status_change'));
      await tester.scrollUntilVisible(
        statusChangeFinder,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(statusChangeFinder, findsOneWidget);

      // Return to list and tap Finish.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: JobOrdersScreen(
          jobsSignals: signals,
          onSelectJobForReport: (_) => reportTapped = true,
        ),
      ));
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(finishFinder);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      // 3. Finished: updatetiming called with endTime > startTime, Start Again button shown, re-locked.
      expect(api.updated.length, 1);
      final updStart = api.updated.first['startTime'] as DateTime;
      final updEnd = api.updated.first['endTime'] as DateTime;
      expect(updEnd.isAfter(updStart), isTrue);

      final restartFinder = find.byKey(const ValueKey('job_start_button_101'));
      expect(restartFinder, findsOneWidget);
      expect(find.text('Start Again'), findsOneWidget);
      final restartBtn = tester.widget<FilledButton>(restartFinder);
      expect(restartBtn.onPressed, isNotNull);
      expect(tester.widget<InkWell>(shortcutFinder).onTap, isNull);
    });

    testWidgets(
        'Service Order list Start unlocks editing & StickyActionBar, Finish re-locks',
        (tester) async {
      DraftStorageService.instance.resetForTesting();
      final api = _TimingRecordingServiceOrdersApi();
      final signals = ServiceOrdersSignals(api: api);
      signals.setTechnicianEmail('tech@example.com');
      addTearDown(signals.dispose);

      signals.allOrders.value = [
        const ServiceOrderDto(
          id: 201,
          accountNumber: 'ACC-201',
          fullName: 'Maria Santos',
          contactNumber: '09170000201',
          emailAddress: 'maria@example.com',
          address: '201 Fiber Ave',
          concern: 'Pullout',
          priorityLevel: 'Urgent',
          supportStatus: 'Open',
          assignedEmail: 'tech@example.com',
        ),
      ];

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(402, 950);
      addTearDown(tester.view.reset);

      // 1. Card renders Start button initially.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ServiceOrderCard(
            order: signals.allOrders.value.first,
            signals: signals,
          ),
        ),
      ));
      await tester.pump();

      final startFinder =
          find.byKey(const ValueKey('service_order_start_button_201'));
      expect(startFinder, findsOneWidget);

      // Detail screen shows lock banner, hides StickyActionBar, ignores text input.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ServiceOrderDetailScreen(orderId: 201, signals: signals),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('service_order_timing_lock_banner')),
          findsOneWidget);
      expect(find.text('Save repair report'), findsNothing);
      expect(find.text('Complete service order'), findsNothing);
      final remarksFinder = find.byKey(const ValueKey('pullout_remarks_field'));
      expect(remarksFinder, findsOneWidget);
      final ignoreAncestor = tester.widget<IgnorePointer>(find
          .ancestor(
            of: remarksFinder,
            matching: find.byType(IgnorePointer),
          )
          .first);
      expect(ignoreAncestor.ignoring, isTrue);

      // Back to card and tap Start.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ServiceOrderCard(
            order: signals.allOrders.value.first,
            signals: signals,
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(startFinder);
      await tester.pumpAndSettle();

      expect(api.created.length, 1);
      expect(api.created.first['joId'], 201);

      // Rebuild card with updated signal order -> Finish button appears.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ServiceOrderCard(
            order: signals.allOrders.value.first,
            signals: signals,
          ),
        ),
      ));
      await tester.pump();
      final finishFinder =
          find.byKey(const ValueKey('service_order_finish_button_201'));
      expect(finishFinder, findsOneWidget);

      // Detail screen now unlocked: no lock banner, StickyActionBar visible, IgnorePointer disabled.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ServiceOrderDetailScreen(orderId: 201, signals: signals),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('service_order_timing_lock_banner')),
          findsNothing);
      expect(find.text('Complete service order'), findsOneWidget);
      final unlockedIgnore = tester.widget<IgnorePointer>(find
          .ancestor(
            of: remarksFinder,
            matching: find.byType(IgnorePointer),
          )
          .first);
      expect(unlockedIgnore.ignoring, isFalse);

      // Back to card and tap Finish.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ServiceOrderCard(
            order: signals.allOrders.value.first,
            signals: signals,
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(finishFinder);
      await tester.pumpAndSettle();

      expect(api.updated.length, 1);
      final soStart = api.updated.first['startTime'] as DateTime;
      final soEnd = api.updated.first['endTime'] as DateTime;
      expect(soEnd.isAfter(soStart), isTrue);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ServiceOrderCard(
            order: signals.allOrders.value.first,
            signals: signals,
          ),
        ),
      ));
      await tester.pump();
      // Gene - Nov, 26, 2026: Stop transitions Service Order to Start Again and re-locks detail controls.
      final restartSoFinder =
          find.byKey(const ValueKey('service_order_start_button_201'));
      expect(restartSoFinder, findsOneWidget);
      expect(find.text('Start Again'), findsOneWidget);
      expect(tester.widget<FilledButton>(restartSoFinder).onPressed, isNotNull);

      // Detail screen re-locked after Finish.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ServiceOrderDetailScreen(orderId: 201, signals: signals),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('service_order_timing_lock_banner')),
          findsOneWidget);
      expect(find.text('Save repair report'), findsNothing);
    });

    // Gene - Nov, 26, 2026: Verify Job Order card disables Details/Navigate/Call/SMS/> until Start and re-locks on Finish.
    testWidgets(
        'Job Order card disables Details, Navigate, Call, SMS, and > until Start and re-locks on Finish',
        (tester) async {
      final db = AppDatabase.forTesting();
      final api = _TimingRecordingJobApi();
      final repo = JobRepository(db.jobOrdersDao, api: api);
      final signals = JobsSignals(repo);
      signals.setTechnicianEmail('tech@example.com');
      addTearDown(() async {
        await signals.dispose();
        await db.close();
      });

      await tester.runAsync(() async {
        await db.jobOrdersDao.insertOrUpdateJob(
          JobOrderDto(
            id: 101,
            ticketNumber: 'SF-101',
            customerName: 'Juan Dela Cruz',
            address: '101 Sample St',
            contactNumber: '09171234567',
            status: 'Scheduled',
            onsiteStatus: 'Scheduled',
            assignedEmail: 'tech@example.com',
            updatedAt: DateTime.now(),
          ),
          synced: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(402, 950);
      addTearDown(tester.view.reset);

      var detailsTapped = false;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: JobOrdersScreen(
          jobsSignals: signals,
          onSelectJobForDetails: (_) => detailsTapped = true,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      for (final keyName in [
        'job_action_navigate_101',
        'job_action_call_101',
        'job_action_sms_101',
        'job_action_details_101',
      ]) {
        final action =
            tester.widget<StatusRailAction>(find.byKey(ValueKey(keyName)));
        expect(action.onTap, isNull, reason: '$keyName locked before Start');
      }
      expect(
        tester
            .widget<InkWell>(
                find.byKey(const ValueKey('job_report_shortcut_101')))
            .onTap,
        isNull,
      );

      await tester.tap(
        find.byKey(const ValueKey('job_action_details_101')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(detailsTapped, isFalse);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('job_start_button_101')));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      for (final keyName in [
        'job_action_navigate_101',
        'job_action_call_101',
        'job_action_sms_101',
        'job_action_details_101',
      ]) {
        final action =
            tester.widget<StatusRailAction>(find.byKey(ValueKey(keyName)));
        expect(action.onTap, isNotNull,
            reason: '$keyName unlocked after Start');
      }
      expect(
        tester
            .widget<InkWell>(
                find.byKey(const ValueKey('job_report_shortcut_101')))
            .onTap,
        isNotNull,
      );

      await tester.tap(find.byKey(const ValueKey('job_action_details_101')));
      await tester.pump();
      expect(detailsTapped, isTrue);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('job_finish_button_101')));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      for (final keyName in [
        'job_action_navigate_101',
        'job_action_call_101',
        'job_action_sms_101',
        'job_action_details_101',
      ]) {
        final action =
            tester.widget<StatusRailAction>(find.byKey(ValueKey(keyName)));
        expect(action.onTap, isNull, reason: '$keyName re-locked after Finish');
      }
      expect(
        tester
            .widget<InkWell>(
                find.byKey(const ValueKey('job_report_shortcut_101')))
            .onTap,
        isNull,
      );
    });

    // Gene - Nov, 26, 2026: Verify Service Order card disables details tap & Navigate/Call/SMS until Start and re-locks on Finish.
    testWidgets(
        'Service Order card disables details tap and Navigate/Call/SMS until Start and re-locks on Finish',
        (tester) async {
      DraftStorageService.instance.resetForTesting();
      final api = _TimingRecordingServiceOrdersApi();
      final signals = ServiceOrdersSignals(api: api);
      signals.setTechnicianEmail('tech@example.com');
      addTearDown(signals.dispose);

      signals.allOrders.value = [
        const ServiceOrderDto(
          id: 201,
          accountNumber: 'ACC-201',
          fullName: 'Maria Santos',
          contactNumber: '09170000201',
          emailAddress: 'maria@example.com',
          address: '201 Fiber Ave',
          concern: 'Pullout',
          priorityLevel: 'Urgent',
          supportStatus: 'Open',
          assignedEmail: 'tech@example.com',
        ),
      ];

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(402, 950);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ServiceOrdersScreen(signals: signals),
      ));
      await tester.pump();

      expect(
        tester
            .widget<InkWell>(
                find.byKey(const ValueKey('service_order_card_tap_201')))
            .onTap,
        isNull,
      );
      for (final keyName in [
        'so_action_navigate_201',
        'so_action_call_201',
        'so_action_sms_201',
      ]) {
        expect(
          tester.widget<StatusRailAction>(find.byKey(ValueKey(keyName))).onTap,
          isNull,
          reason: '$keyName locked before Start',
        );
      }

      // Tapping locked card body must NOT open ServiceOrderDetailScreen.
      await tester.tap(
        find.byKey(const ValueKey('service_order_card_tap_201')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ServiceOrderDetailScreen), findsNothing);

      // Tap Start -> unlocked.
      await tester
          .tap(find.byKey(const ValueKey('service_order_start_button_201')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<InkWell>(
                find.byKey(const ValueKey('service_order_card_tap_201')))
            .onTap,
        isNotNull,
      );
      for (final keyName in [
        'so_action_navigate_201',
        'so_action_call_201',
        'so_action_sms_201',
      ]) {
        expect(
          tester.widget<StatusRailAction>(find.byKey(ValueKey(keyName))).onTap,
          isNotNull,
          reason: '$keyName unlocked after Start',
        );
      }

      // Tapping unlocked card opens ServiceOrderDetailScreen.
      await tester
          .tap(find.byKey(const ValueKey('service_order_card_tap_201')));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceOrderDetailScreen), findsOneWidget);

      // Pop back and tap Finish -> re-locked.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('service_order_finish_button_201')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<InkWell>(
                find.byKey(const ValueKey('service_order_card_tap_201')))
            .onTap,
        isNull,
      );
      for (final keyName in [
        'so_action_navigate_201',
        'so_action_call_201',
        'so_action_sms_201',
      ]) {
        expect(
          tester.widget<StatusRailAction>(find.byKey(ValueKey(keyName))).onTap,
          isNull,
          reason: '$keyName re-locked after Finish',
        );
      }
    });

    // Gene - Nov, 26, 2026: Verify starting one Job Order or Service Order hides Start on all other Job Orders and Service Orders until Finish.
    testWidgets(
        'Starting one Job Order or Service Order hides Start on all other Job Orders and Service Orders until Finish',
        (tester) async {
      DraftStorageService.instance.resetForTesting();
      final db = AppDatabase.forTesting();
      final jobApi = _TimingRecordingJobApi();
      final soApi = _TimingRecordingServiceOrdersApi();
      final jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao, api: jobApi));
      final soSignals = ServiceOrdersSignals(api: soApi);
      jobsSignals.setTechnicianEmail('tech@example.com');
      soSignals.setTechnicianEmail('tech@example.com');
      addTearDown(() async {
        await jobsSignals.dispose();
        soSignals.dispose();
        await db.close();
      });

      await tester.runAsync(() async {
        await db.jobOrdersDao.insertAllJobs([
          JobOrderDto(
            id: 101,
            ticketNumber: 'SF-101',
            customerName: 'Job 101',
            address: '101 St',
            status: 'Scheduled',
            assignedEmail: 'tech@example.com',
            updatedAt: DateTime.now(),
          ),
          JobOrderDto(
            id: 102,
            ticketNumber: 'SF-102',
            customerName: 'Job 102',
            address: '102 St',
            status: 'Scheduled',
            assignedEmail: 'tech@example.com',
            updatedAt: DateTime.now(),
          ),
        ]);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });

      soSignals.allOrders.value = [
        const ServiceOrderDto(
          id: 201,
          accountNumber: 'ACC-201',
          fullName: 'Repair 201',
          contactNumber: '09170000201',
          emailAddress: 'r201@example.com',
          address: '201 Ave',
          concern: 'Pullout',
          priorityLevel: 'Normal',
          supportStatus: 'Open',
          assignedEmail: 'tech@example.com',
        ),
        const ServiceOrderDto(
          id: 202,
          accountNumber: 'ACC-202',
          fullName: 'Repair 202',
          contactNumber: '09170000202',
          emailAddress: 'r202@example.com',
          address: '202 Ave',
          concern: 'No Connection',
          priorityLevel: 'High',
          supportStatus: 'Open',
          assignedEmail: 'tech@example.com',
        ),
      ];

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(402, 1800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            body: TabBarView(
              children: [
                JobOrdersScreen(
                  jobsSignals: jobsSignals,
                  serviceOrdersSignals: soSignals,
                ),
                ServiceOrdersScreen(
                  signals: soSignals,
                  jobsSignals: jobsSignals,
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Initially JO 101 and 102 both show Start.
      expect(
          find.byKey(const ValueKey('job_start_button_101')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('job_start_button_102')), findsOneWidget);

      // Start JO 101 -> JO 101 shows Finish, JO 102 Start is hidden.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('job_start_button_101')));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('job_finish_button_101')), findsOneWidget);
      expect(find.byKey(const ValueKey('job_start_button_102')), findsNothing);

      // Switch to Service Orders tab -> SO 201 and 202 Start buttons are hidden.
      final tabController =
          DefaultTabController.of(tester.element(find.byType(TabBarView)));
      tabController.animateTo(1);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('service_order_start_button_201')),
          findsNothing);
      expect(find.byKey(const ValueKey('service_order_start_button_202')),
          findsNothing);

      // Switch back to Job Orders tab and Finish JO 101 -> JO 102 Start reappears.
      tabController.animateTo(0);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('job_finish_button_101')));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      // Finish JO 101 -> JO 101 shows Start Again and JO 102 Start reappears.
      expect(
          find.byKey(const ValueKey('job_start_button_101')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('job_start_button_102')), findsOneWidget);

      // Switch to Service Orders tab -> SO 201 and 202 Start buttons reappeared.
      tabController.animateTo(1);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('service_order_start_button_201')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('service_order_start_button_202')),
          findsOneWidget);

      // Start SO 201 -> SO 202 Start is hidden, and JO 102 Start is hidden.
      await tester
          .tap(find.byKey(const ValueKey('service_order_start_button_201')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('service_order_finish_button_201')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('service_order_start_button_202')),
          findsNothing);

      tabController.animateTo(0);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('job_start_button_102')), findsNothing);

      // Finish SO 201 -> JO 102 and SO 202 Start buttons reappear.
      tabController.animateTo(1);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('service_order_finish_button_201')));
      await tester.pumpAndSettle();
      // Stop SO 201 -> SO 201 shows Start Again and SO 202 Start reappears.
      expect(find.byKey(const ValueKey('service_order_start_button_201')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('service_order_start_button_202')),
          findsOneWidget);

      tabController.animateTo(0);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('job_start_button_102')), findsOneWidget);
    });

    // Gene - Nov, 26, 2026: Verify techId (user ID), computed duration, and Service Order audit fields are populated on Start/Finish.
    test(
        'Start/Finish populate techId from signed-in user ID, numeric duration, and Service Order audit metadata',
        () async {
      final prevUser = AuthSignals.instance.currentUser.value;
      addTearDown(() => AuthSignals.instance.currentUser.value = prevUser);

      AuthSignals.instance.currentUser.value = UserModel(
        id: 42,
        username: 'tech42',
        fname: 'Juan',
        lname: 'Tech',
        email: 'tech42@example.com',
      );

      final db = AppDatabase.forTesting();
      final jobApi = _TimingRecordingJobApi();
      final soApi = _TimingRecordingServiceOrdersApi();
      final jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao, api: jobApi));
      final soSignals =
          ServiceOrdersSignals(api: soApi, dao: db.serviceOrdersDao);
      jobsSignals.setTechnicianEmail('tech42@example.com');
      soSignals.setTechnicianEmail('tech42@example.com');
      addTearDown(() async {
        await jobsSignals.dispose();
        soSignals.dispose();
        await db.close();
      });

      final job = JobOrderDto(
        id: 301,
        ticketNumber: 'SF-301',
        customerName: 'Job 301',
        address: '301 St',
        status: 'Scheduled',
        assignedEmail: 'tech42@example.com',
      );
      await db.jobOrdersDao.insertOrUpdateJob(job, synced: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await jobsSignals.startJob(job);
      expect(jobApi.created.length, 1);
      expect(jobApi.created.first['techId'], '42');

      final startedJob = (await db.jobOrdersDao.getJobById(301))!;
      await jobsSignals.finishJob(startedJob);
      expect(jobApi.updated.length, 1);
      expect(jobApi.updated.first['techId'], '42');

      final finishedJob = (await db.jobOrdersDao.getJobById(301))!;
      final jobPutJson = finishedJob.toApiJson();
      expect(int.tryParse(jobPutJson['duration'].toString()), isNotNull);

      const order = ServiceOrderDto(
        id: 401,
        accountNumber: 'ACC-401',
        fullName: 'Order 401',
        contactNumber: '09170000401',
        emailAddress: 'o401@example.com',
        address: '401 Ave',
        concern: 'Pullout',
        supportStatus: 'Open',
        assignedEmail: 'tech42@example.com',
      );
      await db.serviceOrdersDao.insertOrUpdateOrder(order, synced: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await soSignals.startOrder(order);
      expect(soApi.created.length, 1);
      expect(soApi.created.first['techId'], '42');

      final startedOrder = (await db.serviceOrdersDao.getOrderById(401))!;
      expect(startedOrder.modifiedBy, 'Juan Tech');
      expect(startedOrder.userEmail, 'tech42@example.com');
      expect(startedOrder.modifiedDate, isNotNull);
      expect(startedOrder.techModifiedDate, isNotNull);

      await soSignals.finishOrder(startedOrder);
      expect(soApi.updated.length, 1);
      expect(soApi.updated.first['techId'], '42');

      final finishedOrder = (await db.serviceOrdersDao.getOrderById(401))!;
      final soPutJson = finishedOrder.toJson();
      expect(int.tryParse(soPutJson['duration'].toString()), isNotNull);
      expect(soPutJson['modifiedBy'], 'Juan Tech');
      expect(soPutJson['userEmail'], 'tech42@example.com');
    });

    // Gene - Nov, 26, 2026: Verify CreateReportScreen locks and disables Save report when Job Order is not started.
    testWidgets(
        'CreateReportScreen shows lock banner and disables Save report when Job Order is not started',
        (tester) async {
      final db = AppDatabase.forTesting();
      final jobApi = _TimingRecordingJobApi();
      final jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao, api: jobApi));
      addTearDown(() async {
        await jobsSignals.dispose();
        await db.close();
      });

      final unstartedJob = JobOrderDto(
        id: 501,
        ticketNumber: 'SF-501',
        customerName: 'Unstarted Subscriber',
        address: '501 St',
        status: 'Scheduled',
        modemRouterSN: 'SN501',
      );
      await tester.runAsync(() async {
        await db.jobOrdersDao.insertOrUpdateJob(unstartedJob, synced: true);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      final reportSignals = ReportSignals()..setJobOrder(unstartedJob);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: CreateReportScreen(
          jobsSignals: jobsSignals,
          reportSignals: reportSignals,
          pickImage: (_) async => null,
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('report_timing_lock_banner')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Locked until started'),
        findsWidgets,
      );
      final stickyBar =
          tester.widget<StickyActionBar>(find.byType(StickyActionBar));
      expect(stickyBar.onPressed, isNull);
    });
  });

  group('Accessibility & 200% text-scale layout', () {
    testWidgets(
        'WorkTimingBar and WorkTimingLockBanner render without overflow at 200% text scale on 402dp width',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(402, 874);
      addTearDown(tester.view.reset);

      final overflows = <String>[];
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) {
          overflows.add(msg);
        } else {
          origOnError?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = origOnError);

      final start = DateTime.utc(2026, 11, 25, 8, 5);
      final end = DateTime.utc(2026, 11, 25, 10, 42);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                WorkTimingBar(
                  status: WorkTimingStatus.notStarted,
                  onStart: () {},
                ),
                const WorkTimingBar(
                  status: WorkTimingStatus.notStarted,
                  hideStart: true,
                ),
                WorkTimingBar(
                  status: WorkTimingStatus.inProgress,
                  startTime: start,
                  onFinish: () {},
                ),
                WorkTimingBar(
                  status: WorkTimingStatus.finished,
                  startTime: start,
                  endTime: end,
                ),
                const WorkTimingLockBanner(
                  status: WorkTimingStatus.notStarted,
                ),
                WorkTimingLockBanner(
                  status: WorkTimingStatus.inProgress,
                  startTime: start,
                ),
                WorkTimingLockBanner(
                  status: WorkTimingStatus.finished,
                  startTime: start,
                  endTime: end,
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(overflows, isEmpty, reason: overflows.join('\n'));
    });

    // Gene - Nov, 26, 2026: Verify date+time formatting, timing merge, restartable Start Again sessions, WorkTimingHistoryDao/Screen filtering by userId & date, and ServiceOrderCard Job Order parity.
    test(
        'Date+time helpers and mergeWorkTimingTimestamps preserve newer restarted sessions',
        () {
      final s1 = DateTime(2026, 11, 26, 8, 5);
      final e1 = DateTime(2026, 11, 26, 9, 15);
      final s2 = DateTime(2026, 11, 26, 10, 0);

      expect(formatTimingDateKey(s1), '2026-11-26');
      expect(formatTimingDateTime(s1), contains('Nov 26'));
      expect(formatTimingDateTime(s1), contains('8:05 AM'));
      expect(formatTimingRange(s1, e1), contains('Nov 26'));
      expect(formatTimingRange(s1, e1), contains('8:05 AM'));
      expect(formatTimingRange(s1, e1), contains('9:15 AM'));

      // Newer local restart (s2, s2) must beat older finished server session (s1, e1).
      final (mergedStart, mergedEnd) = mergeWorkTimingTimestamps(
        serverStart: s1,
        serverEnd: e1,
        localStart: s2,
        localEnd: s2,
      );
      expect(mergedStart, equals(s2));
      expect(mergedEnd, equals(s2));
      expect(resolveWorkTimingStatus(mergedStart, mergedEnd),
          WorkTimingStatus.inProgress);
    });

    testWidgets(
        'Restarting Job Order and Service Order records multiple sessions in WorkTimingHistoryDao and renders in WorkTimingHistoryScreen filtered by userId & date',
        (tester) async {
      final prevUser = AuthSignals.instance.currentUser.value;
      addTearDown(() => AuthSignals.instance.currentUser.value = prevUser);

      AuthSignals.instance.currentUser.value = UserModel(
        id: 77,
        username: 'tech77',
        fname: 'Alex',
        lname: 'Rivera',
        email: 'alex77@example.com',
      );

      final db = AppDatabase.forTesting();
      final jobApi = _TimingRecordingJobApi();
      final soApi = _TimingRecordingServiceOrdersApi();
      final jobsSignals = JobsSignals(
        JobRepository(
          db.jobOrdersDao,
          api: jobApi,
          timingHistory: db.workTimingHistoryDao,
        ),
      );
      final soSignals = ServiceOrdersSignals(
        api: soApi,
        dao: db.serviceOrdersDao,
        timingHistory: db.workTimingHistoryDao,
      );
      jobsSignals.setTechnicianEmail('alex77@example.com');
      soSignals.setTechnicianEmail('alex77@example.com');
      addTearDown(() async {
        await jobsSignals.dispose();
        soSignals.dispose();
        await db.close();
      });

      final job = JobOrderDto(
        id: 701,
        ticketNumber: 'SF-701',
        customerName: 'Job Customer 701',
        address: '701 Fiber Rd',
        status: 'Scheduled',
        assignedEmail: 'alex77@example.com',
      );
      const order = ServiceOrderDto(
        id: 801,
        accountNumber: 'ACC-801',
        fullName: 'Repair Customer 801',
        contactNumber: '09170000801',
        emailAddress: 'r801@example.com',
        address: '801 Repair Ln',
        concern: 'No Connection',
        supportStatus: 'Open',
        assignedEmail: 'alex77@example.com',
      );

      await tester.runAsync(() async {
        await db.jobOrdersDao.insertOrUpdateJob(job, synced: true);
        await db.serviceOrdersDao.insertOrUpdateOrder(order, synced: true);

        // Session 1 on Job 701: Start -> Finish
        await jobsSignals.startJob(job);
        final jStarted1 = (await db.jobOrdersDao.getJobById(701))!;
        await jobsSignals.finishJob(jStarted1);
        final jFinished1 = (await db.jobOrdersDao.getJobById(701))!;
        expect(jFinished1.workTimingStatus, WorkTimingStatus.finished);

        // Session 2 on Job 701: Start Again -> Finish
        await jobsSignals.startJob(jFinished1);
        final jStarted2 = (await db.jobOrdersDao.getJobById(701))!;
        expect(jStarted2.workTimingStatus, WorkTimingStatus.inProgress);
        await jobsSignals.finishJob(jStarted2);

        // Session 1 on Service Order 801: Start -> Stop
        await soSignals.startOrder(order);
        final oStarted = (await db.serviceOrdersDao.getOrderById(801))!;
        expect(oStarted.workTimingStatus, WorkTimingStatus.inProgress);
        await soSignals.finishOrder(oStarted);

        // Also seed a session from another userId and another date to verify strict userId + date filtering.
        await db.workTimingHistoryDao.recordStart(
          orderType: WorkTimingEntry.orderTypeJobOrder,
          orderId: 999,
          orderReference: 'SF-999',
          customerName: 'Other User Job',
          userId: '88',
          startTime: DateTime.now().toUtc(),
          isSynced: true,
        );
        await db.workTimingHistoryDao.recordStart(
          orderType: WorkTimingEntry.orderTypeServiceOrder,
          orderId: 998,
          orderReference: 'SO-0998',
          customerName: 'Yesterday Repair',
          userId: '77',
          startTime: DateTime.now().toUtc().subtract(const Duration(days: 2)),
          isSynced: true,
        );
      });

      expect(jobApi.created.length, 2);
      expect(jobApi.updated.length, 2);
      expect(soApi.created.length, 1);
      expect(soApi.updated.length, 1);

      final todayKey = formatTimingDateKey(DateTime.now());
      final todayForUser77 = await tester.runAsync(() => db.workTimingHistoryDao
          .getByUserAndDate(userId: '77', workDate: todayKey));
      expect(todayForUser77!.length, 3);
      expect(todayForUser77.any((e) => e.orderReference == 'SF-999'), isFalse);
      expect(todayForUser77.any((e) => e.orderReference == 'SO-0998'), isFalse);

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(402, 950);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: WorkTimingHistoryScreen(dao: db.workTimingHistoryDao),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pumpAndSettle();

      expect(find.text('User ID: 77 · Alex Rivera'), findsOneWidget);
      expect(find.text('SF-701'), findsNWidgets(2));
      expect(find.text('SO-0801'), findsOneWidget);
      expect(find.text('Other User Job'), findsNothing);
      expect(find.text('Yesterday Repair'), findsNothing);

      // Filter to Service Orders only.
      await tester
          .tap(find.byKey(const ValueKey('timing_history_type_service')));
      await tester.pumpAndSettle();
      expect(find.text('SO-0801'), findsOneWidget);
      expect(find.text('SF-701'), findsNothing);

      // Switch to All Dates -> Yesterday Repair appears for User ID 77 (Other User Job stays hidden).
      await tester
          .tap(find.byKey(const ValueKey('timing_history_filter_all_dates')));
      await tester.pumpAndSettle();
      expect(find.text('SO-0801'), findsOneWidget);
      expect(find.text('SO-0998'), findsOneWidget);
      expect(find.text('Other User Job'), findsNothing);
    });

    testWidgets(
        'ServiceOrderCard shares Job Order StatusRailRow anatomy, expands/collapses, uses Stop label, and renders cleanly at 200% text scale',
        (tester) async {
      final api = _TimingRecordingServiceOrdersApi();
      final signals = ServiceOrdersSignals(api: api);
      signals.setTechnicianEmail('tech@example.com');
      addTearDown(signals.dispose);

      const order = ServiceOrderDto(
        id: 305,
        accountNumber: 'ACC-305',
        fullName: 'Carlos Mendoza',
        contactNumber: '09173053050',
        emailAddress: 'carlos@example.com',
        address: '305 Rizal Blvd',
        lcp: 'LCP-10',
        nap: 'NAP-04',
        port: 'Port 2',
        concern: 'High Loss',
        priorityLevel: 'Normal',
        supportStatus: 'Open',
        assignedEmail: 'tech@example.com',
      );
      signals.allOrders.value = [order];

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(402, 950);
      addTearDown(tester.view.reset);

      final overflows = <String>[];
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) {
          overflows.add(msg);
        } else {
          origOnError?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = origOnError);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ServiceOrderCard(order: order, signals: signals),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();

      // Uses StatusRailRow with 4 actions and collapsed secondary details.
      expect(find.byType(StatusRailRow), findsOneWidget);
      expect(find.text('SO-0305 (ACC-305)'), findsOneWidget);
      expect(find.text('305 Rizal Blvd'), findsNothing);
      expect(find.text('NAVIGATE'), findsOneWidget);
      expect(find.text('CALL'), findsOneWidget);
      expect(find.text('SMS'), findsOneWidget);
      expect(find.text('DETAILS'), findsOneWidget);

      // Expand chevron reveals address & plant specs.
      await tester
          .tap(find.byKey(const ValueKey('service_order_expand_toggle_305')));
      await tester.pumpAndSettle();
      expect(find.text('305 Rizal Blvd'), findsOneWidget);
      expect(
          find.text('LCP LCP-10 · NAP NAP-04 · PORT Port 2'), findsOneWidget);

      // Start -> shows Stop label; Stop -> shows Start Again label.
      final soStartBtn =
          find.byKey(const ValueKey('service_order_start_button_305'));
      await tester.ensureVisible(soStartBtn);
      await tester.tap(soStartBtn);
      await tester.pumpAndSettle();
      expect(find.text('Stop'), findsOneWidget);

      final soStopBtn =
          find.byKey(const ValueKey('service_order_finish_button_305'));
      await tester.ensureVisible(soStopBtn);
      await tester.tap(soStopBtn);
      await tester.pumpAndSettle();
      expect(find.text('Start Again'), findsOneWidget);
      expect(overflows, isEmpty, reason: overflows.join('\n'));
    });
  });
}
