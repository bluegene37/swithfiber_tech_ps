import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/theme/app_text.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';

/// The Calm Utility scale from DESIGN.md (Typography), pinned so a stray edit
/// cannot drift a role. Sizes live only in app_theme.dart.
void main() {
  group('type scale (DESIGN.md table)', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final t = theme.textTheme;
      final name = theme.brightness.name;
      final secondary = theme.brightness == Brightness.dark
          ? AppTheme.secondaryInkDark
          : AppTheme.secondaryInk;

      test('$name the interface face is Barlow', () {
        expect(theme.textTheme.bodyMedium!.fontFamily, AppTheme.fontUi);
        expect(theme.textTheme.titleMedium!.fontFamily, AppTheme.fontUi);
      });
      test('$name displaySmall is the 44/500 mono hero clock', () {
        expect(t.displaySmall!.fontSize, 44);
        expect(t.displaySmall!.fontWeight, FontWeight.w500);
        expect(t.displaySmall!.fontFamily, AppTheme.fontMono);
      });
      test('$name headlineSmall is the 36/500 mono tabular reading', () {
        expect(t.headlineSmall!.fontSize, 36);
        expect(t.headlineSmall!.fontWeight, FontWeight.w500);
        expect(t.headlineSmall!.fontFamily, AppTheme.fontMono);
        expect(t.headlineSmall!.fontFeatures,
            contains(const FontFeature.tabularFigures()));
      });
      test('$name headlineMedium is the 24/600 headline', () {
        expect(t.headlineMedium!.fontSize, 24);
        expect(t.headlineMedium!.fontWeight, FontWeight.w600);
      });
      test('$name titleLarge is the 20/600 title', () {
        expect(t.titleLarge!.fontSize, 20);
        expect(t.titleLarge!.fontWeight, FontWeight.w600);
      });
      test('$name titleMedium is the 17/600 row title', () {
        expect(t.titleMedium!.fontSize, 17);
        expect(t.titleMedium!.fontWeight, FontWeight.w600);
      });
      test('$name titleSmall is 15/600 body strong', () {
        expect(t.titleSmall!.fontSize, 15);
        expect(t.titleSmall!.fontWeight, FontWeight.w600);
      });
      test('$name bodyLarge is the 15 mono tabular data role', () {
        expect(t.bodyLarge!.fontSize, 15);
        expect(t.bodyLarge!.fontFamily, AppTheme.fontMono);
        expect(t.bodyLarge!.fontFeatures,
            contains(const FontFeature.tabularFigures()));
      });
      test('$name bodyMedium, the default Text style, is 15 with 1.45 leading',
          () {
        expect(t.bodyMedium!.fontSize, 15);
        expect(t.bodyMedium!.height, 1.45);
      });
      test('$name bodySmall is the 13 condensed footnote in secondary ink', () {
        expect(t.bodySmall!.fontSize, 13);
        expect(t.bodySmall!.fontFamily, AppTheme.fontDense);
        expect(t.bodySmall!.color, secondary);
      });
      test('$name labelLarge is 15/600 for buttons', () {
        expect(t.labelLarge!.fontSize, 15);
        expect(t.labelLarge!.fontWeight, FontWeight.w600);
      });
      test('$name labelMedium is the 13/600 tracked condensed label', () {
        expect(t.labelMedium!.fontSize, 13);
        expect(t.labelMedium!.fontWeight, FontWeight.w600);
        expect(t.labelMedium!.fontFamily, AppTheme.fontDense);
        expect(t.labelMedium!.letterSpacing, greaterThan(0));
      });
      test('$name nothing in the scale is below 13', () {
        for (final s in [
          t.labelSmall,
          t.labelMedium,
          t.bodySmall,
          t.bodyMedium,
          t.labelLarge,
        ]) {
          expect(s!.fontSize, greaterThanOrEqualTo(13));
        }
      });
    }
  });

  group('touch targets, shapes and inputs', () {
    final theme = AppTheme.lightTheme;
    test('tap targets are padded to 48', () {
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
    });
    test('primary buttons are 56 tall, secondary and text 48', () {
      expect(theme.elevatedButtonTheme.style!.minimumSize!.resolve({}),
          const Size(48, 56));
      expect(theme.outlinedButtonTheme.style!.minimumSize!.resolve({}),
          const Size(48, 48));
      expect(theme.textButtonTheme.style!.minimumSize!.resolve({}),
          const Size(48, 48));
    });
    test('secondary buttons are ink on card, never a second red', () {
      final s = theme.outlinedButtonTheme.style!;
      expect(s.foregroundColor!.resolve({}), AppTheme.darkSlate);
      expect(s.side!.resolve({})!.color, AppTheme.borderLight);
    });
    test('no shadows: cards, buttons and dialogs sit flat on hairlines', () {
      expect(theme.cardTheme.elevation, 0);
      expect(theme.elevatedButtonTheme.style!.elevation!.resolve({}), 0);
      expect(theme.dialogTheme.elevation, 0);
      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.side.color, AppTheme.borderLight);
      expect(shape.borderRadius, BorderRadius.circular(AppTheme.radiusCard));
    });
    test('list rows are at least 56', () {
      expect(theme.listTileTheme.minTileHeight, 56);
    });
    test('inputs pad to a 52 field and hint in body-size secondary ink', () {
      final d = theme.inputDecorationTheme;
      expect(d.contentPadding,
          const EdgeInsets.symmetric(horizontal: 14, vertical: 16));
      expect(d.hintStyle!.fontSize, 15);
      expect(d.hintStyle!.color, AppTheme.secondaryInk);
      expect(d.labelStyle!.fontSize, 15);
    });
    test('app bar sits on the page in ink with the title role', () {
      expect(theme.appBarTheme.backgroundColor, AppTheme.lightBg);
      expect(theme.appBarTheme.foregroundColor, AppTheme.darkSlate);
      expect(theme.appBarTheme.titleTextStyle!.fontSize, 20);
      expect(theme.appBarTheme.iconTheme!.color, AppTheme.darkSlate,
          reason: 'red is the action, not the chrome');
    });
    test('page transitions are native per platform', () {
      final b = theme.pageTransitionsTheme.builders;
      expect(b[TargetPlatform.iOS], isA<CupertinoPageTransitionsBuilder>());
      expect(
          b[TargetPlatform.android], isA<FadeForwardsPageTransitionsBuilder>());
    });
  });

  testWidgets('context.text resolves the theme scale', (tester) async {
    late TextTheme seen;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Builder(builder: (context) {
        seen = context.text;
        return const SizedBox();
      }),
    ));
    expect(seen.bodyMedium!.fontSize, 15);
    expect(seen.bodyMedium!.fontFamily, AppTheme.fontUi);
  });
}
