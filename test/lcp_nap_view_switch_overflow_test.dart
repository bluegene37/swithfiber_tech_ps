import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/database/daos/lcp_nap_dao.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/screens/lcp_nap_list_screen.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';

/// Logical width of the OPPO CPH2483 the crews carry.
const double _screenWidth = 423.5;

/// The list/map switch on the LCP NAP screen overflowed by 1.9px on that
/// phone: each segment held an icon and a label that could not shrink, so a
/// larger font setting pushed the label past the segment on every frame.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scale in [1.0, 1.15, 1.3, 1.5]) {
    testWidgets('the list/map switch fits a 424dp phone at text scale $scale',
        (tester) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(_screenWidth * 3.0, 2400);
      addTearDown(tester.view.reset);

      final db = AppDatabase(NativeDatabase.memory());
      final signals = LcpNapSignals(LcpNapRepository(LcpNapLocationsDao(db)));
      addTearDown(() async {
        await signals.dispose();
        await db.close();
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: LcpNapListScreen(signals: signals),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull,
          reason: 'the switch overflowed at text scale $scale');
      expect(find.text('List'), findsOneWidget);
      expect(find.text('Map'), findsOneWidget);
    });
  }
}
