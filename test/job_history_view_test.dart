import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/auth/models/user_model.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/widgets/job_history_tile.dart';
import 'package:swithfiber_tech_ps/features/jobs/widgets/job_history_view.dart';

const _me = 'tech@switchfiber.ph';
final _now = DateTime(2026, 9, 2, 14);

JobOrderDto _job(
  int id,
  String email,
  String status, {
  DateTime? installed,
  String city = 'Antipolo',
}) =>
    JobOrderDto(
      id: id,
      ticketNumber: 'SF-$id',
      customerName: 'Subscriber $id',
      address: 'Lot $id, Sample St.',
      city: city,
      status: status,
      assignedEmail: email,
      dateInstalled: installed,
    );

void main() {
  late AppDatabase db;
  late JobsSignals jobsSignals;
  final auth = AuthSignals.instance;

  Future<void> seed(WidgetTester tester, List<JobOrderDto> jobs) async {
    // Database work must run in runAsync: the fake-async test zone never
    // advances Drift's stream otherwise, and allJobs would stay empty.
    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory());
      jobsSignals =
          JobsSignals(JobRepository(db.jobOrdersDao), clock: () => _now);
      await db.jobOrdersDao
          .insertAllJobs([for (final j in jobs) j.toCompanion()]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  }

  Future<void> pumpView(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: JobHistoryView(
              jobsSignals: jobsSignals,
              authSignals: auth,
            ),
          ),
        ),
      );

  tearDown(() async {
    auth.currentUser.value = null;
    await jobsSignals.dispose();
    await db.close();
  });

  testWidgets('shows history jobs, newest first, excluding scheduled',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await seed(tester, [
      _job(1, _me, 'Activated', installed: DateTime(2026, 8, 1)),
      _job(2, 'other@switchfiber.ph', 'Activated',
          installed: DateTime(2026, 8, 30)),
      _job(3, _me, 'Activated', installed: DateTime(2026, 8, 20)),
      _job(4, _me, 'Scheduled'),
    ]);
    jobsSignals.setTechnicianEmail(_me);

    await pumpView(tester);
    await tester.pumpAndSettle();

    expect(find.text('SF-2'), findsNothing,
        reason: 'assigned to another technician, so not my history');
    expect(find.text('SF-3'), findsOneWidget);
    expect(find.text('SF-1'), findsOneWidget);
    expect(find.text('SF-4'), findsNothing,
        reason: 'a job that is still scheduled is not history');

    final tiles = tester
        .widgetList<JobHistoryTile>(find.byType(JobHistoryTile))
        .map((t) => t.job.id)
        .toList();
    expect(tiles, [3, 1], reason: 'most recent activation first');
    // The date sits in the mono left column as `Aug 20` over `2026`.
    expect(find.text('Aug 20\n2026'), findsOneWidget);
    expect(find.text('ACTIVATED'), findsNWidgets(2));
    expect(find.byType(FilterChip), findsNothing,
        reason: 'status is a rail and a word, never a pill');
  });

  /// Opens the filter button labelled [button] and taps [option] in its sheet.
  Future<void> pick(WidgetTester tester, String button, String option) async {
    await tester.tap(find.widgetWithText(FilterButton, button));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('the header is one counts line and one row of filter buttons',
      (tester) async {
    await seed(tester, [
      _job(1, _me, 'Activated', installed: DateTime(2026, 9, 2, 9)),
      _job(2, _me, 'Completed',
          installed: DateTime(2026, 8, 20), city: 'Pasig'),
    ]);
    jobsSignals.setTechnicianEmail(_me);

    await pumpView(tester);
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(JobHistoryView.summaryText(
          total: 2, activated: 1, completed: 1, thisWeek: 1)),
      findsOneWidget,
    );
    // Three buttons name their current (unfiltered) values; no Reset yet.
    expect(find.widgetWithText(FilterButton, 'All statuses'), findsOneWidget);
    expect(find.widgetWithText(FilterButton, 'All time'), findsOneWidget);
    expect(find.widgetWithText(FilterButton, 'All areas'), findsOneWidget);
    expect(find.text('Reset'), findsNothing);
    for (final button in tester.widgetList(find.byType(FilterButton))) {
      expect(tester.getSize(find.byWidget(button)).height,
          greaterThanOrEqualTo(48));
    }
    // The old four-number strip is gone.
    expect(find.text('Total'), findsNothing);
    expect(find.text('This Week'), findsNothing);

    await pick(tester, 'All statuses', 'Completed');
    expect(find.widgetWithText(FilterButton, 'Completed'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('SF-1'), findsNothing);
    expect(find.text('SF-2'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterButton, 'All statuses'), findsOneWidget);
    expect(find.text('SF-1'), findsOneWidget);
  });

  testWidgets('header and rows have no overflow at 200% text on a phone',
      (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(402 * 3.0, 874 * 3.0);
    addTearDown(tester.view.reset);
    final errors = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.toString());
    addTearDown(() => FlutterError.onError = original);

    await seed(tester, [
      _job(1, _me, 'Activated', installed: DateTime(2026, 9, 2, 9)),
      _job(2, _me, 'Completed',
          installed: DateTime(2026, 8, 20), city: 'Binangonan'),
    ]);
    jobsSignals.setTechnicianEmail(_me);
    jobsSignals.setHistoryCity('Binangonan');

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: Scaffold(
          body: JobHistoryView(jobsSignals: jobsSignals, authSignals: auth),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    FlutterError.onError = original;
    tester.takeException();

    final overflows = errors.where((e) => e.contains('overflowed')).toList();
    expect(overflows, isEmpty, reason: overflows.join('\n'));
    // The filter buttons wrapped onto more than one line instead of
    // running off the right edge.
    final reset = tester.getRect(find.text('Reset'));
    final first =
        tester.getRect(find.widgetWithText(FilterButton, 'All statuses'));
    expect(reset.top, greaterThan(first.top));
  });

  testWidgets('date and area filters narrow the list and clear together',
      (tester) async {
    await seed(tester, [
      _job(1, _me, 'Activated', installed: DateTime(2026, 9, 2, 9)),
      _job(2, _me, 'Activated',
          installed: DateTime(2026, 8, 20), city: 'Pasig'),
    ]);
    jobsSignals.setTechnicianEmail(_me);

    await pumpView(tester);
    await tester.pumpAndSettle();
    expect(find.text('SF-1'), findsOneWidget);
    expect(find.text('SF-2'), findsOneWidget);

    await pick(tester, 'All time', 'Today');
    expect(find.text('SF-1'), findsOneWidget);
    expect(find.text('SF-2'), findsNothing);

    await pick(tester, 'All areas', 'Pasig');
    expect(find.text('Nothing matches'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('SF-1'), findsOneWidget);
    expect(find.text('SF-2'), findsOneWidget);
  });

  testWidgets('the status filter switches between Activated and Completed',
      (tester) async {
    await seed(tester, [
      _job(1, _me, 'Activated', installed: DateTime(2026, 9, 2, 9)),
      _job(2, _me, 'Completed',
          installed: DateTime(2026, 8, 20), city: 'Pasig'),
    ]);
    jobsSignals.setTechnicianEmail(_me);

    await pumpView(tester);
    await tester.pumpAndSettle();
    expect(find.text('SF-1'), findsOneWidget);
    expect(find.text('SF-2'), findsOneWidget);

    await pick(tester, 'All statuses', 'Activated');
    expect(find.text('SF-1'), findsOneWidget);
    expect(find.text('SF-2'), findsNothing);

    // The button now reads "Activated"; the sheet's ticked row does too, so
    // the finder targets the button explicitly.
    await tester.tap(find.widgetWithText(FilterButton, 'Activated'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(BottomSheet), matching: find.text('Completed')));
    await tester.pumpAndSettle();
    expect(find.text('SF-1'), findsNothing);
    expect(find.text('SF-2'), findsOneWidget);

    await pick(tester, 'Completed', 'All statuses');
    expect(find.text('SF-1'), findsOneWidget);
    expect(find.text('SF-2'), findsOneWidget);
  });

  testWidgets("another technician's jobs never show once my email is known",
      (tester) async {
    // A pull made before the email was known can leave other crews' rows in
    // the cache; the history must not show them.
    await seed(tester, [
      _job(1, _me, 'Activated'),
      _job(2, 'tech1@switchfiber.ph', 'Activated'),
    ]);
    jobsSignals.setTechnicianEmail(_me);

    await pumpView(tester);
    await tester.pumpAndSettle();

    expect(find.text('SF-1'), findsOneWidget);
    expect(find.text('SF-2'), findsNothing);
  });

  testWidgets('displays history jobs even when technician email is not set',
      (tester) async {
    await seed(tester, [_job(1, _me, 'Activated')]);
    jobsSignals.setTechnicianEmail('');

    await pumpView(tester);
    await tester.pumpAndSettle();

    expect(find.text('SF-1'), findsOneWidget);
  });

  testWidgets('tapping a tile opens the details in view-only mode',
      (tester) async {
    await seed(tester, [_job(1, _me, 'Activated')]);
    jobsSignals.setTechnicianEmail(_me);
    auth.currentUser.value = UserModel(id: 1, username: 'tech', email: _me);

    await pumpView(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(JobHistoryTile));
    await tester.pumpAndSettle();

    final detail =
        tester.widget<JobOrderDetailScreen>(find.byType(JobOrderDetailScreen));
    expect(detail.readOnly, isTrue);
    // The view-only note lives in the workflow card, last in the list.
    final note = find.textContaining('View only');
    await tester.scrollUntilVisible(note, 300,
        scrollable: find
            .descendant(
                of: find.byType(JobOrderDetailScreen),
                matching: find.byType(Scrollable))
            .first);
    expect(note, findsOneWidget);
    expect(find.text('Complete'), findsNothing);
    expect(find.text('Mark as Activated'), findsNothing);
    expect(find.byTooltip('Field Completion Report'), findsNothing);
    expect(find.text('Fill / Update Completion Report'), findsNothing);
  });
}
