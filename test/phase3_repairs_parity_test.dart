import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:swithfiber_tech_ps/core/services/draft_storage_service.dart';
import 'package:swithfiber_tech_ps/core/services/location_service.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/reports/widgets/signature_pad.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_orders_screen.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/widgets/service_order_card.dart';
import 'package:swithfiber_tech_ps/features/service_orders/widgets/service_orders_map_view.dart';

final _blankTile = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _OfflineTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(Uint8List.fromList(_blankTile));
}

class _TestLocationService extends LocationService {
  final Position? fixed;
  _TestLocationService(this.fixed);

  @override
  Position? get lastKnownPosition => fixed;

  @override
  Future<Position?> getCurrentPosition({
    Duration timeout = const Duration(seconds: 4),
  }) async =>
      fixed;
}

Position _pos(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 11, 23),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 0,
    );

ServiceOrderDto _order({
  required int id,
  String concern = 'No Connection',
  String priority = 'Normal',
  String? coords,
  String contactNumber = '09171234567',
  // Gene - Nov, 26, 2026: Optional startTimestamp for unlocked ServiceOrderCard action tests.
  DateTime? startTimestamp,
}) =>
    ServiceOrderDto(
      id: id,
      accountNumber: 'ACC-$id',
      fullName: 'Subscriber $id',
      contactNumber: contactNumber,
      emailAddress: 'sub$id@example.com',
      address: 'Lot $id, Rizal St',
      concern: concern,
      priorityLevel: priority,
      addressCoordinates: coords,
      startTimestamp: startTimestamp,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocationService originalLocation;
  late ServiceOrdersSignals signals;

  setUp(() {
    originalLocation = LocationService.instance;
    DraftStorageService.instance.resetForTesting();
    signals = ServiceOrdersSignals();
  });

  tearDown(() {
    LocationService.instance = originalLocation;
    DraftStorageService.instance.resetForTesting();
    signals.dispose();
  });

  group('Phase 3 Step 3.1 & 3.4b — Card Distance, SMS, Sort & Map', () {
    testWidgets(
        'Urgent ServiceOrderCard displays BOTH distance badge and SMS action',
        (tester) async {
      LocationService.instance = _TestLocationService(_pos(14.4700, 121.1950));
      final urgentOrder = _order(
        id: 101,
        priority: 'Urgent',
        coords: '14.4800, 121.1950',
        // Gene - Nov, 26, 2026: Seed active Start timestamp so SMS action is unlocked.
        startTimestamp: DateTime.utc(2026, 11, 26, 8, 0),
      );
      signals.allOrders.value = [urgentOrder];

      final launchedUrls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          if (call.method == 'launch' || call.method == 'launchUrl') {
            final url = (call.arguments as Map?)?['url']?.toString();
            if (url != null) launchedUrls.add(url);
            return true;
          }
          if (call.method == 'canLaunch') return true;
          return true;
        },
      );

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ServiceOrderCard(order: urgentOrder, signals: signals),
        ),
      ));
      await tester.pump();

      expect(find.text('URGENT'), findsOneWidget);
      expect(find.text('1.1 km'), findsOneWidget);
      expect(find.text('NAVIGATE'), findsOneWidget);
      expect(find.text('CALL'), findsOneWidget);
      expect(find.text('SMS'), findsOneWidget);

      await tester.tap(find.text('SMS'));
      await tester.pump();
      expect(
        launchedUrls.any((u) => u.startsWith('sms:') && u.contains('SO-0101')),
        isTrue,
      );
    });

    test(
        'ServiceOrdersSignals nearest sort orders mappable tickets by distance and puts unmapped last',
        () {
      LocationService.instance = _TestLocationService(_pos(14.4700, 121.1950));
      final far = _order(
        id: 1,
        priority: 'Urgent',
        coords: '14.5200, 121.1950',
      );
      final near = _order(
        id: 2,
        priority: 'Normal',
        coords: '14.4710, 121.1950',
      );
      final unmapped = _order(id: 3, priority: 'Urgent', coords: null);
      signals.allOrders.value = [far, unmapped, near];

      // Priority mode: Urgent (3, 1) before Normal (2), descending ID.
      expect(signals.filteredOrders.value.map((o) => o.id).toList(), [3, 1, 2]);

      // Nearest mode: 2 (closest) -> 1 (far) -> 3 (unmapped last).
      signals.setSortMode(ServiceOrderSort.nearest);
      expect(signals.filteredOrders.value.map((o) => o.id).toList(), [2, 1, 3]);
    });

    testWidgets(
        'ServiceOrdersScreen toggles List <-> Map and updates filtered banner count',
        (tester) async {
      final mapped = _order(
        id: 10,
        priority: 'Urgent',
        concern: 'High Loss',
        coords: '14.4705, 121.1955',
      );
      final unmapped = _order(
        id: 11,
        priority: 'Normal',
        concern: 'Pullout',
      );
      signals.allOrders.value = [mapped, unmapped];

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: ServiceOrdersScreen(
          signals: signals,
          mapTileProvider: _OfflineTileProvider(),
        ),
      ));
      await tester.pump();

      expect(find.text('2 active repair tickets'), findsOneWidget);

      // Filtering updates banner count accurately.
      await tester.tap(find.text('Urgent').first);
      await tester.pump();
      expect(find.text('1 of 2 repair tickets'), findsOneWidget);

      // Toggle Map View.
      await tester
          .tap(find.byKey(const ValueKey('repairs_view_toggle_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ServiceOrdersMapView), findsOneWidget);
      expect(find.byKey(const ValueKey('repair_map_pin_10')), findsOneWidget);

      // Tap pin opens popup card.
      await tester.tap(find.byKey(const ValueKey('repair_map_pin_10')));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('repairs_map_popup_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('repairs_map_open_button')),
          findsOneWidget);

      // Clear Urgent filter -> unmapped ticket shows unmapped banner on Map.
      await tester.tap(find.text('All').first);
      await tester.pump();
      expect(find.byKey(const ValueKey('repairs_map_unmapped_banner')),
          findsOneWidget);
    });
  });

  group(
      'Phase 3 Steps 3.2, 3.3, 3.4 — Lockable Signature, Dynamic Materials, Chips & 2-Col Photos',
      () {
    Future<void> pumpDetail(WidgetTester tester,
        {double textScale = 1.0}) async {
      signals.allOrders.value = [
        ServiceOrderDto(
          id: 201,
          accountNumber: 'ACC-201',
          fullName: 'Subscriber 201',
          contactNumber: '09171234567',
          emailAddress: 'sub201@example.com',
          address: 'Lot 201, Rizal St',
          concern: 'No Connection',
          priorityLevel: 'Urgent',
          addressCoordinates: '14.47, 121.19',
          // Gene - Nov, 25, 2026: Seed active Start timestamp so detail editing controls are unlocked.
          startTimestamp: DateTime.utc(2026, 11, 25, 8, 0),
        ),
      ];
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(402, 915);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: ServiceOrderDetailScreen(orderId: 201, signals: signals),
        ),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets(
        'starts with locked signature pad, appends quick-remark chips, and adds dynamic catalog materials',
        (tester) async {
      await pumpDetail(tester);

      final scroller = find.byType(Scrollable).first;

      // Quick-remark chip appends to technician_remarks_field.
      final remarkChip =
          find.widgetWithText(ActionChip, 'Re-spliced drop cable');
      await tester.scrollUntilVisible(remarkChip, 300, scrollable: scroller);
      await tester.pump();
      await tester.tap(remarkChip);
      await tester.pump();
      final remarksText = tester
          .widget<TextFormField>(
              find.byKey(const ValueKey('technician_remarks_field')))
          .controller!
          .text;
      expect(remarksText, contains('Re-spliced drop cable'));

      // Quick-add Patch Cord adds catalog item + MaterialCounterRow.
      final patchChip = find.widgetWithText(ActionChip, '+ Patch Cord');
      await tester.scrollUntilVisible(patchChip, 300, scrollable: scroller);
      await tester.pump();
      await tester.tap(patchChip);
      await tester.pump();
      expect(find.text('APC-SC TO APC-SC (GREEN)'), findsOneWidget);

      // Searchable Add Other Material button opens picker.
      final addOtherBtn =
          find.byKey(const ValueKey('service_order_add_material_button'));
      await tester.scrollUntilVisible(addOtherBtn, 300, scrollable: scroller);
      expect(addOtherBtn, findsOneWidget);

      // Signature pad is locked initially until technician unlocks it.
      final unlockBtn =
          find.byKey(const ValueKey('service_order_unlock_signature_button'));
      await tester.scrollUntilVisible(unlockBtn, 300, scrollable: scroller);
      await tester.pump();
      expect(unlockBtn, findsOneWidget);
      expect(find.byType(SignaturePad), findsNothing);

      await tester.tap(unlockBtn);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('service_order_lock_signature_button')),
        200,
        scrollable: scroller,
      );
      expect(find.byType(SignaturePad), findsOneWidget);

      await tester.tap(
          find.byKey(const ValueKey('service_order_lock_signature_button')));
      await tester.pump();
      expect(find.byType(SignaturePad), findsNothing);
    });

    testWidgets(
        '2-column photo grid renders cleanly at 1.0x text scale on 402dp width',
        (tester) async {
      final overflows = <String>[];
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        final msg = details.toString();
        if (msg.contains('overflowed')) overflows.add(msg);
      };
      try {
        await pumpDetail(tester, textScale: 1.0);
        final gridFinder =
            find.byKey(const ValueKey('service_order_photos_grid'));
        await tester.scrollUntilVisible(gridFinder, 300,
            scrollable: find.byType(Scrollable).first);
        await tester.pump();

        final grid = tester.widget<GridView>(gridFinder);
        expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          2,
        );
      } finally {
        FlutterError.onError = original;
      }
      tester.takeException();
      expect(overflows, isEmpty, reason: overflows.join('\n'));
    });

    testWidgets(
        '2-column photo grid and repairs detail render with zero overflow at 2.0x text scale on 402dp width',
        (tester) async {
      final overflows = <String>[];
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        final msg = details.toString();
        if (msg.contains('overflowed')) overflows.add(msg);
      };
      try {
        await pumpDetail(tester, textScale: 2.0);
        final gridFinder =
            find.byKey(const ValueKey('service_order_photos_grid'));
        await tester.scrollUntilVisible(gridFinder, 300,
            scrollable: find.byType(Scrollable).first);
        await tester.pump();
        final grid = tester.widget<GridView>(gridFinder);
        expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          2,
        );
      } finally {
        FlutterError.onError = original;
      }
      tester.takeException();
      expect(overflows, isEmpty, reason: overflows.join('\n'));
    });
  });
}
