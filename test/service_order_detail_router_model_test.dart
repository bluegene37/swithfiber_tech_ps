import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';

// Regression: tapping a repair ticket showed Flutter's red error screen.
// The server sends routerModel as '' (not null); the detail screen fed that
// blank straight into the replacement-model dropdown, whose assertion
// required the value to match exactly one item. The dropdown is now a
// searchable picker sheet; the blank and legacy cases must still open.
// Found by /investigate on 2026-09-05 (owner report: "repairs list click
// broken").

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ServiceOrderDto order({required int id, String? routerModel}) =>
      ServiceOrderDto(
        id: id,
        accountNumber: '9944946819',
        fullName: 'Repair Subscriber',
        contactNumber: '09171234567',
        emailAddress: 'repair@example.com',
        address: 'Lot 1, Fiber Street, Tayuman, Binangonan',
        barangay: 'Tayuman',
        city: 'Binangonan',
        concern: 'No Internet',
        priorityLevel: 'Urgent',
        lcp: 'LCP 181',
        nap: 'NAP 004',
        routerModel: routerModel,
      );

  Future<ServiceOrdersSignals> pumpDetail(
    WidgetTester tester, {
    required List<ServiceOrderDto> orders,
    required int openId,
  }) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(402 * 3.0, 874 * 3.0);
    addTearDown(tester.view.reset);

    final signals = ServiceOrdersSignals();
    signals.allOrders.value = orders;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: ServiceOrderDetailScreen(orderId: openId, signals: signals),
    ));
    await tester.pump();
    // Let the router catalog request fail over to the bundled fallback list,
    // which is when the stored model is applied to the dropdown.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 300));
    return signals;
  }

  testWidgets('an order with a blank router model opens without an error',
      (tester) async {
    await pumpDetail(tester,
        orders: [order(id: 1, routerModel: '')], openId: 1);
    expect(tester.takeException(), isNull);
    expect(find.text('Hardware Swap / Pullout'), findsOneWidget);
    expect(find.byKey(const ValueKey('router_model_field')), findsOneWidget);
  });

  testWidgets('an order with a null router model opens without an error',
      (tester) async {
    await pumpDetail(tester, orders: [order(id: 2)], openId: 2);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('router_model_field')), findsOneWidget);
  });

  testWidgets(
      'a model the catalog no longer lists is kept and shown as selected',
      (tester) async {
    await pumpDetail(tester,
        orders: [order(id: 3, routerModel: 'ZTE F609 (legacy)')], openId: 3);
    expect(tester.takeException(), isNull);
    // Shown in the read-only header and in the replacement-model field.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('router_model_field')),
            matching: find.text('ZTE F609 (legacy)')),
        findsOneWidget,
        reason: 'what is on file stays visible instead of crashing the form');
  });
}
