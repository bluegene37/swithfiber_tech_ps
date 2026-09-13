import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/core/widgets/status_rail_row.dart';
import 'package:swithfiber_tech_ps/core/widgets/status_stamp.dart';
import 'package:swithfiber_tech_ps/core/widgets/sticky_action_bar.dart';

/// The shared Calm Utility widgets (DESIGN.md): a status rail row, an
/// outline stamp and the sticky verb bar. Each carries its own rule.
void main() {
  Future<void> pump(WidgetTester tester, Widget child,
      {double scale = 1.0}) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(402 * 3.0, 874 * 3.0);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: child)),
      ),
    ));
    await tester.pump();
  }

  group('StatusRailRow', () {
    testWidgets('shows the rail next to one status word and is a 64dp target',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        StatusRailRow(
          leading: '2.4 km',
          railColor: AppTheme.info,
          statusInk: AppTheme.infoInk,
          title: 'Rosario Villanueva',
          subtitle: 'Tayuman, Binangonan',
          data: 'LCP 173 · NAP 008',
          statusLabel: 'Scheduled',
          onTap: () => taps++,
        ),
      );
      expect(find.text('SCHEDULED'), findsOneWidget,
          reason: 'status is a word, not only a colour');
      expect(find.text('2.4 km'), findsOneWidget);
      expect(find.text('LCP 173 · NAP 008'), findsOneWidget);
      expect(tester.getSize(find.byType(StatusRailRow)).height,
          greaterThanOrEqualTo(StatusRailRow.minHeight));
      await tester.tap(find.text('Rosario Villanueva'));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wraps a long address at 200% text without overflowing',
        (tester) async {
      await pump(
        tester,
        StatusRailRow(
          leading: '12.8 km',
          railColor: AppTheme.warning,
          statusInk: AppTheme.warningInk,
          title: 'Mark Anthony dela Cruz-Villanueva',
          subtitle: '(Batingan, Binangonan, Rizal), Batingan, Binangonan',
          statusLabel: 'Pending sync',
        ),
        scale: 2.0,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('PENDING SYNC'), findsOneWidget);
    });
  });

  testWidgets('StatusStamp is an outline with an uppercase word',
      (tester) async {
    await pump(
        tester, const StatusStamp(label: 'Scheduled', color: AppTheme.infoInk));
    expect(find.text('SCHEDULED'), findsOneWidget);
    final box = tester.widget<Container>(find.byType(Container).first);
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, isNull, reason: 'stamp, not a filled pill');
    expect(decoration.border, isNotNull);
    expect(tester.takeException(), isNull);
  });

  group('StickyActionBar', () {
    testWidgets('is a 64dp full-width primary button', (tester) async {
      var pressed = 0;
      await pump(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: StickyActionBar(
            label: 'Complete job',
            icon: Icons.check_circle_outline,
            onPressed: () => pressed++,
          ),
        ),
      );
      final button = tester.getSize(find.byType(ElevatedButton));
      expect(button.height, AppTheme.stickyBarHeight);
      expect(button.width, greaterThan(300));
      await tester.tap(find.text('Complete job'));
      expect(pressed, 1);
    });

    testWidgets('says why it is disabled instead of greying out silently',
        (tester) async {
      await pump(
        tester,
        const Align(
          alignment: Alignment.bottomCenter,
          child: StickyActionBar(
            label: 'Save report',
            why: '3 of 7 photos missing · signature missing',
          ),
        ),
      );
      expect(find.text('3 of 7 photos missing · signature missing'),
          findsOneWidget);
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
