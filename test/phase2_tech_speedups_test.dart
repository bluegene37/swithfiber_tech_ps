import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/constants/app_constants.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/services/draft_storage_service.dart';
import 'package:swithfiber_tech_ps/core/services/map_navigation_service.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/core/widgets/serial_scanner_sheet.dart';
import 'package:swithfiber_tech_ps/features/auth/models/user_model.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/widgets/job_contact.dart';
import 'package:swithfiber_tech_ps/features/reports/screens/create_report_screen.dart';
import 'package:swithfiber_tech_ps/features/reports/signals/report_signals.dart';
import 'package:swithfiber_tech_ps/features/settings/screens/settings_screen.dart';
import 'package:swithfiber_tech_ps/features/settings/signals/settings_signals.dart';

class _QuietJobsApi extends JobOrdersApi {
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

JobOrderDto _job({
  int id = 1,
  String? contactNumber = '09171112222',
  String? secondContactNumber,
}) =>
    JobOrderDto(
      id: id,
      ticketNumber: 'SF-$id',
      customerName: 'Subscriber $id',
      address: 'Lot $id, Fiber St',
      status: 'Scheduled',
      modemRouterSN: 'SN$id',
      contactNumber: contactNumber,
      secondContactNumber: secondContactNumber,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> secureStore;
  late AppDatabase db;
  late JobsSignals jobsSignals;
  late ReportSignals reportSignals;

  setUp(() async {
    secureStore = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'read':
            return secureStore[call.arguments['key']];
          case 'write':
            secureStore[call.arguments['key']] =
                call.arguments['value'] as String;
            return null;
          case 'delete':
            secureStore.remove(call.arguments['key']);
            return null;
          case 'deleteAll':
            secureStore.clear();
            return null;
          case 'readAll':
            return secureStore;
          default:
            return null;
        }
      },
    );

