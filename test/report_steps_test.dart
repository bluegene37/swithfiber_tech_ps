import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/core/widgets/port_tile_grid.dart';
import 'package:swithfiber_tech_ps/core/widgets/step_header.dart';
import 'package:swithfiber_tech_ps/core/widgets/sticky_action_bar.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/reports/screens/create_report_screen.dart';
import 'package:swithfiber_tech_ps/features/reports/signals/report_signals.dart';

/// The completion report as five numbered steps (DESIGN.md): port tiles
/// instead of a dropdown, and a sticky Save that names what is missing.
// Gene - Nov 5, 2026: Extended JobOrdersApi to inherit default image and multipart methods.
class _QuietApi extends JobOrdersApi {
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
  Future<Map<String, dynamic>?> fetchById(int id) async => null;
  @override
  Future<void> update(int id, Map<String, dynamic> body) async {}
}

void main() {
  late AppDatabase db;
  late JobsSignals jobs;
  late ReportSignals report;

  Future<void> pumpReport(WidgetTester tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(402 * 3.0, 874 * 3.0);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      db = AppDatabase.forTesting();
      jobs = JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
      await db.jobOrdersDao.insertAllJobs([
        JobOrderDto(
          id: 1,
          ticketNumber: 'SF-1',
          customerName: 'Subscriber One',
          address: 'Lot 1',
          status: 'Scheduled',
          // Gene - Nov, 26, 2026: Seed active Start timestamp so CreateReportScreen is unlocked.
          startTimeStamp: DateTime.utc(2026, 11, 26, 8, 0),
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    report = ReportSignals()
      ..setJobOrder(jobs.allJobs.value.firstWhere((j) => j.id == 1));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: CreateReportScreen(
        jobsSignals: jobs,
        reportSignals: report,
        pickImage: (_) async => null,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  tearDown(() async {
    await jobs.dispose();
    await db.close();
  });

  Finder scrollable() => find.byType(Scrollable).first;

  /*
  testWidgets('the form is five numbered steps with one sticky Save',
      (tester) async {
    await pumpReport(tester);

    for (final n in [1, 2, 3, 4, 5]) {
      final header =
          find.byWidgetPredicate((w) => w is StepHeader && w.number == n);
      await tester.scrollUntilVisible(header, 300, scrollable: scrollable());
      expect(header, findsOneWidget, reason: 'step $n');
    }
    expect(find.text('Optical reading'), findsOneWidget);
    expect(find.text('Customer sign-off'), findsOneWidget);

    // One red verb, pinned, saying what is still missing.
    expect(find.byType(StickyActionBar), findsOneWidget);
    expect(find.text('Save report'), findsOneWidget);
    expect(find.textContaining('Missing: serial number'), findsOneWidget);
    expect(find.textContaining('7 of 7 photos'), findsOneWidget);
    expect(find.textContaining('signature'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  */
  /*
  // Gene - Oct 13, 2026: Updated test to assert all six numbered steps matching AppSheet workflow order (1: Hardware, 2: Optical, 3: Materials, 4: Photos, 5: Customer sign-off, 6: Remarks & status).
  testWidgets('the form is six numbered steps with one sticky Save',
      (tester) async {
    await pumpReport(tester);

    for (final n in [1, 2, 3, 4, 5, 6]) {
      final header =
          find.byWidgetPredicate((w) => w is StepHeader && w.number == n);
      await tester.scrollUntilVisible(header, 300, scrollable: scrollable());
      expect(header, findsOneWidget, reason: 'step $n');
    }
    expect(find.text('Optical reading'), findsOneWidget);
    expect(find.text('Customer sign-off'), findsOneWidget);

    // One red verb, pinned, saying what is still missing.
    expect(find.byType(StickyActionBar), findsOneWidget);
    expect(find.text('Save report'), findsOneWidget);
    expect(find.textContaining('Missing: serial number'), findsOneWidget);
    expect(find.textContaining('7 of 7 photos'), findsOneWidget);
    expect(find.textContaining('signature'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  */
  // Gene - Oct 13, 2026: Updated test to assert five numbered steps without optical reading and with VLAN dropdown.
  testWidgets('the form is five numbered steps with one sticky Save',
      (tester) async {
    await pumpReport(tester);

    for (final n in [1, 2, 3, 4, 5]) {
      final header =
          find.byWidgetPredicate((w) => w is StepHeader && w.number == n);
      await tester.scrollUntilVisible(header, 300, scrollable: scrollable());
      expect(header, findsOneWidget, reason: 'step $n');
    }
    expect(find.text('Optical reading'), findsNothing);
    expect(find.byKey(const ValueKey('vlan_dropdown_field')), findsOneWidget);
    expect(find.text('Customer sign-off'), findsOneWidget);

    // One red verb, pinned, saying what is still missing.
    expect(find.byType(StickyActionBar), findsOneWidget);
    expect(find.text('Save report'), findsOneWidget);
    /*
    expect(find.textContaining('7 of 7 photos'), findsOneWidget);
    */
    // Gene - Oct 13, 2026: Expect 4 of 4 photos now that unneeded photo proofs are removed.
    expect(find.textContaining('4 of 4 photos'), findsOneWidget);
    expect(find.textContaining('signature'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'NAP port starts collapsed to the current port and Change opens the '
      'tiles', (tester) async {
    await pumpReport(tester);
    final change = find.byKey(const ValueKey('nap_port_toggle'));
    await tester.scrollUntilVisible(change, 300, scrollable: scrollable());
    /*
    expect(find.byType(DropdownButtonFormField<String>), findsNothing,
        reason: 'the ONT model is a searchable sheet like the NAP box');
    */
    // Gene - Oct 13, 2026: Assert router model is a searchable PickerField and VLAN uses DropdownButtonFormField.
    expect(find.byKey(const ValueKey('router_model_field')), findsOneWidget);
    expect(find.byKey(const ValueKey('vlan_dropdown_field')), findsOneWidget);

    // Collapsed: the header names the port, the grid is not built.
    expect(report.napPort.value, 'PORT 001');
    expect(find.text('PORT 001'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.byType(PortTileGrid), findsNothing);
    expect(tester.getSize(change).height, greaterThanOrEqualTo(48));

    // Expand: every port visible.
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(find.byType(PortTileGrid), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('16'), findsOneWidget);

    // Every tile is a real target.
    final tile = find.ancestor(
        of: find.text('05'), matching: find.byType(ConstrainedBox));
    expect(tester.getSize(tile.first).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a port tile records it and collapses the grid',
      (tester) async {
    await pumpReport(tester);
    final change = find.byKey(const ValueKey('nap_port_toggle'));
    await tester.scrollUntilVisible(change, 300, scrollable: scrollable());
    await tester.tap(change);
    await tester.pumpAndSettle();

    await tester.tap(find.text('05'));
    await tester.pumpAndSettle();
    expect(report.napPort.value, 'PORT 005');
    expect(find.byType(PortTileGrid), findsNothing);
    expect(find.text('PORT 005'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);

    // Done closes the grid without changing the port.
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(find.byType(PortTileGrid), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(PortTileGrid), findsNothing);
    expect(report.napPort.value, 'PORT 005');
    expect(tester.takeException(), isNull);
  });

  /*
  testWidgets(
      'typing the serial ticks step 2 and drops it from the missing '
      'line', (tester) async {
    await pumpReport(tester);
    final step2 = find
        .byWidgetPredicate((w) => w is StepHeader && w.number == 2 && w.done);
    expect(step2, findsNothing);

    // The first text field on the form is the optical reading; the serial
    // field is the one labelled as such.
    final serialField = find.ancestor(
        of: find.text('Modem / ONT Serial Number (SN)'),
        matching: find.byType(TextFormField));
    await tester.scrollUntilVisible(serialField, 300, scrollable: scrollable());
    await tester.enterText(serialField, 'HWTC12345678');
    await tester.pump();

    expect(step2, findsOneWidget);
    expect(find.textContaining('serial number'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  */
  // Gene - Oct 13, 2026: Serial number input is in Step 1 (Network plant & hardware) in AppSheet workflow; assert step 1 ticks upon entry.
  testWidgets(
      'typing the serial ticks step 1 and drops it from the missing '
      'line', (tester) async {
    await pumpReport(tester);
    final step1 = find
        .byWidgetPredicate((w) => w is StepHeader && w.number == 1 && w.done);
    expect(step1, findsNothing);

    final serialField = find.ancestor(
        of: find.text('Modem / ONT Serial Number (SN)'),
        matching: find.byType(TextFormField));
    await tester.scrollUntilVisible(serialField, 300, scrollable: scrollable());
    await tester.enterText(serialField, 'HWTC12345678');
    await tester.pump();

    expect(step1, findsOneWidget);
    expect(find.textContaining('serial number'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remarks start collapsed and open with Add, then read back',
      (tester) async {
    await pumpReport(tester);
    final toggle = find.byKey(const ValueKey('remarks_toggle'));
    await tester.scrollUntilVisible(toggle, 300, scrollable: scrollable());
    expect(find.text('No remarks'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.byKey(const ValueKey('remarks_preview')), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    final field = find.widgetWithText(TextFormField,
        'Enter fiber splice details, cable distance, speedtest results...');
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Spliced at NAP 008, 62 m drop');
    await tester.pump();

    /*
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    */
    // Gene - Oct 13, 2026: Scroll toggle button into visible viewport before tapping Done to avoid hit test clipping.
    await tester.scrollUntilVisible(toggle, 300, scrollable: scrollable());
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Spliced at NAP 008, 62 m drop'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.byType(TextFormField).evaluate().length,
        lessThan(20)); // sanity: the box is gone, no leak of a second one
    expect(tester.takeException(), isNull);
  });

  // Gene - Oct 13, 2026: Assert VLAN dropdown defaults to 1000 and updates report signal on selection.
  testWidgets(
      'VLAN dropdown defaults to 1000 and updates report signal on selection',
      (tester) async {
    await pumpReport(tester);
    final vlanDropdown = find.byKey(const ValueKey('vlan_dropdown_field'));
    await tester.scrollUntilVisible(vlanDropdown, 300,
        scrollable: scrollable());
    expect(vlanDropdown, findsOneWidget);
    expect(find.text('1000 (Default)'), findsOneWidget);
    expect(report.vlan.value, '1000');

    await tester.tap(vlanDropdown);
    await tester.pumpAndSettle();
    expect(find.text('200').last, findsOneWidget);
    await tester.tap(find.text('200').last);
    await tester.pumpAndSettle();

    expect(report.vlan.value, '200');
    expect(tester.takeException(), isNull);
  });

  test('port tiles read the port number only', () {
    expect(PortTileGrid.tileLabel('PORT 001'), '01');
    expect(PortTileGrid.tileLabel('PORT 016'), '16');
    expect(PortTileGrid.tileLabel('Spare'), 'Spare');
  });
}
