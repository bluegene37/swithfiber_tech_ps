import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_orders_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/widgets/job_history_view.dart';
import 'package:swithfiber_tech_ps/features/jobs/widgets/jobs_map_view.dart';
import 'package:swithfiber_tech_ps/core/widgets/status_rail_row.dart';

/// The Today home from DESIGN.md: glance panel, the next job lifted with one
/// red Navigate, plain rows with a status word, done jobs behind a toggle,
/// search and map behind their icons. No app bar.
void main() {
  const me = 'tech@switchfiber.ph';
  late AppDatabase db;
  late JobsSignals signals;

  JobOrderDto job(
    int id,
    String name, {
    String status = 'Scheduled',
    String onsite = 'Scheduled',
    bool synced = true,
    DateTime? installed,
    String barangay = 'Batingan',
  }) =>
      JobOrderDto(
        id: id,
        ticketNumber: 'SF-2026-$id',
        customerName: name,
        address: 'Lot $id, Fiber Street',
        barangay: barangay,
        city: 'Binangonan',
        status: status,
        onsiteStatus: onsite,
        contactNumber: '09171234567',
        rawJson: '{"applicantEmailAddress": "sub$id@example.com", '
            '"secondContactNumber": "09181234567"}',
        nap: 'NAP 00$id',
        napId: id,
        assignedEmail: me,
        isSynced: synced,
        dateInstalled: installed,
        updatedAt: DateTime.now(),
      );

  Future<void> seed(WidgetTester tester, List<JobOrderDto> jobs) async {
    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory());
      signals = JobsSignals(JobRepository(db.jobOrdersDao));
      signals.setTechnicianEmail(me);
      for (final j in jobs) {
        // toCompanion takes the sync flag as its own argument.
        await db.jobOrdersDao
            .insertOrUpdateJob(j.toCompanion(synced: j.isSynced));
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
  }

  Future<void> pumpHome(WidgetTester tester,
      {double scale = 1.0, double height = 874}) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = Size(402 * 3.0, height * 3.0);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: JobOrdersScreen(jobsSignals: signals),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  tearDown(() async {
    await signals.dispose();
    await db.close();
  });

  final threeJobs = [
    job(1, 'Blaine Ivory Medel'),
    job(2, 'Rosario Villanueva', barangay: 'Tayuman'),
    job(3, 'Mark Anthony dela Cruz', synced: false, barangay: 'Pag-asa'),
    job(9, 'test test', status: 'Activated', installed: DateTime.now()),
  ];

  testWidgets('shows the day on one glance with the next job lifted',
      (tester) async {
    await seed(tester, threeJobs);
    // Tall enough that all three cards are built; the list is lazy.
    await pumpHome(tester, height: 1600);

    expect(find.byType(AppBar), findsNothing, reason: 'no app bar on Today');
    expect(find.text('3'), findsOneWidget, reason: 'hero job count');
    // Without a GPS fix the next job is the list's first; its barangay varies
    // with the list order, the counts do not.
    expect(
        find.textContaining('3 jobs · 1 done today · next '), findsOneWidget);

    // Every job is the same card with the same three actions, so the
    // technician picks freely; the nearest leads under a NEXT kicker.
    expect(find.text('NEXT'), findsOneWidget);
    expect(find.text('THEN'), findsOneWidget);
    expect(find.byType(StatusRailRow), findsNWidgets(3));
    expect(find.text('NAVIGATE'), findsNWidgets(3));
    expect(find.text('CALL'), findsNWidgets(3));
    expect(find.text('SMS'), findsNWidgets(3));
    expect(find.byType(ElevatedButton), findsNothing,
        reason: 'no red verb on the list; the sticky verb is on the detail');
    // Phone and email sit on every card with one copy button, so a number
    // can be read back to a caller without opening the job.
    expect(find.text('09171234567 · 09181234567'), findsNWidgets(3));
    expect(find.text('sub1@example.com'), findsOneWidget);
    expect(find.byTooltip('Copy contact'), findsNWidgets(3));
    // Ticket and record id together on the mono line; phone and email at
    // the same body size, each detail led by an icon.
    expect(find.text('SF-2026-1 (1)'), findsOneWidget);
    final phoneStyle = tester
        .widget<Text>(find.text('09171234567 · 09181234567').first)
        .style!
        .fontSize;
    final emailStyle =
        tester.widget<Text>(find.text('sub1@example.com')).style!.fontSize;
    expect(phoneStyle, emailStyle);
    expect(find.byIcon(Icons.location_on_outlined), findsNWidgets(3));
    expect(find.byIcon(Icons.call_outlined), findsNWidgets(3));
    expect(find.byIcon(Icons.alternate_email_rounded), findsNWidgets(3));

    // The others are rows with a status word, never a pill.
    expect(find.text('Rosario Villanueva'), findsOneWidget);
    expect(find.text('Mark Anthony dela Cruz'), findsOneWidget);
    // Two scheduled words (rows or the lifted card's stamp) and one pending.
    expect(find.text('SCHEDULED'), findsNWidgets(2));
    expect(find.text('PENDING SYNC'), findsOneWidget);
    expect(find.text('NAP 002'), findsOneWidget);
    expect(find.textContaining('saved on phone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('done jobs sit behind one toggle and open the history view',
      (tester) async {
    await seed(tester, threeJobs);
    await pumpHome(tester);
    expect(find.byType(JobHistoryView), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(JobHistoryView), findsOneWidget);
    expect(find.text('NEXT'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the map and search sit behind their icons', (tester) async {
    await seed(tester, threeJobs);
    await pumpHome(tester);

    await tester.tap(find.byTooltip('Show map'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(JobsMapView), findsOneWidget);
    await tester.tap(find.byTooltip('Show list'));
    await tester.pump();
    expect(find.byType(JobsMapView), findsNothing);

    expect(find.byType(TextField), findsNothing,
        reason: 'search is not permanent chrome');
    await tester.tap(find.byTooltip('Search jobs'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Rosario');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Rosario Villanueva'), findsOneWidget);
    expect(find.text('Blaine Ivory Medel'), findsNothing);
    expect(find.text('NEXT'), findsNothing,
        reason: 'a search shows matches in their own order, no NEXT kicker');
    expect(tester.takeException(), isNull);
  });

  testWidgets('has no overflow at 200% text on a phone', (tester) async {
    await seed(tester, threeJobs);
    final errors = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.toString());
    addTearDown(() => FlutterError.onError = original);
    await pumpHome(tester, scale: 2.0);
    FlutterError.onError = original;
    tester.takeException();
    final overflows = errors.where((e) => e.contains('overflowed')).toList();
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  });

  test('summary line reads like a foreman', () {
    expect(
      JobOrdersScreen.summaryLine(
          scheduled: 4, doneToday: 1, next: job(1, 'x', barangay: 'Tayuman')),
      '4 jobs · 1 done today · next Tayuman',
    );
    expect(
      JobOrdersScreen.summaryLine(
          scheduled: 1, doneToday: 0, next: job(1, 'x')),
      '1 job · 0 done today · next Batingan',
    );
    expect(
      JobOrdersScreen.summaryLine(scheduled: 0, doneToday: 6, next: null),
      'No scheduled jobs · 6 done today',
    );
  });
}
