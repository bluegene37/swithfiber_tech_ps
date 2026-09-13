import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/database/daos/lcp_nap_dao.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/models/lcp_nap_model.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/screens/lcp_nap_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/screens/lcp_nap_list_screen.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';
import 'package:swithfiber_tech_ps/features/reports/widgets/optical_power_gauge.dart';
import 'package:swithfiber_tech_ps/features/toolkit/screens/fiber_color_code_tool.dart';

// Regression: ISSUE-001, 002, 008, 013, 014, 017, 018 — rows that overflowed
// or were cut short on a 402dp iPhone at the DEFAULT text size, plus the LCP
// NAP toolbar that scaled its view switch below the 13px floor at large text.
// The existing 200% sweep missed all of them: it never pumps the completion
// report gauge or the NAP detail, and its seeded job has no optical reading,
// so the job detail's optical card was never built.
// Found by /qa on 2026-09-05
// Report: .gstack/qa-reports/qa-report-switchfiber-tech-ios-simulator-2026-09-05.md

/// Logical width of the iPhone 17 Pro the QA run used.
const double _phoneWidth = 402;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps [home] on a phone-width screen at [scale] and returns every
  /// RenderFlex overflow the layout reported. Overflow is reported to
  /// FlutterError, never thrown, so a green pump alone proves nothing.
  Future<List<String>> overflowsOf(
    WidgetTester tester,
    Widget home, {
    double scale = 1.0,
    Future<void> Function(WidgetTester tester)? interact,
  }) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(_phoneWidth * 3.0, 874 * 3.0);
    addTearDown(tester.view.reset);

    final errors = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.toString());
    addTearDown(() => FlutterError.onError = original);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: home,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (interact != null) {
      await interact(tester);
      await tester.pump(const Duration(milliseconds: 400));
    }
    FlutterError.onError = original;
    tester.takeException();
    return errors.where((e) => e.contains('overflowed')).toList();
  }

  group('completion report optical gauge (ISSUE-013)', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('verdict and reading fit a card at text scale $scale',
          (tester) async {
        // 303px is what the report card leaves the gauge on the phone.
        final overflows = await overflowsOf(
          tester,
          const Scaffold(
            body: Center(
              child: SizedBox(
                width: 303,
                child: OpticalPowerGauge(opticalPowerDbm: -19.5),
              ),
            ),
          ),
          scale: scale,
        );
        expect(overflows, isEmpty, reason: overflows.join('\n'));
        expect(find.text('-19.5 dBm'), findsOneWidget);
      });
    }
  });

  group('fiber color code tool (ISSUE-017)', () {
    testWidgets('the 12-colour sequence header wraps instead of overflowing',
        (tester) async {
      final overflows = await overflowsOf(tester, const FiberColorCodeTool());
      expect(overflows, isEmpty, reason: overflows.join('\n'));
      expect(find.text('TIA-598 Standard 12-Color Sequence'), findsOneWidget);
    });
  });

  group('job order detail optical card (ISSUE-014)', () {
    late AppDatabase db;
    late JobsSignals jobs;

    tearDown(() async {
      await jobs.dispose();
      await db.close();
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('reading, standard and verdict fit at text scale $scale',
          (tester) async {
        await tester.runAsync(() async {
          db = AppDatabase(NativeDatabase.memory());
          jobs = JobsSignals(JobRepository(db.jobOrdersDao));
          await db.jobOrdersDao.insertOrUpdateJob(JobOrderDto(
            id: 3980,
            ticketNumber: '202609030028571738368',
            customerName: 'Blaine Ivory Medel',
            address: '(Batingan, Binangonan, Rizal), Batingan',
            city: 'Binangonan',
            status: 'Scheduled',
            onsiteStatus: 'Scheduled',
            // The precondition the 200% sweep never sets: an optical reading
            // is what builds the card whose row overflowed by 37px.
            opticalPower: -19.5,
            modemRouterSN: 'QA-SN-20260905',
            isSynced: true,
            updatedAt: DateTime.now(),
          ).toCompanion());
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });

        final overflows = await overflowsOf(
          tester,
          JobOrderDetailScreen(jobId: 3980, jobsSignals: jobs),
          scale: scale,
          // The optical card sits below the fold of the lazy ListView, so
          // it is only laid out (and can only overflow) once scrolled to.
          interact: (tester) => tester.dragUntilVisible(
            find.text('-19.5 dBm'),
            find.byType(ListView),
            const Offset(0, -250),
          ),
        );
        expect(overflows, isEmpty, reason: overflows.join('\n'));
        expect(find.text('-19.5 dBm'), findsOneWidget);
      });
    }
  });

  group('LCP NAP screens', () {
    late AppDatabase db;
    late LcpNapSignals signals;

    /// Real plant names: "CAR LCP 001 NAP 006" is what overflowed the
    /// detail header by 16px; the sample seed's "LCP 01 - NAP 01" is too
    /// short to show the defect.
    Future<void> seed(WidgetTester tester) async {
      await tester.runAsync(() async {
        db = AppDatabase(NativeDatabase.memory());
        final dao = LcpNapLocationsDao(db);
        signals = LcpNapSignals(LcpNapRepository(dao));
        final now = DateTime.now();
        for (var i = 1; i <= 6; i++) {
          await dao.insertOrUpdateLocation(LcpNapDto(
            id: i,
            lcp: 'CAR LCP 001',
            nap: 'NAP 00$i',
            lcpNap: 'CAR LCP 001 NAP 00$i',
            portTotal: 16,
            coordinates: '14.48296$i, 121.22168$i',
            street: 'San diego',
            region: 'Rizal',
            barangay: '63',
            city: 'Cardona',
            isSynced: true,
            updatedAt: now,
          ).toCompanion());
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
    }

    tearDown(() async {
      await signals.dispose();
      await db.close();
    });

    testWidgets('detail header fits a long NAP name (ISSUE-008)',
        (tester) async {
      await seed(tester);
      final overflows = await overflowsOf(
        tester,
        LcpNapDetailScreen(locationId: 6, signals: signals),
      );
      expect(overflows, isEmpty, reason: overflows.join('\n'));
      expect(find.text('CAR LCP 001 NAP 006'), findsWidgets);
      expect(find.text('16 ports'), findsOneWidget);
    });

    testWidgets(
        'stat chips show their unit and the filter banner its cabinet '
        '(ISSUE-001, ISSUE-002)', (tester) async {
      await seed(tester);
      signals.setLcpFilter('CAR LCP 001');
      final overflows = await overflowsOf(
        tester,
        LcpNapListScreen(signals: signals),
      );
      expect(overflows, isEmpty, reason: overflows.join('\n'));
      // The counts are one summary line under the search field now.
      expect(find.textContaining('cabinet'), findsOneWidget);
      expect(find.textContaining('NAPs'), findsWidgets);
      expect(find.textContaining('ports'), findsWidgets);
      // The banner text now owns the row's free width. Before, Flexible and
      // a Spacer split it in half and the label ended at "Cabine...".
      final banner = find.text('Filtered by Cabinet: CAR LCP 001');
      expect(banner, findsOneWidget);
      final showAll = find.text('Show All');
      // 8px gap plus the text button's own 16px padding.
      expect(tester.getRect(banner).right,
          greaterThanOrEqualTo(tester.getRect(showAll).left - 32),
          reason: 'the banner text should run right up to Show All');
    });

    testWidgets('the view switch keeps its size at large text (ISSUE-018)',
        (tester) async {
      await seed(tester);
      const scale = 1.5;
      final overflows = await overflowsOf(
        tester,
        LcpNapListScreen(signals: signals),
        scale: scale,
      );
      expect(overflows, isEmpty, reason: overflows.join('\n'));

      // getRect goes through the paint transform, so a FittedBox that had
      // shrunk the label would show up here as a short rectangle.
      // The test font is far wider than Barlow, so the FittedBox may still
      // trim a little here; what must never happen is dropping below the
      // 13px floor (which is what the old layout did, to ~7px).
      final label = tester.getRect(find.text('Map'));
      expect(label.height, greaterThanOrEqualTo(13 * scale),
          reason: 'the Map label fell below the 13px floor');

      // Stacked: the filter button sits under the switch, not beside it.
      final filter = tester.getRect(find.text('Filter LCP'));
      expect(filter.top, greaterThan(label.bottom));
    });

    testWidgets('the view switch and filter share a row at normal text',
        (tester) async {
      await seed(tester);
      final overflows = await overflowsOf(
        tester,
        LcpNapListScreen(signals: signals),
      );
      expect(overflows, isEmpty, reason: overflows.join('\n'));
      final label = tester.getRect(find.text('Map'));
      final filter = tester.getRect(find.text('Filter LCP'));
      expect(filter.left, greaterThan(label.right));
      expect((filter.center.dy - label.center.dy).abs(), lessThan(24));
    });
  });
}
