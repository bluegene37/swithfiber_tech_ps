import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_orders_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/widgets/jobs_map_view.dart';
import 'package:swithfiber_tech_ps/core/widgets/status_rail_row.dart';

/// The Today home's list/map switch, search, and the tablet master-detail
/// layout. (Updated 2026-09-06 for the Calm Utility home: the icon-and-label
/// segmented toggle became an icon button; JobCard became the lifted
/// status-rail cards with Navigate, Call and SMS on every one.)
void main() {
  Future<(AppDatabase, JobsSignals)> seed(WidgetTester tester,
      {String? coordinates, DateTime? startTimeStamp}) async {
    late final AppDatabase db;
    late final JobsSignals jobsSignals;
    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      jobsSignals = JobsSignals(JobRepository(db.jobOrdersDao));
      await db.jobOrdersDao.insertOrUpdateJob(
        JobOrderDto(
          id: 101,
          ticketNumber: 'SF-2026-101',
          customerName: 'Juan Dela Cruz',
          address: '123 Rizal St',
          barangay: 'San Isidro',
          city: 'Antipolo',
          status: 'Scheduled',
          onsiteStatus: 'Scheduled',
          contactNumber: '09171234567',
          nap: 'NAP-01',
          napId: 1,
          startTimeStamp: startTimeStamp,
          isSynced: true,
          updatedAt: DateTime.now(),
          rawJson:
              coordinates == null ? null : '{"coordinates": "$coordinates"}',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    return (db, jobsSignals);
  }

  Future<void> pumpHome(WidgetTester tester, JobsSignals signals) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: JobOrdersScreen(jobsSignals: signals),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('JobOrdersScreen toggles between list and map with one icon',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final (db, jobsSignals) =
        await seed(tester, coordinates: '14.580000, 121.170000');
    await pumpHome(tester, jobsSignals);

    // List first: the only job is one card with its three actions.
    expect(find.byType(StatusRailRow), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    /*
    expect(find.text('NAVIGATE'), findsOneWidget);
    */
    // Gene - Oct 6, 2026: Job cards start collapsed; expand to reveal action buttons.
    expect(find.byKey(const ValueKey('job_expand_toggle_101')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('job_expand_toggle_101')));
    await tester.pump();
    expect(find.text('NAVIGATE'), findsOneWidget);
    expect(find.byType(JobsMapView), findsNothing);

    await tester.tap(find.byTooltip('Show map'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(JobsMapView), findsOneWidget);
    expect(find.byType(StatusRailRow), findsNothing);

    await tester.tap(find.byTooltip('Show list'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(StatusRailRow), findsOneWidget);
    expect(find.byType(JobsMapView), findsNothing);

    await tester.runAsync(() async {
      await jobsSignals.dispose();
      await db.close();
    });
  });

  testWidgets('JobOrdersScreen shows search empty state and clears search',
      (WidgetTester tester) async {
    // Gene - Nov, 26, 2026: Seed active Start timestamp so DETAILS action unlocks tablet master-detail pane.
    final (db, jobsSignals) = await seed(
      tester,
      startTimeStamp: DateTime.utc(2026, 11, 26, 8, 0),
    );
    await pumpHome(tester, jobsSignals);

    expect(find.byType(StatusRailRow), findsOneWidget);

    await tester.tap(find.byTooltip('Search jobs'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'NonexistentSubscriber');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(StatusRailRow), findsNothing);
    expect(
        find.text('No jobs matching "NonexistentSubscriber"'), findsOneWidget);
    expect(find.text('Clear Search'), findsOneWidget);

    /*
    await tester.tap(find.text('Clear Search'));
    */
    // Gene - Nov, 28, 2026: Scroll Clear Search button into view before tapping when ActiveWorkOrderBanner shifts the scrollable empty state below the 600px test viewport.
    await tester.ensureVisible(find.text('Clear Search'));
    await tester.pump();
    await tester.tap(find.text('Clear Search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(StatusRailRow), findsOneWidget);
    expect(find.text('No jobs matching "NonexistentSubscriber"'), findsNothing);

    await tester.runAsync(() async {
      await jobsSignals.dispose();
      await db.close();
    });
  });

  testWidgets(
      'JobOrdersScreen renders adaptive master-detail layout on tablet >= 768dp',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Gene - Nov, 26, 2026: Seed active Start timestamp so DETAILS action unlocks tablet master-detail pane.
    final (db, jobsSignals) = await seed(
      tester,
      startTimeStamp: DateTime.utc(2026, 11, 26, 8, 0),
    );
    await pumpHome(tester, jobsSignals);

    expect(find.byType(StatusRailRow), findsOneWidget);
    expect(find.text('Select a Job Order'), findsOneWidget);
    expect(find.byType(JobOrderDetailScreen), findsNothing);

    /*
    await tester.tap(find.text('Juan Dela Cruz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(StatusRailRow), findsOneWidget);
    expect(find.byType(JobOrderDetailScreen), findsOneWidget);
    expect(find.text('Select a Job Order'), findsNothing);
    */
    // Gene - Oct 13, 2026: Tapping the card expands it; tapping DETAILS selects the job on tablet master-detail view.
    await tester.tap(find.text('Juan Dela Cruz'));
    await tester.pump();
    /*
    await tester.tap(find.text('DETAILS'));
    */
    // Gene - Nov, 28, 2026: Scroll expanded card DETAILS action into view before tapping when ActiveWorkOrderBanner shifts the left-pane list on 1024x768 tablet viewports.
    await tester.ensureVisible(find.text('DETAILS'));
    await tester.pump();
    await tester.tap(find.text('DETAILS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(StatusRailRow), findsOneWidget);
    expect(find.byType(JobOrderDetailScreen), findsOneWidget);
    expect(find.text('Select a Job Order'), findsNothing);

    await tester.runAsync(() async {
      await jobsSignals.dispose();
      await db.close();
    });
  });

  // Gene - Oct 3, 2026: Verifies jobStatusWord returns 'In progress' for In Progress jobs regardless of onsiteStatus.
  testWidgets('jobStatusWord displays In progress when jobStatus is inProgress',
      (WidgetTester tester) async {
    late (String, Color, Color) result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(
        builder: (context) {
          final job = JobOrderDto(
            id: 4152,
            ticketNumber: 'JO-4152',
            customerName: 'Gene 2 Medel',
            address: 'Kaysakat',
            status: 'Inprogress',
            onsiteStatus: 'Done',
          );
          result = jobStatusWord(context, job);
          return Container();
        },
      ),
    ));

    expect(result.$1, 'In progress');
  });
}
