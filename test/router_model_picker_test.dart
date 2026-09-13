import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/core/widgets/searchable_picker_sheet.dart';
import 'package:swithfiber_tech_ps/features/catalogs/models/catalog_model.dart';
import 'package:swithfiber_tech_ps/features/catalogs/services/catalog_service.dart';
import 'package:swithfiber_tech_ps/features/catalogs/widgets/router_model_picker.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/reports/screens/create_report_screen.dart';
import 'package:swithfiber_tech_ps/features/reports/signals/report_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';

/// The ONT model is picked from the same searchable sheet as the NAP box, on
/// the completion report and on the repair form, because the approved
/// catalog keeps growing.
class _QuietApi implements JobOrdersApi {
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
  test('a model the catalog no longer lists is offered first', () {
    final options = RouterModelPicker.options(
        CatalogService.fallbackRouters, 'ZTE F609 (legacy)');
    expect(options.first.compactName, 'ZTE F609 (legacy)');
    expect(options.length, CatalogService.fallbackRouters.length + 1);

    // A catalog model, or nothing, adds no extra row.
    expect(
        RouterModelPicker.options(CatalogService.fallbackRouters, 'ZTE F670L'),
        CatalogService.fallbackRouters);
    expect(RouterModelPicker.options(CatalogService.fallbackRouters, ''),
        CatalogService.fallbackRouters);
  });

  group('completion report', () {
    late AppDatabase db;
    late JobsSignals jobs;
    late ReportSignals report;

    Future<void> pumpReport(WidgetTester tester) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(402 * 3.0, 874 * 3.0);
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        db = AppDatabase(NativeDatabase.memory());
        jobs = JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietApi()));
        await db.jobOrdersDao.insertAllJobs([
          JobOrderDto(
            id: 1,
            ticketNumber: 'SF-1',
            customerName: 'Subscriber One',
            address: 'Lot 1',
            status: 'Scheduled',
          ).toCompanion(),
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

    testWidgets('the ONT model opens a searchable sheet and filters as typed',
        (tester) async {
      await pumpReport(tester);
      final field = find.byKey(const ValueKey('router_model_field'));
      await tester.scrollUntilVisible(field, 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(report.routerModel.value, 'Huawei 5v5');

      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.byType(SearchablePickerSheet<RouterDto>), findsOneWidget);
      expect(find.text(RouterModelPicker.title), findsOneWidget);
      expect(find.text('ZTE F670L'), findsOneWidget);
      expect(find.text('UT-KING UT-XP6486-S'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, RouterModelPicker.searchHint), 'zte');
      await tester.pumpAndSettle();
      expect(find.text('ZTE F670L'), findsOneWidget);
      expect(find.text('UT-KING UT-XP6486-S'), findsNothing);

      await tester.tap(find.text('ZTE F670L'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchablePickerSheet<RouterDto>), findsNothing);
      expect(report.routerModel.value, 'ZTE F670L');
      expect(find.text('ZTE F670L'), findsOneWidget,
          reason: 'the field shows what was picked');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a search with no match says so instead of a blank sheet',
        (tester) async {
      await pumpReport(tester);
      final field = find.byKey(const ValueKey('router_model_field'));
      await tester.scrollUntilVisible(field, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, RouterModelPicker.searchHint),
          'nokia');
      await tester.pumpAndSettle();
      expect(find.text('No model matching "nokia"'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('repair form', () {
    ServiceOrderDto order({required int id, String? routerModel}) =>
        ServiceOrderDto(
          id: id,
          accountNumber: '9944946819',
          fullName: 'Repair Subscriber',
          contactNumber: '09171234567',
          emailAddress: 'repair@example.com',
          address: 'Lot 1, Fiber Street',
          concern: 'No Internet',
          priorityLevel: 'Urgent',
          routerModel: routerModel,
        );

    Future<void> pumpDetail(WidgetTester tester, ServiceOrderDto o) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(402 * 3.0, 874 * 3.0);
      addTearDown(tester.view.reset);
      final signals = ServiceOrdersSignals();
      signals.allOrders.value = [o];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ServiceOrderDetailScreen(orderId: o.id, signals: signals),
      ));
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 300));
    }

    // The detail screen keeps a catalog request in flight against the
    // network, so settle by elapsed time rather than pumpAndSettle.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('the replacement model is the same searchable sheet',
        (tester) async {
      await pumpDetail(tester, order(id: 1, routerModel: 'ZTE F609 (legacy)'));
      final field = find.byKey(const ValueKey('router_model_field'));
      Finder inField(String text) =>
          find.descendant(of: field, matching: find.text(text));
      await tester.scrollUntilVisible(field, 300,
          scrollable: find.byType(Scrollable).first);
      // The sticky Complete bar pins the bottom of the screen, so the field
      // must sit fully above it before its centre can be tapped.
      await tester.ensureVisible(field);
      await settle(tester);
      expect(inField('ZTE F609 (legacy)'), findsOneWidget);

      await tester.tap(field);
      await settle(tester);
      expect(find.text(RouterModelPicker.title), findsOneWidget);
      // The legacy model leads the list so it stays selectable.
      expect(find.text('ZTE F609 (legacy)'), findsWidgets);

      await tester.enterText(
          find.widgetWithText(TextField, RouterModelPicker.searchHint),
          'huawei');
      await settle(tester);
      await tester.tap(find.text('Huawei 5v5'));
      await settle(tester);
      expect(find.text(RouterModelPicker.title), findsNothing);
      expect(inField('Huawei 5v5'), findsOneWidget);
      expect(inField('ZTE F609 (legacy)'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
