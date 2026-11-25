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
    // Gene - Nov, 25, 2026: Optional active Start timestamp parameter for report-shortcut tests.
    DateTime? startTimeStamp,
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
        startTimeStamp: startTimeStamp,
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
      db = AppDatabase.forTesting();
      signals = JobsSignals(JobRepository(db.jobOrdersDao));
      signals.setTechnicianEmail(me);
      for (final j in jobs) {
        // insertOrUpdateJob takes the sync flag as its own argument.
        await db.jobOrdersDao.insertOrUpdateJob(j, synced: j.isSynced);
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

    /*
    // Every job is the same card with the same three actions, so the
    // technician picks freely; the nearest leads under a NEXT kicker.
    expect(find.text('NEXT'), findsOneWidget);
    expect(find.text('THEN'), findsOneWidget);
    */
    // Gene - Oct 8, 2026: Jobs are now grouped by scheduled date instead of NEXT and THEN kickers.
    final todayGroupLabel =
        JobOrdersScreen.dateGroupLabel(DateTime.now()).toUpperCase();
    expect(find.text(todayGroupLabel), findsOneWidget);
    expect(find.byType(StatusRailRow), findsNWidgets(3));
    /*
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
    */
    // Gene - Oct 6, 2026: Cards start collapsed; expanding reveals secondary contact lines and action buttons.
    expect(find.byTooltip('Expand details'), findsNWidgets(3));
    for (final toggle in find.byTooltip('Expand details').evaluate().toList()) {
      await tester.tap(find.byWidget(toggle.widget));
    }
    await tester.pump();
    /*
    expect(find.text('NAVIGATE'), findsNWidgets(3));
    expect(find.text('CALL'), findsNWidgets(3));
    expect(find.text('SMS'), findsNWidgets(3));
    */
    // Gene - Oct 13, 2026: Expanded cards show four partitioned actions in the footer including DETAILS.
    expect(find.text('NAVIGATE'), findsNWidgets(3));
    expect(find.text('CALL'), findsNWidgets(3));
    expect(find.text('SMS'), findsNWidgets(3));
    expect(find.text('DETAILS'), findsNWidgets(3));
    expect(find.byType(ElevatedButton), findsNothing,
        reason: 'no red verb on the list; the sticky verb is on the detail');
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

  // Gene - Oct 8, 2026: Verifies that jobs scheduled across multiple days are grouped under their respective date kickers.
  testWidgets('groups jobs by scheduled date under distinct date kickers',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final tomorrow = today.add(const Duration(days: 1));

    final multiDateJobs = [
      job(10, 'Today Client One', installed: today),
      job(11, 'Today Client Two', installed: today),
      job(12, 'Tomorrow Client', installed: tomorrow),
    ];

    await seed(tester, multiDateJobs);
    await pumpHome(tester, height: 1600);

    final todayLabel = JobOrdersScreen.dateGroupLabel(today).toUpperCase();
    final tomorrowLabel =
        JobOrdersScreen.dateGroupLabel(tomorrow).toUpperCase();

    expect(find.text(todayLabel), findsOneWidget);
    expect(find.text(tomorrowLabel), findsOneWidget);
    expect(find.text('Today Client One'), findsOneWidget);
    expect(find.text('Today Client Two'), findsOneWidget);
    expect(find.text('Tomorrow Client'), findsOneWidget);
  });

  // Gene - Oct 13, 2026: Verifies that tapping anywhere on the card toggles expansion instead of opening details, and that tapping DETAILS invokes onSelectJobForDetails.
  testWidgets(
      'card tap toggles expand/collapse and DETAILS button triggers details navigation',
      (tester) async {
    JobOrderDto? selectedJob;
    await seed(tester, [job(1, 'Blaine Ivory Medel')]);

    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(402 * 3.0, 1000 * 3.0);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: JobOrdersScreen(
        jobsSignals: signals,
        onSelectJobForDetails: (j) => selectedJob = j,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Gene - Oct 13, 2026: DETAILS action button at the bottom of the card is always visible.
    expect(find.text('DETAILS'), findsOneWidget);
    expect(selectedJob, isNull);

    // Initially collapsed: secondary address is not visible
    expect(
        find.text('Lot 1, Fiber Street, Batingan, Binangonan'), findsNothing);

    // Tap on the customer name on the card body
    await tester.tap(find.text('Blaine Ivory Medel'));
    await tester.pump();

    // Now expanded: secondary address is visible, but navigation was NOT triggered
    expect(
        find.text('Lot 1, Fiber Street, Batingan, Binangonan'), findsOneWidget);
    expect(find.text('DETAILS'), findsOneWidget);
    expect(selectedJob, isNull);

    // Tap DETAILS action button to navigate
    await tester.tap(find.text('DETAILS'));
    await tester.pump();

    // Navigation was triggered with the correct job
    expect(selectedJob, isNotNull);
    expect(selectedJob!.id, 1);

    // Tapping the card body again collapses the secondary address
    await tester.tap(find.text('Blaine Ivory Medel'));
    await tester.pump();
    expect(
        find.text('Lot 1, Fiber Street, Batingan, Binangonan'), findsNothing);
    expect(find.text('DETAILS'), findsOneWidget);
  });

  // Gene - Oct 13, 2026: Verifies trailing '>' shortcut button triggers onSelectJobForReport.
  testWidgets('trailing > button triggers report creation shortcut',
      (tester) async {
    JobOrderDto? reportJob;
    // Gene - Nov, 25, 2026: Seed active Start timestamp so report shortcut is unlocked on list card.
    await seed(tester, [
      job(
        1,
        'Blaine Ivory Medel',
        startTimeStamp: DateTime.utc(2026, 11, 25, 8, 0),
      ),
    ]);

    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(402 * 3.0, 1000 * 3.0);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: JobOrdersScreen(
        jobsSignals: signals,
        onSelectJobForReport: (j) => reportJob = j,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('Open report'), findsOneWidget);
    await tester.tap(find.byTooltip('Open report'));
    await tester.pump();

    expect(reportJob, isNotNull);
    expect(reportJob!.id, 1);
  });

  // Gene - Oct 13, 2026: Verifies Group By toggle switches between Date and Barangay groupings.
  testWidgets('Group By toggle switches between Date and Barangay groups',
      (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final tomorrow = today.add(const Duration(days: 1));

    // Two jobs on different dates but same barangay (Batingan)
    final jobs = [
      job(10, 'Client Today', installed: today, barangay: 'Batingan'),
      job(11, 'Client Tomorrow', installed: tomorrow, barangay: 'Batingan'),
      job(12, 'Client Other', installed: today, barangay: 'Tayuman'),
    ];

    await seed(tester, jobs);
    await pumpHome(tester, height: 1600);

    // Default: Grouped by Date
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Barangay'), findsOneWidget);

    // Switch to Group by Barangay
    await tester.tap(find.text('Barangay'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Under Barangay grouping, same barangay (Batingan) has only 1 header with count 2
    expect(find.text('Brgy. Batingan'), findsOneWidget);
    expect(find.text('2 jobs'), findsOneWidget);
    expect(find.text('Brgy. Tayuman'), findsOneWidget);
    expect(find.text('1 job'), findsOneWidget);

    // Switch back to Date
    await tester.tap(find.text('Date'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final todayLabel = JobOrdersScreen.dateGroupLabel(today).toUpperCase();
    expect(find.text(todayLabel), findsOneWidget);
  });
}
