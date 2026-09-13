import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';

/// A selected filter chip must read as a highlighted choice without spending
/// the screen's one red (DESIGN.md: red is a verb). Material 3 falls back to
/// `colorScheme.secondaryContainer` for the selected fill, so the chip theme
/// carries ink-on-page explicitly, in both themes.
void main() {
  Future<ChipThemeData> chipThemeOf(
      WidgetTester tester, ThemeData theme) async {
    late ChipThemeData data;
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Builder(builder: (context) {
        data = ChipTheme.of(context);
        return const SizedBox();
      }),
    ));
    return data;
  }

  const selected = {WidgetState.selected};
  const rest = <WidgetState>{};

  testWidgets(
      'light: selected chip is ink with page text, unselected is the '
      'quiet fill with a hairline', (tester) async {
    final chips = await chipThemeOf(tester, AppTheme.lightTheme);
    expect(chips.selectedColor, AppTheme.darkSlate);
    expect(chips.selectedColor, isNot(AppTheme.primary),
        reason: 'red is reserved for the one action on the screen');
    expect(chips.backgroundColor, AppTheme.fillLight);
    final ink = chips.labelStyle!.color as WidgetStateColor;
    expect(ink.resolve(selected), AppTheme.lightBg);
    expect(ink.resolve(rest), AppTheme.secondaryInk);
    final side = chips.side as WidgetStateBorderSide;
    expect(side.resolve(rest)!.color, AppTheme.borderLight);
    expect(side.resolve(selected)!.color, AppTheme.darkSlate);
    expect(chips.shape, isA<StadiumBorder>(),
        reason: 'chips are pills; cards, buttons and inputs are not');
  });

  testWidgets('dark: selected chip inverts to white with page text',
      (tester) async {
    final chips = await chipThemeOf(tester, AppTheme.darkTheme);
    expect(chips.selectedColor, AppTheme.white);
    expect(chips.backgroundColor, AppTheme.darkInput);
    final ink = chips.labelStyle!.color as WidgetStateColor;
    expect(ink.resolve(selected), AppTheme.darkBg);
    expect(ink.resolve(rest), AppTheme.secondaryInkDark);
  });
}
