import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_orders_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/widgets/status_change_sheet.dart';

/// A technician can mark an open job Rescheduled with a reason from a fixed
/// list, and bring it back to Scheduled. The change is written locally,
/// queued for sync, and the job stays on the Today queue.
class _RecordingApi implements JobOrdersApi {
  final List<Map<String, dynamic>> updates = [];
  Map<String, dynamic>? fetchByIdResult;
  @override
  Future<List<Map<String, dynamic>>> fetchByStatus(String status) async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchByStatusAssigned(
          {required String status, String? assignedEmail}) async =>
      [];
  @override
  Future<List<Map<String, dynamic>>> fetchByStatusDate(
          {String? status, DateTime? dateFrom, DateTime? dateTo}) async =>
      [];
  @override
  Future<Map<String, dynamic>?> fetchById(int id) async => fetchByIdResult;
  @override
  Future<void> update(int id, Map<String, dynamic> body) async {
    updates.add(body);
  }
}

JobOrderDto _job({String status = 'Scheduled', String? statusRemarks}) =>
    JobOrderDto(
      id: 42,
      ticketNumber: 'SF-2026-0042',
      customerName: 'Subscriber Santos',
      address: 'Lot 42, Fiber Street',
      status: status,
      statusRemarks: statusRemarks,
      rawJson: '{"id":42,"status":"$status","statusRemarks":""}',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _RecordingApi api;
  late JobRepository repository;
  late JobsSignals signals;

  Future<void> setUpJob(JobOrderDto job) async {
    db = AppDatabase.forTesting();
    api = _RecordingApi();
    repository = JobRepository(db.jobOrdersDao, api: api);
    signals = JobsSignals(repository);
    await db.jobOrdersDao.insertOrUpdateJob(job, synced: true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  tearDown(() async {
    await signals.dispose();
    await db.close();
  });

  test('reschedule writes the status and reason locally and sends them',
      () async {
    await setUpJob(_job());

    await repository.changeStatus(42,
        status: JobStatus.rescheduled, statusRemarks: 'No Available Slot');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final row = (await db.jobOrdersDao.getJobById(42))!;
    expect(row.status, 'Rescheduled');
    expect(row.statusRemarks, 'No Available Slot');
    expect(row.isRescheduled, isTrue);

    // The PUT replayed the record with the new status and reason.
    expect(api.updates, hasLength(1));
    expect(api.updates.single['status'], 'Rescheduled');
    expect(api.updates.single['statusRemarks'], 'No Available Slot');
    // Vital subscriber details are preserved in the payload even if rawJson had no split names
    expect(api.updates.single['firstName'], 'Subscriber');
    expect(api.updates.single['lastName'], 'Santos');
    expect(api.updates.single['address'], 'Lot 42, Fiber Street');

    // Still on the queue, counted as rescheduled, not in the history.
    expect(signals.filteredJobs.value.map((j) => j.id), [42]);
    expect(signals.rescheduledCount.value, 1);
    expect(signals.historyJobs.value, isEmpty);
  });

  test(
      'reschedule does not corrupt local details when server returns blanked names',
      () async {
    await setUpJob(_job());
    // Server responds to fetchById with blank names (as if another tech or API wiped them)
    api.fetchByIdResult = {
      'id': 42,
      'status': 'Rescheduled',
      'statusRemarks': 'No Available Slot',
      'firstName': '',
      'lastName': '',
      'address': '',
    };

    await repository.changeStatus(42,
        status: JobStatus.rescheduled, statusRemarks: 'No Available Slot');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final row = (await db.jobOrdersDao.getJobById(42))!;
    expect(row.customerName, 'Subscriber Santos');
    expect(row.address, 'Lot 42, Fiber Street');
    expect(row.status, 'Rescheduled');
  });

  test('pickNext prioritizes scheduled jobs over rescheduled jobs', () async {
    final scheduledJob = JobOrderDto(
      id: 1,
      ticketNumber: 'SF-001',
      customerName: 'Active Client',
      address: 'Active Address',
      status: 'Scheduled',
    );
    final rescheduledJob = JobOrderDto(
      id: 2,
      ticketNumber: 'SF-002',
      customerName: 'Rescheduled Client',
      address: 'Rescheduled Address',
      status: 'Rescheduled',
      statusRemarks: 'Bad Weather',
    );

    final next = JobOrdersScreen.pickNext([rescheduledJob, scheduledJob]);
    expect(next.id, 1,
        reason:
            'Active scheduled job must be prioritized over rescheduled job');
  });

  test('back to Scheduled clears the reason and preserves details', () async {
    await setUpJob(_job(status: 'Rescheduled', statusRemarks: 'Bad Weather'));

    await repository.changeStatus(42, status: JobStatus.scheduled);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final row = (await db.jobOrdersDao.getJobById(42))!;
    expect(row.status, 'Scheduled');
    expect(row.statusRemarks, '');
    expect(row.customerName, 'Subscriber Santos');
    expect(api.updates.single['statusRemarks'], '');
    expect(api.updates.single['firstName'], 'Subscriber');
    expect(api.updates.single['lastName'], 'Santos');
  });

  group('job detail', () {
    Future<void> pumpDetail(WidgetTester tester, JobOrderDto job) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(402 * 3.0, 874 * 3.0);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => setUpJob(job));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: JobOrderDetailScreen(jobId: 42, jobsSignals: signals),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets(
        'Change opens the sheet; Rescheduled reveals the reasons; Save '
        'records both and the banner shows the reason', (tester) async {
      await pumpDetail(tester, _job());
      final change = find.byKey(const ValueKey('job_status_change'));
      await tester.scrollUntilVisible(change, 300,
          scrollable: find.byType(Scrollable).first);
      // Visible is not enough: the sticky action bar covers the bottom of the
      // viewport, and with the RADIUS lookup refused at once its card is
      // shorter, which leaves the button right under that bar. Scroll on a
      // little so the tap lands on the button itself.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
      await settle(tester);
      expect(find.byKey(const ValueKey('job_exception_banner')), findsNothing);

      // Tapping Change starts the chain that ends in a database write once
      // the sheet closes. Started under real async so that write can run:
      // in the fake-async zone Drift never completes it.
      await tester.runAsync(() async {
        await tester.tap(change);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settle(tester);
      expect(find.byType(StatusChangeSheet), findsOneWidget);
      // Scheduled is ticked; no remarks yet; Save is enabled as-is.
      expect(find.byKey(const ValueKey('status_remarks_field')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('status_option_rescheduled')));
      await settle(tester);
      expect(
          find.byKey(const ValueKey('status_remarks_field')), findsOneWidget);
      expect(find.text('STATUS REMARKS'), findsOneWidget);
      for (final reason in RescheduleReasons.all) {
        expect(find.text(reason), findsOneWidget);
      }
      // No free-text box anywhere in the sheet.
      expect(
          find.descendant(
              of: find.byType(StatusChangeSheet),
              matching: find.byType(TextField)),
          findsNothing);
      final save = find.byKey(const ValueKey('status_change_save'));
      expect(tester.widget<ElevatedButton>(save).onPressed, isNull,
          reason: 'Rescheduled without a reason cannot be saved');

      await tester
          .tap(find.byKey(const ValueKey('status_reason_Not Available')));
      await settle(tester);
      expect(tester.widget<ElevatedButton>(save).onPressed, isNotNull);
      await tester.runAsync(() async {
        await tester.tap(save);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await settle(tester);

      expect(find.byType(StatusChangeSheet), findsNothing);
      final saved = await tester.runAsync(() => db.jobOrdersDao.getJobById(42));
      final row = saved!;
      expect(row.status, 'Rescheduled');
      expect(row.statusRemarks, 'Not Available');

      // The banner and the status row both read the reason back.
      final banner = find.byKey(const ValueKey('job_exception_banner'));
      await tester.scrollUntilVisible(banner, -300,
          scrollable: find.byType(Scrollable).first);
      expect(banner, findsOneWidget);
      expect(find.descendant(of: banner, matching: find.text('Not Available')),
          findsOneWidget);
      // The status row lives in the workflow card at the end of the list.
      await tester.scrollUntilVisible(change, 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Rescheduled · Not Available'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Let the confirmation snackbar's timer expire before the test ends.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a rescheduled job still offers the completion report',
        (tester) async {
      await pumpDetail(
          tester, _job(status: 'Rescheduled', statusRemarks: 'Bad Weather'));
      expect(find.text('Fill completion report'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('job_status_change')), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Rescheduled · Bad Weather'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