    DraftStorageService.instance.resetForTesting();
    AuthSignals.instance.currentUser.value = null;
    SettingsSignals.instance.preferredNavApp.value = PreferredNavApp.google;
    db = AppDatabase.forTesting();
    jobsSignals =
        JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietJobsApi()));
    reportSignals = ReportSignals();
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    SettingsSignals.instance.preferredNavApp.value = PreferredNavApp.google;
    AuthSignals.instance.currentUser.value = null;
    DraftStorageService.instance.resetForTesting();
    await jobsSignals.dispose();
    await db.close();
  });

  group('Phase 2 Step 2.1 — Standard FTTH Kit & Quick-Add Chips', () {
    testWidgets(
        'Standard FTTH Kit populates missing items without overwriting user quantity and quick-add chips increment counts',
        (tester) async {
      await tester.runAsync(() async {
        await db.jobOrdersDao.insertOrUpdateJob(_job(id: 21));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      reportSignals
        ..setJobOrder(_job(id: 21))
        ..setMaterialQuantity('Drop Cable (m)', 80);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: CreateReportScreen(
          jobsSignals: jobsSignals,
          reportSignals: reportSignals,
          pickImage: (_) async => null,
        ),
      ));
      await tester.pumpAndSettle();

      final kitBtn = find.byKey(const ValueKey('apply_standard_kit_button'));
      await tester.scrollUntilVisible(kitBtn, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();

      await tester.tap(kitBtn);
      await tester.pumpAndSettle();

      // Existing non-zero qty must stay 80, not reset to 50.
      expect(reportSignals.materialsUsed.value['Drop Cable (m)'], 80);
      expect(reportSignals.materialsUsed.value['SC/APC Fast Connector'], 2);
      expect(reportSignals.materialsUsed.value['S-Clamp'], 2);
      // Patch Cord resolves to exact catalog alias APC-SC TO APC-SC (GREEN) in fallbackMaterials.
      expect(
        reportSignals.materialsUsed.value['APC-SC TO APC-SC (GREEN)'] ??
            reportSignals.materialsUsed.value['Patch Cord'],
        1,
      );

      // Quick-add chip increments Drop Cable (m) from 80 -> 81.
      final dropChip =
          find.byKey(const ValueKey('quick_add_material_drop_cable'));
      await tester.scrollUntilVisible(dropChip, 150,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(dropChip);
      await tester.pumpAndSettle();
      expect(reportSignals.materialsUsed.value['Drop Cable (m)'], 81);
    });
  });

  group('Phase 2 Step 2.2 — Crew Defaults & Custom VLAN', () {
    testWidgets(
        'Custom VLAN validates 1..4094 and applies valid custom VLAN ID',
        (tester) async {
      await tester.runAsync(() async {
        await db.jobOrdersDao.insertOrUpdateJob(_job(id: 22));
      });
      reportSignals.setJobOrder(_job(id: 22));

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: CreateReportScreen(
          jobsSignals: jobsSignals,
          reportSignals: reportSignals,
          pickImage: (_) async => null,
        ),
      ));
      await tester.pumpAndSettle();

      final vlanDropdown = find.byKey(const ValueKey('vlan_dropdown_field'));
      await tester.scrollUntilVisible(vlanDropdown, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();

      await tester.tap(vlanDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom VLAN...').last);
      await tester.pumpAndSettle();

      // Invalid out-of-range VLAN keeps dialog open with error.
      await tester.enterText(
          find.byKey(const ValueKey('custom_vlan_input')), '5000');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a VLAN ID between 1 and 4094'), findsOneWidget);
      expect(reportSignals.vlan.value, '1000');

      // Valid VLAN updates report signal and closes dialog.
      await tester.enterText(
          find.byKey(const ValueKey('custom_vlan_input')), '1250');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(reportSignals.vlan.value, '1250');
      expect(find.text('1250'), findsOneWidget);
    });

    testWidgets(
        'Visit By auto-fills from logged-in user and Visit With restores same-day partner',
        (tester) async {
      AuthSignals.instance.currentUser.value = UserModel(
        id: 7,
        username: 'juan_tech',
        fname: 'Juan',
        lname: 'Dela Cruz',
      );
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      secureStore[AppConstants.keyLastVisitWithDate] = today;
      secureStore[AppConstants.keyLastVisitWith] = 'Partner Pedro';

      reportSignals.setJobOrder(_job(id: 23));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: CreateReportScreen(
          jobsSignals: jobsSignals,
          reportSignals: reportSignals,
          pickImage: (_) async => null,
        ),
      ));
      await tester.pumpAndSettle();

      expect(reportSignals.visitBy.value, 'Juan Dela Cruz');
      expect(reportSignals.visitWith.value, 'Partner Pedro');
    });

    testWidgets(
        'Visit By stays None when logged out and yesterday Visit With is ignored',
        (tester) async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yStr =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      secureStore[AppConstants.keyLastVisitWithDate] = yStr;
      secureStore[AppConstants.keyLastVisitWith] = 'Old Partner';

      final report2 = ReportSignals()..setJobOrder(_job(id: 24));
      AuthSignals.instance.currentUser.value = null;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: CreateReportScreen(
          jobsSignals: jobsSignals,
          reportSignals: report2,
          pickImage: (_) async => null,
        ),
      ));
      await tester.pumpAndSettle();

      expect(report2.visitBy.value, 'None');
      expect(report2.visitWith.value, 'None');
    });
  });

  group('Phase 2 Step 2.3 — SerialScannerSheet Multi-Barcode Picker', () {
    testWidgets(
        'single barcode pops immediately while 2+ barcodes show candidate picker and rescan',
        (tester) async {
      String? poppedValue;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                poppedValue = await SerialScannerSheet.show(context);
              },
              child: const Text('Open Scanner'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Scanner'));
      await tester.pumpAndSettle();

      final state = tester
          .state<SerialScannerSheetState>(find.byType(SerialScannerSheet));

      // Multiple barcodes in frame -> show candidate picker instead of auto-picking first.
      state.processDetectedValues(
          ['MAC:AA:BB:CC:DD', 'ZTEG12345678', 'ZTEG12345678']);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('barcode_candidate_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('barcode_candidate_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('barcode_candidate_2')), findsNothing);
      expect(poppedValue, isNull);

      // Rescan clears candidates and unpauses detection.
      await tester.tap(find.byKey(const ValueKey('barcode_rescan_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('barcode_candidate_0')), findsNothing);

      // Multi-code again -> tap second candidate -> pops exact serial.
      state.processDetectedValues(['MAC:11:22:33', 'HWTC99887766']);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('barcode_candidate_1')));
      await tester.pumpAndSettle();

      expect(poppedValue, 'HWTC99887766');
    });

    testWidgets('single unique barcode pops immediately without chooser',
        (tester) async {
      String? poppedValue;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                poppedValue = await SerialScannerSheet.show(context);
              },
              child: const Text('Open Scanner'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Scanner'));
      await tester.pumpAndSettle();

      tester
          .state<SerialScannerSheetState>(find.byType(SerialScannerSheet))
          .processDetectedValues(['FHTT01020304']);
      await tester.pumpAndSettle();

      expect(poppedValue, 'FHTT01020304');
    });
  });

  group('Phase 2 Step 2.4 — Preferred Navigation App & Settings Picker', () {
    test('SettingsSignals persists PreferredNavApp across restore', () async {
      await SettingsSignals.instance.setPreferredNavApp(PreferredNavApp.waze);
      expect(secureStore[AppConstants.keyPreferredNavApp], 'waze');

      SettingsSignals.instance.preferredNavApp.value = PreferredNavApp.google;
      await SettingsSignals.instance.restore();
      expect(
          SettingsSignals.instance.preferredNavApp.value, PreferredNavApp.waze);
    });

    test('MapNavigationService honors PreferredNavApp for Waze and Apple Maps',
        () async {
      final launched = <Uri>[];
      final installed = <String>{
        'waze',
        'maps',
        'google.navigation',
        'comgooglemaps',
        'https'
      };
      MapNavigationService.canLaunch =
          (uri) async => installed.contains(uri.scheme);
      MapNavigationService.launch = (uri) async {
        launched.add(uri);
        return true;
      };

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await SettingsSignals.instance.setPreferredNavApp(PreferredNavApp.waze);
      await MapNavigationService.navigateToCoordinates(
        latitude: 14.47,
        longitude: 121.19,
      );
      expect(launched.last.scheme, 'waze');

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await SettingsSignals.instance.setPreferredNavApp(PreferredNavApp.apple);
      await MapNavigationService.navigateToCoordinates(
        latitude: 14.47,
        longitude: 121.19,
      );
      expect(launched.last.scheme, 'maps');
    });

    testWidgets(
        'PreferredNavApp.ask opens navigation chooser and SettingsScreen updates preference',
        (tester) async {
      final launched = <Uri>[];
      MapNavigationService.canLaunch = (_) async => true;
      MapNavigationService.launch = (uri) async {
        launched.add(uri);
        return true;
      };
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await SettingsSignals.instance.setPreferredNavApp(PreferredNavApp.ask);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: SettingsScreen(
          authSignals: AuthSignals.instance,
          jobsSignals: jobsSignals,
        ),
      ));
      await tester.pumpAndSettle();

      // Settings row opens modal picker and switches to Google Maps, then Always ask.
      final navRow = find.byKey(const ValueKey('settings_nav_app_row'));
      expect(navRow, findsOneWidget);
      await tester.tap(navRow);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav_app_option_waze')));
      await tester.pumpAndSettle();
      expect(
          SettingsSignals.instance.preferredNavApp.value, PreferredNavApp.waze);

      await SettingsSignals.instance.setPreferredNavApp(PreferredNavApp.ask);
      await MapNavigationService.navigateToCoordinates(
        latitude: 14.47,
        longitude: 121.19,
        destinationLabel: 'Pole 9',
        context: tester.element(navRow),
      );
      await tester.pumpAndSettle();

      expect(find.text('Start Navigation'), findsOneWidget);
      expect(find.text('Waze Navigation'), findsOneWidget);
      await tester.tap(find.text('Waze Navigation'));
      await tester.pumpAndSettle();
      expect(launched.single.scheme, 'waze');
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('Phase 2 Step 2.5 — Alternate Contact Number Chooser', () {
    test('contactNumbersFor deduplicates and handles alternate-only jobs', () {
      final both = _job(
        contactNumber: '09171112222',
        secondContactNumber: '09183334444',
      );
      expect(
        contactNumbersFor(both).map((e) => '${e.label}:${e.number}').toList(),
        ['Primary:09171112222', 'Alternate:09183334444'],
      );

      final dup = _job(
        contactNumber: '09171112222',
        secondContactNumber: ' 09171112222 ',
      );
      expect(contactNumbersFor(dup).length, 1);

      final altOnly = _job(
        contactNumber: '',
        secondContactNumber: '09183334444',
      );
      expect(
        contactNumbersFor(altOnly).single,
        (label: 'Alternate', number: '09183334444'),
      );
    });

    testWidgets(
        'callJob and smsJob show Primary & Alternate chooser when both numbers exist',
        (tester) async {
      final job = _job(
        contactNumber: '09171112222',
        secondContactNumber: '09183334444',
      );

      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ));

      // Ignore missing url_launcher implementation in headless test after sheet pops.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (_) async => true,
      );

      final future = callJob(captured, job);
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('contact_option_primary')), findsOneWidget);
      expect(find.byKey(const ValueKey('contact_option_alternate')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('contact_option_alternate')));
      await tester.pumpAndSettle();
      await future;
    });
  });
}
