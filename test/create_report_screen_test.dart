import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/core/utils/data_url.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/reports/screens/create_report_screen.dart';
import 'package:swithfiber_tech_ps/features/reports/signals/report_signals.dart';
// Gene - Oct 13, 2026: Import SignaturePad for signature pad widget assertions
import 'package:swithfiber_tech_ps/features/reports/widgets/signature_pad.dart';

/// Accepts every PUT so the background sync after submit completes quietly.
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

/// A real 1x1 PNG: the sign-off card renders an existing signature with
/// Image.memory, so the bytes have to decode.
final _signature = DataUrl.encode(
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

JobOrderDto _job(int id) => JobOrderDto(
      id: id,
      ticketNumber: 'SF-$id',
      customerName: 'Subscriber $id',
      address: 'Lot $id',
      status: 'Scheduled',
      modemRouterSN: 'SN$id',
    );

void main() {
  late AppDatabase db;
  late JobsSignals jobsSignals;
  late ReportSignals reportSignals;

  tearDown(() async {
    await jobsSignals.dispose();
    await db.close();
  });

  testWidgets(
      'submitting a report survives the database re-emitting the job list',
      (tester) async {
    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
      await db.jobOrdersDao.insertAllJobs([_job(1), _job(2)]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    reportSignals = ReportSignals()
      ..setJobOrder(jobsSignals.allJobs.value.firstWhere((j) => j.id == 1))
      ..setSignature(_signature);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateReportScreen(
        jobsSignals: jobsSignals,
        reportSignals: reportSignals,
        pickImage: (_) async => null,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Save report'), findsOneWidget);

    // Submit through the signals in real async rather than tapping: the
    // form is long and the submit spinner animates forever, which makes a
    // scroll-and-tap flaky. What matters is what follows: the save makes
    // the database re-emit the list while this screen is still mounted.
    await tester.runAsync(() async {
      await reportSignals.submitReport(jobsSignals.repository);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    // The dropdown used to assert here because the re-emitted list carried
    // new DTO instances that no longer equalled the selected one.
    expect(tester.takeException(), isNull);
    expect(reportSignals.submissionMessage.value, contains('saved'));

    final saved = jobsSignals.allJobs.value.firstWhere((j) => j.id == 1);
    expect(saved.isScheduled, isTrue,
        reason: 'report submit does not auto-update Job Order status');
    expect(saved.hasCompletedReport, isTrue);
    expect(saved.clientSignature, _signature);
  });

  testWidgets('the ONT model dropdown fits a narrow phone screen',
      (tester) async {
    // A 360pt-wide phone, the narrowest the crew carries.
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
      await db.jobOrdersDao.insertAllJobs([_job(1)]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    reportSignals = ReportSignals()
      ..setJobOrder(jobsSignals.allJobs.value.first)
      // The widest option is what used to burst the row.
      ..routerModel.value = 'UT-KING UT-XP6486-S';

    // Overflow reports arrive as FlutterErrors during layout. Collect them
    // all, because takeException() only ever surfaces the first.
    final errors = <String>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.toString());
    addTearDown(() => FlutterError.onError = originalOnError);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateReportScreen(
        jobsSignals: jobsSignals,
        reportSignals: reportSignals,
        pickImage: (_) async => null,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    FlutterError.onError = originalOnError;
    tester.takeException();

    // This screen has other long header rows that overflow at this width.
    // They predate this fix and are out of scope here, so look only at the
    // dropdown that was reported.
    final dropdownOverflows = errors
        .where((e) => e.contains('overflowed'))
        .where((e) => e.contains('DropdownButtonFormField'))
        .toList();

    expect(dropdownOverflows, isEmpty,
        reason: 'the ONT model dropdown sized itself to its widest menu item '
            'and burst the row it shares with the NAP port field');
  });

  testWidgets('tapping submit with missing fields displays guidance snackbar',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
      await db.jobOrdersDao.insertAllJobs([
        JobOrderDto(
          id: 1,
          ticketNumber: 'SF-1',
          customerName: 'Subscriber 1',
          address: 'Lot 1',
          status: 'Scheduled',
          modemRouterSN: '', // blank serial
        )
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    reportSignals = ReportSignals()
      ..setJobOrder(jobsSignals.allJobs.value.first);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateReportScreen(
        jobsSignals: jobsSignals,
        reportSignals: reportSignals,
        pickImage: (_) async => null,
      ),
    ));
    await tester.pumpAndSettle();

    final submitFinder = find.text('Save report');
    expect(submitFinder, findsOneWidget);

    // Scroll to submit button and tap when serial is empty
    await tester.ensureVisible(submitFinder);
    await tester.pumpAndSettle();
    await tester.tap(submitFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
        find.text('Modem / Router Serial Number is required.'), findsOneWidget);

    // Clear the first snackbar so it does not block the viewport
    ScaffoldMessenger.of(tester.element(find.byType(CreateReportScreen)))
        .clearSnackBars();
    await tester.pumpAndSettle();

    // Now enter a serial number, but leave signature empty
    final serialFinder =
        find.widgetWithText(TextFormField, 'Modem / ONT Serial Number (SN)');
    await tester.ensureVisible(serialFinder);
    await tester.pumpAndSettle();
    await tester.enterText(serialFinder, 'HWTC9999');
    await tester.pump();

    // Scroll back to submit and tap when signature is empty
    await tester.ensureVisible(submitFinder);
    await tester.pumpAndSettle();
    await tester.tap(submitFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Customer signature is required before saving report.'),
        findsOneWidget);
  });

  test('T2: ReportSignals resets routerSerial to empty string on job change',
      () {
    final signals = ReportSignals();
    expect(signals.routerSerial.value, '',
        reason: 'default routerSerial must not leak mock serial numbers');

    final jobWithSerial = JobOrderDto(
      id: 10,
      ticketNumber: 'SF-10',
      customerName: 'Customer 10',
      address: 'Lot 10',
      status: 'Scheduled',
      modemRouterSN: 'ZTE12345',
    );
    signals.setJobOrder(jobWithSerial);
    expect(signals.routerSerial.value, 'ZTE12345');

    final jobWithoutSerial = JobOrderDto(
      id: 11,
      ticketNumber: 'SF-11',
      customerName: 'Customer 11',
      address: 'Lot 11',
      status: 'Scheduled',
      modemRouterSN: null,
    );
    signals.setJobOrder(jobWithoutSerial);
    expect(signals.routerSerial.value, '',
        reason:
            'routerSerial must be reset to empty string when job has no serial');
  });

  // Gene - Oct 13, 2026: Added test verifying subscriber RADIUS / Wi-Fi username displays at the top of CreateReportScreen.
  testWidgets('displays RADIUS username at the top of the report screen',
      (tester) async {
    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final signals = ReportSignals();
    final job = JobOrderDto(
      id: 20,
      ticketNumber: 'SF-20',
      customerName: 'Maria Santos',
      address: 'Block 5 Lot 12',
      username: 'accountt0601261206',
      status: 'Scheduled',
    );
    signals.setJobOrder(job);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateReportScreen(
        jobsSignals: jobsSignals,
        reportSignals: signals,
        pickImage: (_) async => null,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('radius_username_banner')), findsOneWidget);
    expect(find.text('RADIUS / Wi-Fi Username'), findsOneWidget);
    expect(find.text('accountt0601261206'), findsOneWidget);
    expect(find.byKey(const ValueKey('copy_radius_username_button')),
        findsOneWidget);

    // Tap copy button and verify snackbar feedback
    await tester.tap(find.byKey(const ValueKey('copy_radius_username_button')));
    await tester.pump();
    expect(find.text('RADIUS username copied to clipboard'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(CreateReportScreen)))
        .clearSnackBars();
    await tester.pumpAndSettle();
  });

  // Gene - Oct 13, 2026: Added test verifying signature pad starts locked against scrolling scratches and can be unlocked.
  testWidgets(
      'signature pad starts locked against scrolling scratches and can be unlocked',
      (tester) async {
    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final signals = ReportSignals();
    final job = _job(1);
    signals.setJobOrder(job);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateReportScreen(
        jobsSignals: jobsSignals,
        reportSignals: signals,
        pickImage: (_) async => null,
      ),
    ));
    await tester.pumpAndSettle();

    // Verify locked state is visible
    final unlockFinder =
        find.byKey(const ValueKey('unlock_signature_pad_button'));
    // Gene - Oct 13, 2026: Replaced scrollUntilVisible with ensureVisible to avoid multiple Scrollables error
    // await tester.scrollUntilVisible(unlockFinder, 300);
    await tester.ensureVisible(unlockFinder);
    await tester.pumpAndSettle();
    expect(unlockFinder, findsOneWidget);
    expect(find.text('Tap to sign'), findsOneWidget);

    // Tap to unlock
    await tester.tap(unlockFinder);
    await tester.pumpAndSettle();

    // Active signature pad is now shown
    expect(find.byType(SignaturePad), findsOneWidget);
    expect(find.byKey(const ValueKey('lock_signature_pad_button')),
        findsOneWidget);

    // Tap Done to lock again
    await tester.tap(find.byKey(const ValueKey('lock_signature_pad_button')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('unlock_signature_pad_button')), findsOneWidget);
  });

  // Gene - Oct 13, 2026: Added test verifying drawing signature, saving with Done/Save to lock, and unlocking to sign again.
  testWidgets(
      'drawing signature locks when Done is tapped and can be unlocked to sign again',
      (tester) async {
    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final signals = ReportSignals();
    final job = _job(1);
    signals.setJobOrder(job);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateReportScreen(
        jobsSignals: jobsSignals,
        reportSignals: signals,
        pickImage: (_) async => null,
      ),
    ));
    await tester.pumpAndSettle();

    // Verify initially locked
    final unlockFinder =
        find.byKey(const ValueKey('unlock_signature_pad_button'));
    await tester.ensureVisible(unlockFinder);
    await tester.pumpAndSettle();
    expect(unlockFinder, findsOneWidget);

    // Tap to unlock
    await tester.tap(unlockFinder);
    await tester.pumpAndSettle();

    // SignaturePad is now displayed
    final padFinder = find.byType(SignaturePad);
    expect(padFinder, findsOneWidget);
    await tester.ensureVisible(padFinder);
    await tester.pumpAndSettle();

    // Draw a stroke on the signature pad
    await tester.timedDrag(padFinder, const Offset(50, 20),
        const Duration(milliseconds: 200));
    await tester.pump();

    // Check that Clear button is enabled after drawing ink
    final clearFinder = find.byKey(const ValueKey('clear_signature_button'));
    final clearWidget = tester.widget<TextButton>(clearFinder);
    expect(clearWidget.onPressed, isNotNull);

    // Tap Done to save and lock
    final doneFinder = find.byKey(const ValueKey('save_signature_pad_button'));
    await tester.ensureVisible(doneFinder);
    await tester.pumpAndSettle();
    await tester.tap(doneFinder);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // Signature is now locked and saved into report signals
    expect(signals.hasSignature.value, isTrue);
    expect(find.text('Signature saved · Locked'), findsOneWidget);
    expect(find.byType(SignaturePad), findsNothing);
    expect(find.byType(Image), findsWidgets);

    // Tap 'Unlock to sign' to sign again
    final unlockAgainFinder =
        find.byKey(const ValueKey('unlock_signature_pad_button'));
    await tester.ensureVisible(unlockAgainFinder);
    await tester.pumpAndSettle();
    await tester.tap(unlockAgainFinder);
    await tester.pumpAndSettle();

    // Signature was cleared and pad is unlocked again
    expect(signals.hasSignature.value, isFalse);
    expect(find.byType(SignaturePad), findsOneWidget);
  });

  // Gene - Oct 13, 2026: Added test verifying plan dropdown displays and updates on-site plan selection.
  testWidgets(
      'displays plan dropdown and allows technician to update or upgrade plan on-site',
      (tester) async {
    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final signals = ReportSignals();
    final job = JobOrderDto(
      id: 30,
      ticketNumber: 'SF-30',
      customerName: 'Juan Dela Cruz',
      address: 'Block 2 Lot 8',
      planId: 1,
      planName: 'SwitchLite - P699',
      status: 'Scheduled',
    );
    signals.setJobOrder(job);
    expect(signals.planId.value, 1);
    expect(signals.planName.value, 'SwitchLite - P699');

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateReportScreen(
        jobsSignals: jobsSignals,
        reportSignals: signals,
        pickImage: (_) async => null,
      ),
    ));
    await tester.pumpAndSettle();

    final planDropdownFinder =
        find.byKey(const ValueKey('plan_dropdown_field'));
    expect(planDropdownFinder, findsOneWidget);

    // Tap dropdown to reveal plan options
    await tester.tap(planDropdownFinder);
    await tester.pumpAndSettle();

    // Verify plans are available in dropdown menu
    expect(find.text('SwitchUltra - P1499 · ₱1499.00').last, findsOneWidget);

    // Select SwitchUltra - P1499
    await tester.tap(find.text('SwitchUltra - P1499 · ₱1499.00').last);
    await tester.pumpAndSettle();

    // Verify signal updated to upgraded plan
    expect(signals.planId.value, 5);
    expect(signals.planName.value, 'SwitchUltra - P1499');
    expect(find.textContaining('Plan updated on-site from: SwitchLite - P699'),
        findsOneWidget);
  });

  // Gene - Oct 13, 2026: Added test verifying submitReport saves upgraded plan to repository and database.
  test('submitReport saves upgraded plan into database and sync payload',
      () async {
    final testDb = AppDatabase.forTesting();
    final repo = JobRepository(testDb.jobOrdersDao, api: _QuietApi());
    final job = JobOrderDto(
      id: 55,
      ticketNumber: 'SF-55',
      customerName: 'Elena Cruz',
      address: 'Zone 4',
      planId: 1,
      planName: 'SwitchLite - P699',
      status: 'Scheduled',
    );
    // Gene - Oct 13, 2026: Use insertOrUpdateJob to seed test job
    await testDb.jobOrdersDao.insertOrUpdateJob(job);

    final signals = ReportSignals();
    signals.setJobOrder(job);
    signals.routerSerial.value = 'HWTC5555';
    signals.setSignature('data:image/png;base64,iVBORw0KGgo=');
    signals.setPlan(5, 'SwitchUltra - P1499');

    final success = await signals.submitReport(repo);
    expect(success, isTrue);

    final updated = await testDb.jobOrdersDao.getJobById(55);
    expect(updated?.planId, 5);
    expect(updated?.planName, 'SwitchUltra - P1499');

    await testDb.close();
  });

  // Gene - Oct 13, 2026: Added test verifying username shows empty when null or unassigned.
  testWidgets('shows empty when username is null or empty', (tester) async {
    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final signals = ReportSignals();
    final job = JobOrderDto(
      id: 70,
      ticketNumber: 'SF-70',
      customerName: 'Pedro Penduko',
      address: 'Sitio Bato',
      username: null,
      status: 'Scheduled',
    );
    expect(job.username, isNull);
    expect(job.radiusUsername, '');

    signals.setJobOrder(job);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateReportScreen(
        jobsSignals: jobsSignals,
        reportSignals: signals,
        pickImage: (_) async => null,
      ),
    ));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('radius_username_banner')), findsOneWidget);
    // Ticket number SF-70 should only appear once (in the ticket badge), never in username field
    expect(find.text('SF-70'), findsOneWidget);
  });

  // Gene - Oct 13, 2026: Added test verifying Connection Type dropdown renders with Fiber default, options (Fiber, Local, Antenna), and updates signal.
  testWidgets('connection type dropdown defaults to Fiber and supports Local and Antenna', (tester) async {
    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final signals = ReportSignals();
    final job = JobOrderDto(
      id: 88,
      ticketNumber: 'SF-88',
      customerName: 'Juan Dela Cruz',
      address: 'Poblacion',
      status: 'Scheduled',
    );
    expect(job.connectionType, 'Fiber');

    signals.setJobOrder(job);
    expect(signals.connectionType.value, 'Fiber');

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateReportScreen(
        jobsSignals: jobsSignals,
        reportSignals: signals,
        pickImage: (_) async => null,
      ),
    ));
    await tester.pumpAndSettle();

    final dropdownFinder = find.byKey(const ValueKey('connection_type_dropdown_field'));
    await tester.ensureVisible(dropdownFinder);
    await tester.pumpAndSettle();
    expect(dropdownFinder, findsOneWidget);
    expect(find.text('Fiber (Default)'), findsOneWidget);

    // Tap dropdown and select Local
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();

    expect(find.text('Local').last, findsOneWidget);
    expect(find.text('Antenna').last, findsOneWidget);

    await tester.tap(find.text('Local').last);
    await tester.pumpAndSettle();

    expect(signals.connectionType.value, 'Local');
  });

  // Gene - Oct 13, 2026: Added test verifying connectionType persistence through submitReport.
  test('persists connectionType to database on report submission', () async {
    final testDb = AppDatabase.forTesting();
    final repo = JobRepository(testDb.jobOrdersDao, api: _QuietApi());
    final job = JobOrderDto(
      id: 89,
      ticketNumber: 'SF-89',
      customerName: 'Maria Clara',
      address: 'Barangay 1',
      status: 'Scheduled',
    );
    await testDb.jobOrdersDao.insertAllJobs([job]);

    final signals = ReportSignals();
    signals.setJobOrder(job);
    signals.routerSerial.value = 'HWTC9999';
    signals.setSignature('data:image/png;base64,iVBORw0KGgo=');
    signals.connectionType.value = 'Antenna';

    final success = await signals.submitReport(repo);
    expect(success, isTrue);

    final updated = await testDb.jobOrdersDao.getJobById(89);
    expect(updated?.connectionType, 'Antenna');

    await testDb.close();
  });

  // Gene - Oct 13, 2026: Added test verifying Visit By and Visit With dropdowns default to None and allow technician selection.
  testWidgets(
      'visit by and visit with dropdowns default to None and allow technician selection',
      (tester) async {
    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final signals = ReportSignals();
    final job = JobOrderDto(
      id: 90,
      ticketNumber: 'SF-90',
      customerName: 'Pedro Penduko',
      address: 'Barangay 2',
      status: 'Scheduled',
    );
    expect(job.visitBy, 'None');
    expect(job.visitWith, 'None');

    signals.setJobOrder(job);
    expect(signals.visitBy.value, 'None');
    expect(signals.visitWith.value, 'None');

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateReportScreen(
        jobsSignals: jobsSignals,
        reportSignals: signals,
        pickImage: (_) async => null,
      ),
    ));
    await tester.pumpAndSettle();

    final visitByFinder =
        find.byKey(const ValueKey('visit_by_dropdown_field'));
    final visitWithFinder =
        find.byKey(const ValueKey('visit_with_dropdown_field'));

    await tester.ensureVisible(visitByFinder);
    await tester.pumpAndSettle();
    expect(visitByFinder, findsOneWidget);
    expect(visitWithFinder, findsOneWidget);

    // Both should show 'None (Default)'
    expect(find.text('None (Default)'), findsNWidgets(2));

    // Tap Visit By and select Dave Dimacali
    await tester.tap(visitByFinder);
    await tester.pumpAndSettle();

    expect(find.text('Dave Dimacali').last, findsOneWidget);
    await tester.tap(find.text('Dave Dimacali').last);
    await tester.pumpAndSettle();

    expect(signals.visitBy.value, 'Dave Dimacali');

    // Tap Visit With and select Aldrin Ian Albao
    await tester.tap(visitWithFinder);
    await tester.pumpAndSettle();

    expect(find.text('Aldrin Ian Albao').last, findsOneWidget);
    await tester.tap(find.text('Aldrin Ian Albao').last);
    await tester.pumpAndSettle();

    expect(signals.visitWith.value, 'Aldrin Ian Albao');
  });

  // Gene - Oct 13, 2026: Added test verifying visitBy and visitWith persistence through submitReport.
  test('persists visitBy and visitWith to database on report submission',
      () async {
    final testDb = AppDatabase.forTesting();
    final repo = JobRepository(testDb.jobOrdersDao, api: _QuietApi());
    final job = JobOrderDto(
      id: 91,
      ticketNumber: 'SF-91',
      customerName: 'Crisostomo Ibarra',
      address: 'San Diego',
      status: 'Scheduled',
    );
    await testDb.jobOrdersDao.insertAllJobs([job]);

    final signals = ReportSignals();
    signals.setJobOrder(job);
    signals.routerSerial.value = 'HWTC8888';
    signals.setSignature('data:image/png;base64,iVBORw0KGgo=');
    signals.visitBy.value = 'Dave Dimacali';
    signals.visitWith.value = 'Melchor Ynopia';

    final success = await signals.submitReport(repo);
    expect(success, isTrue);

    final updated = await testDb.jobOrdersDao.getJobById(91);
    expect(updated?.visitBy, 'Dave Dimacali');
    expect(updated?.visitWith, 'Melchor Ynopia');

    await testDb.close();
  });
}
