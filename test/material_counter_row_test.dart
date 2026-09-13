import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/core/widgets/material_counter_row.dart';

/// The materials quantity is typeable: a technician who used 45 metres of
/// drop cable types 45 rather than tapping plus forty-five times.
void main() {
  const fieldKey = ValueKey('qty_field');
  const minusKey = ValueKey('qty_minus');
  const plusKey = ValueKey('qty_plus');

  /// A host that owns the count the way the report and repair screens do.
  Future<List<int>> pumpRow(WidgetTester tester, {int initial = 0}) async {
    final changes = <int>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            final count = changes.isEmpty ? initial : changes.last;
            return MaterialCounterRow(
              name: 'Drop Cable',
              unit: 'meters',
              count: count,
              fieldKey: fieldKey,
              minusKey: minusKey,
              plusKey: plusKey,
              onChanged: (v) => setState(() => changes.add(v)),
            );
          },
        ),
      ),
    ));
    return changes;
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(fieldKey)).controller!.text;

  testWidgets('typing a number records it without a tap per unit',
      (tester) async {
    final changes = await pumpRow(tester);
    expect(fieldText(tester), '0');

    await tester.enterText(find.byKey(fieldKey), '45');
    await tester.pump();
    expect(changes.last, 45);
    expect(fieldText(tester), '45');
    expect(tester.takeException(), isNull);
  });

  testWidgets('only digits get through, capped at five', (tester) async {
    final changes = await pumpRow(tester);

    await tester.enterText(find.byKey(fieldKey), '1a2.5');
    await tester.pump();
    expect(fieldText(tester), '125');
    expect(changes.last, 125);

    await tester.enterText(find.byKey(fieldKey), '1234567');
    await tester.pump();
    expect(fieldText(tester), '12345');
    expect(changes.last, 12345);
  });

  testWidgets('plus and minus update the field text', (tester) async {
    final changes = await pumpRow(tester, initial: 3);
    expect(fieldText(tester), '3');

    await tester.tap(find.byKey(plusKey));
    await tester.pump();
    expect(changes.last, 4);
    expect(fieldText(tester), '4');

    await tester.tap(find.byKey(minusKey));
    await tester.pump();
    expect(changes.last, 3);
    expect(fieldText(tester), '3');
  });

  testWidgets('clearing the field means zero and blur writes 0 back',
      (tester) async {
    final changes = await pumpRow(tester, initial: 12);

    await tester.enterText(find.byKey(fieldKey), '');
    await tester.pump();
    expect(changes.last, 0);
    // Left empty while editing so the next keystroke is not fighting a 0.
    expect(fieldText(tester), '');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(fieldText(tester), '0');
  });

  testWidgets('focusing selects the whole number so typing replaces it',
      (tester) async {
    await pumpRow(tester, initial: 12);
    await tester.tap(find.byKey(fieldKey));
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(fieldKey));
    final sel = field.controller!.selection;
    expect(sel.start, 0);
    expect(sel.end, 2);
  });

  testWidgets('minus is disabled at zero and buttons are 48dp', (tester) async {
    await pumpRow(tester);
    final minus = tester.widget<IconButton>(find.byKey(minusKey));
    expect(minus.onPressed, isNull);
    expect(tester.getSize(find.byKey(minusKey)).height,
        greaterThanOrEqualTo(AppTheme.minTarget));
    expect(tester.getSize(find.byKey(plusKey)).height,
        greaterThanOrEqualTo(AppTheme.minTarget));
    expect(tester.getSize(find.byKey(fieldKey)).height,
        greaterThanOrEqualTo(AppTheme.minTarget));
  });
}
