import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/core/widgets/status_rail_row.dart';

/// The action strip under a status-rail card: three equal 48dp targets that
/// stay on one row and inside the card at 200% text.
void main() {
  Widget card({VoidCallback? onCall}) => StatusRailRow(
        leading: '2.4 km',
        railColor: AppTheme.info,
        title: 'Blaine Ivory Medel',
        subtitle: '(Batingan, Binangonan, Rizal), Batingan, Binangonan',
        data: 'LCP 173 · NAP 008 · PORT 004',
        footnote: '202609051154363299355 · SwitchNet - P999',
        extra: const Text('09171234567 · long.subscriber.name@example.com'),
        statusLabel: 'Scheduled',
        onTap: () {},
        actions: [
          StatusRailAction(
              icon: Icons.navigation_rounded, label: 'Navigate', onTap: () {}),
          StatusRailAction(
              icon: Icons.call_rounded, label: 'Call', onTap: onCall),
          StatusRailAction(icon: Icons.sms_rounded, label: 'SMS', onTap: () {}),
        ],
      );

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('three actions share one row without overflow at $scale',
        (tester) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(402 * 3.0, 874 * 3.0);
      addTearDown(tester.view.reset);
      final errors = <String>[];
      final original = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d.toString());
      addTearDown(() => FlutterError.onError = original);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body:
                ListView(padding: const EdgeInsets.all(16), children: [card()]),
          ),
        ),
      ));
      await tester.pump();
      FlutterError.onError = original;
      tester.takeException();
      final overflows = errors.where((e) => e.contains('overflowed')).toList();
      expect(overflows, isEmpty, reason: overflows.join('\n'));

      final actions = find.byType(StatusRailAction);
      expect(actions, findsNWidgets(3));
      final rects = [
        for (final a in actions.evaluate())
          tester.getRect(find.byWidget(a.widget))
      ];
      for (final r in rects) {
        expect(r.height, greaterThanOrEqualTo(48));
        expect(r.width, greaterThanOrEqualTo(48));
      }
      // Side by side, not stacked: all three share the same top edge.
      expect(rects.map((r) => r.top).toSet().length, 1);
      // Labels are the uppercase 13px word, never a pill.
      expect(find.text('NAVIGATE'), findsOneWidget);
      expect(find.text('CALL'), findsOneWidget);
      expect(find.text('SMS'), findsOneWidget);
    });
  }

  testWidgets('a disabled action renders in muted ink and ignores taps',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: ListView(children: [card(onCall: null)])),
    ));
    await tester.pump();
    final call = tester.widget<Text>(find.text('CALL'));
    expect(call.style!.color,
        AppTheme.secondaryInkOf(tester.element(find.text('CALL'))));
    await tester.tap(find.text('CALL'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
