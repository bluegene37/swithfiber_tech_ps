import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/database/daos/lcp_nap_dao.dart';
import 'package:swithfiber_tech_ps/core/services/draft_storage_service.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/models/lcp_nap_model.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/screens/lcp_nap_list_screen.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/services/map_tiles.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/widgets/lcp_nap_card.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/widgets/lcp_nap_map_view.dart';
import 'package:swithfiber_tech_ps/features/reports/screens/create_report_screen.dart';
import 'package:swithfiber_tech_ps/features/reports/signals/report_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';
import 'package:swithfiber_tech_ps/features/settings/screens/settings_screen.dart';
import 'package:swithfiber_tech_ps/features/toolkit/screens/drop_cable_tool.dart';
import 'package:swithfiber_tech_ps/features/toolkit/screens/optical_budget_tool.dart';
import 'package:swithfiber_tech_ps/features/toolkit/services/bom_handoff_service.dart';

final _blankTile = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _OfflineTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(Uint8List.fromList(_blankTile));
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late JobsSignals jobsSignals;
  late LcpNapSignals lcpNapSignals;

  setUp(() {
    BomHandoffService.instance.clear();
    DraftStorageService.instance.resetForTesting();
    AuthSignals.instance.currentUser.value = null;
    db = AppDatabase.forTesting();
    jobsSignals =
        JobsSignals(JobRepository(db.jobOrdersDao, api: _QuietJobsApi()));
    lcpNapSignals = LcpNapSignals(LcpNapRepository(LcpNapLocationsDao(db)));
  });

  tearDown(() async {
    BomHandoffService.instance.clear();
    DraftStorageService.instance.resetForTesting();
    await jobsSignals.dispose();
    await lcpNapSignals.dispose();
    await db.close();
  });

  group('Phase 4 Step 4.2 — Offline Map Tile Cache Manager & UI Controls', () {
    test(
        'tilesForRadius computes deterministic tile coords and obeys maxTiles cap',
        () {
      final first = MapTiles.tilesForRadius(
        centerLat: 14.469586,
        centerLng: 121.195615,
        radiusKm: 1.5,
        zooms: const [15, 16],
        maxTiles: 120,
      );
      final second = MapTiles.tilesForRadius(
        centerLat: 14.469586,
        centerLng: 121.195615,
        radiusKm: 1.5,
        zooms: const [15, 16],
        maxTiles: 120,
      );
      expect(first, isNotEmpty);
      expect(first, equals(second));
      expect(first.every((t) => t.z >= 15 && t.x >= 0 && t.y >= 0), isTrue);

      final capped = MapTiles.tilesForRadius(
        centerLat: 14.469586,
        centerLng: 121.195615,
        radiusKm: 3.0,
        zooms: const [15, 16, 17, 18],
        maxTiles: 10,
      );
      expect(capped.length, 10);
    });

    testWidgets('SettingsScreen displays Offline Map Tiles controls',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: SettingsScreen(
          authSignals: AuthSignals.instance,
          jobsSignals: jobsSignals,
        ),
      ));
      await tester.pumpAndSettle();

      final tilesRow = find.byKey(const ValueKey('settings_map_tiles_row'));
      await tester.scrollUntilVisible(tilesRow, 300,
          scrollable: find.byType(Scrollable).first);
      expect(tilesRow, findsOneWidget);
      expect(find.text('Offline Map Tiles'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings_download_map_tiles_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings_clear_map_tiles_button')),
        findsOneWidget,
      );
    });

    testWidgets('LcpNapMapView renders Cache area button', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 700,
            child: LcpNapMapView(
              signals: lcpNapSignals,
              tileProvider: _OfflineTileProvider(),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const ValueKey('plant_cache_area_button')),
          findsOneWidget);
    });
  });

  group('Phase 4 Step 4.3 — Toolkit Drop Cable BOM -> Report Bridge', () {
    testWidgets('DropCableTool stages BOM for report import', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: const DropCableTool(),
      ));
      await tester.pumpAndSettle();

      final sendBtn = find.byKey(const ValueKey('send_bom_to_report_button'));
      await tester.ensureVisible(sendBtn);
      await tester.pumpAndSettle();
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      final staged = BomHandoffService.instance.pendingBom.value;
      expect(staged, isNotNull);
      expect(staged!.materials['Drop Cable (m)'], greaterThan(0));
    });

    testWidgets('CreateReportScreen imports staged Toolkit BOM & clears it',
        (tester) async {
      BomHandoffService.instance.stageBom(
        const {
          'Drop Cable (m)': 91,
          'SC/APC Fast Connector': 2,
          'S-Clamp': 3,
          'Patch Cord': 1,
        },
        summary: '91m drop (2 spans)',
      );

      final reportSignals = ReportSignals()
        ..setJobOrder(JobOrderDto(
          id: 401,
          ticketNumber: 'SF-401',
          customerName: 'Bom Subscriber',
          address: '10 Fiber Ave',
          status: 'Scheduled',
          modemRouterSN: 'SN401',
        ));

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: CreateReportScreen(
          jobsSignals: jobsSignals,
          reportSignals: reportSignals,
          pickImage: (_) async => null,
        ),
      ));
      await tester.pumpAndSettle();

      final importBtn = find.byKey(const ValueKey('import_toolkit_bom_button'));
      await tester.scrollUntilVisible(importBtn, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(importBtn);
      await tester.pumpAndSettle();

      expect(reportSignals.materialsUsed.value['Drop Cable (m)'], 91);
      expect(reportSignals.materialsUsed.value['SC/APC Fast Connector'], 2);
      expect(BomHandoffService.instance.pendingBom.value, isNull);
    });

    testWidgets('ServiceOrderDetailScreen also imports staged Toolkit BOM',
        (tester) async {
      BomHandoffService.instance.stageBom(
        const {'Drop Cable (m)': 75, 'Patch Cord': 1},
        summary: '75m drop',
      );
      final soSignals = ServiceOrdersSignals();
      addTearDown(soSignals.dispose);
      // Gene - Nov, 25, 2026: Seed active Start timestamp so ServiceOrderDetailScreen editing & BOM import are unlocked.
      soSignals.allOrders.value = [
        ServiceOrderDto(
          id: 402,
          accountNumber: 'ACC-402',
          fullName: 'Repair BOM User',
          contactNumber: '09171234567',
          emailAddress: 'bom@example.com',
          address: 'Lot 2',
          concern: 'No Connection',
          startTimestamp: DateTime.utc(2026, 11, 25, 8, 0),
        ),
      ];

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(402, 915);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ServiceOrderDetailScreen(orderId: 402, signals: soSignals),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 200));

      final importBtn = find.byKey(const ValueKey('import_toolkit_bom_button'));
      await tester.scrollUntilVisible(importBtn, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(importBtn);
      await tester.pump();

      expect(BomHandoffService.instance.pendingBom.value, isNull);
      expect(find.text('APC-SC TO APC-SC (GREEN)'), findsOneWidget);
    });
  });

  group('Phase 4 Step 4.4 — Plant Labels/Counts & Optical Budget Polish', () {
    test(
        'totalCabinetsCount matches groupedByLcp keys even with unassigned LCP',
        () {
      lcpNapSignals.allLocations.value = [
        LcpNapDto(
            id: 1,
            lcp: 'CAB-01',
            nap: 'NAP 001',
            lcpNap: 'CAB-01 NAP 001',
            portTotal: 8),
        LcpNapDto(
            id: 2, lcp: '', nap: 'NAP 002', lcpNap: 'NAP 002', portTotal: 16),
      ];
      expect(
        lcpNapSignals.totalCabinetsCount.value,
        lcpNapSignals.groupedByLcp.value.keys.length,
      );
      expect(lcpNapSignals.totalCabinetsCount.value, 2);
    });

    testWidgets('LcpNapCard displays NAP badge instead of LCP', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: LcpNapCard(
            location: LcpNapDto(
              id: 9,
              lcp: 'CAB-09',
              nap: 'NAP 009',
              lcpNap: 'CAB-09 NAP 009',
              portTotal: 8,
            ),
            onTap: () {},
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('NAP'), findsOneWidget);
      expect(find.text('LCP'), findsNothing);
    });

    Future<void> checkCabinetRowAtScale(
        WidgetTester tester, double scale) async {
      lcpNapSignals.allLocations.value = [
        LcpNapDto(
          id: 10,
          lcp: 'CAB-10',
          nap: 'NAP 001',
          lcpNap: 'CAB-10 NAP 001',
          portTotal: 16,
          barangay: 'San Roque',
          city: 'Binangonan',
        ),
      ];
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(402, 915);
      addTearDown(tester.view.reset);

      final overflows = <String>[];
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        final msg = details.toString();
        if (msg.contains('overflowed')) overflows.add(msg);
      };
      try {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: LcpNapListScreen(signals: lcpNapSignals),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('1 NAP · 16 ports'), findsOneWidget);
      } finally {
        FlutterError.onError = original;
      }
      expect(overflows, isEmpty, reason: 'Scale $scale: $overflows');
    }

    testWidgets(
        'LcpNapListScreen cabinet row spells out NAPs and ports at 1.0x text scale',
        (tester) => checkCabinetRowAtScale(tester, 1.0));

    testWidgets(
        'LcpNapListScreen cabinet row spells out NAPs and ports without overflow at 2.0x text scale',
        (tester) => checkCabinetRowAtScale(tester, 2.0));

    Future<void> checkOpticalToolAtScale(
        WidgetTester tester, double scale) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(402, 915);
      addTearDown(tester.view.reset);

      final overflows = <String>[];
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        final msg = details.toString();
        if (msg.contains('overflowed')) overflows.add(msg);
      };
      try {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const OpticalBudgetTool(),
          ),
        ));
        await tester.pumpAndSettle();

        final heroTextFinder = find.textContaining('dBm').first;
        final heroText = tester.widget<Text>(heroTextFinder);
        expect(heroText.maxLines, 1);
        expect(
          find.ancestor(
            of: heroTextFinder,
            matching: find.byType(FittedBox),
          ),
          findsOneWidget,
        );

        final pairsFinder = find.text('2 pairs (0.6 dB)');
        await tester.scrollUntilVisible(pairsFinder, 300,
            scrollable: find.byType(Scrollable).first);
        expect(pairsFinder, findsOneWidget);
      } finally {
        FlutterError.onError = original;
      }
      expect(overflows, isEmpty, reason: 'Scale $scale: $overflows');
    }

    testWidgets(
        'OpticalBudgetTool keeps hero RX readout single-line and full SC/APC text at 1.0x on 402dp width',
        (tester) => checkOpticalToolAtScale(tester, 1.0));

    testWidgets(
        'OpticalBudgetTool keeps hero RX readout single-line and full SC/APC text at 2.0x on 402dp width',
        (tester) => checkOpticalToolAtScale(tester, 2.0));
  });
}
