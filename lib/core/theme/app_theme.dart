import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Design tokens and themes for Switch Fiber Tech: the Calm Utility system in
/// DESIGN.md ("the printed job slip").
///
/// Matte paper and black ink, hairlines instead of shadows, and the brand red
/// used once per screen as the action. Type is Barlow for the interface,
/// Barlow Semi Condensed for dense rows and 13px labels, and JetBrains Mono
/// with tabular figures for everything that is measured. All three are
/// bundled (see pubspec.yaml) because the app runs offline.
///
/// Token names are kept from the previous system so call sites keep
/// compiling; the values changed.
class AppTheme {
  // Font families as declared in pubspec.yaml.
  static const String fontUi = 'Barlow';
  static const String fontDense = 'Barlow Semi Condensed';
  static const String fontMono = 'JetBrains Mono';

  // Brand: Switch Fiber red. A fill for the one action per screen, never a
  // text colour below 18px bold (use brandInk for text).
  static const Color primary = Color(0xFFE02424);
  static const Color primaryDark = Color(0xFFC81E1E);
  static const Color primaryActive = Color(0xFF9B1C1C);
  static const Color primarySubtleBg = Color(0xFFFBEAE8); // faint red on paper
  static const Color primarySubtleBorder = Color(0xFFF1C4C0);
  static const Color primarySubtleBgDark = Color(0xFF2C1A18);
  static const Color primarySubtleBorderDark = Color(0xFF5A2622);

  // Light surfaces: warm paper page, white card, one hairline.
  static const Color lightBg = Color(0xFFF4F1EA); // paper
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color white = Color(0xFFFFFFFF);
  static const Color darkSlate = Color(0xFF17150F); // ink (name kept)
  static const Color textMuted =
      Color(0xFFA39E92); // a fill grey; fails on paper, never for text
  static const Color textSecondary = textMuted;
  static const Color textTertiary = Color(0xFFCFC9BD);
  static const Color borderLight = Color(0xFFD9D4C8); // hairline
  static const Color fillLight = Color(0xFFECE8DF); // inputs, chips, tiles

  // Dark surfaces: near-black paper, not navy.
  static const Color darkBg = Color(0xFF0F0F0D);
  static const Color darkCard = Color(0xFF1A1916);
  static const Color darkCardElevated = Color(0xFF262420);
  static const Color darkElevatedCard = darkCardElevated;
  static const Color darkInput = Color(0xFF23211C);
  static const Color textSecondaryDark = Color(0xFFA39E92);
  static const Color textTertiaryDark = Color(0xFF6B665C);
  static const Color borderDark = Color(0xFF2C2A25);
  static const Color fillDark = Color(0xFF23211C);

  // Status fills and rails. Meaning is never carried by colour alone: every
  // rail sits next to a word.
  static const Color success = Color(0xFF176F34); // done, pass
  static const Color warning = Color(0xFFFFB020); // near threshold, pending
  static const Color danger = Color(0xFFE02424); // failed
  static const Color info = Color(0xFF2F6FED); // scheduled

  // Status subtle backgrounds (banners, tiles).
  static const Color successSubtle = Color(0xFFE6F2E9);
  static const Color warningSubtle = Color(0xFFFFF3D6);
  static const Color dangerSubtle = Color(0xFFFBEAE8);
  static const Color infoSubtle = Color(0xFFE8EEFB);

  // Gene - Nov, 26, 2026: Distinct Violet accent tokens for Service Orders (Repairs) so they match Job Order layout while staying visually distinguishable.
  static const Color serviceOrderAccent = Color(0xFF6D28D9);
  static const Color serviceOrderSubtleBg = Color(0xFFF3EEFF);
  static const Color serviceOrderSubtleBorder = Color(0xFFD8C8FA);
  static const Color serviceOrderSubtleBgDark = Color(0xFF241B35);
  static const Color serviceOrderSubtleBorderDark = Color(0xFF4C3575);

  // Ink tokens: the only colours allowed on TEXT. Each passes WCAG 4.5:1 on
  // both surfaces of its theme (verified by test/app_theme_contrast_test.dart).
  static const Color secondaryInk = Color(0xFF5C574D); // 6.4:1 page, 7.2:1 card
  static const Color secondaryInkDark = Color(0xFFA39E92); // 6.7:1 card
  static const Color brandInk = Color(0xFFB81A1A); // 5.8:1 page
  static const Color brandInkDark = Color(0xFFFF6B6B); // 6.4:1 card
  static const Color successInk = Color(0xFF176F34); // 5.6:1 page
  static const Color successInkDark = Color(0xFF5CCB7A); // 8.7:1 card
  static const Color warningInk = Color(0xFF9A5B00); // 4.8:1 page
  static const Color warningInkDark = Color(0xFFF5B942); // 10:1 card
  static const Color dangerInk = Color(0xFFB81A1A);
  static const Color dangerInkDark = Color(0xFFFF6B6B);
  static const Color infoInk = Color(0xFF1D4ED8); // 6.0:1 page
  static const Color infoInkDark = Color(0xFF6D9BFF); // 6.6:1 card
  static const Color violetInk = Color(0xFF6D28D9);
  static const Color violetInkDark = Color(0xFFC084FC);

  static bool _isDark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  /// Text colour for secondary information in the active theme.
  static Color secondaryInkOf(BuildContext c) =>
      _isDark(c) ? secondaryInkDark : secondaryInk;
  static Color brandInkOf(BuildContext c) =>
      _isDark(c) ? brandInkDark : brandInk;
  static Color successInkOf(BuildContext c) =>
      _isDark(c) ? successInkDark : successInk;
  static Color warningInkOf(BuildContext c) =>
      _isDark(c) ? warningInkDark : warningInk;
  static Color dangerInkOf(BuildContext c) =>
      _isDark(c) ? dangerInkDark : dangerInk;
  static Color infoInkOf(BuildContext c) => _isDark(c) ? infoInkDark : infoInk;
  static Color violetInkOf(BuildContext c) =>
      _isDark(c) ? violetInkDark : violetInk;

  /// Surface helpers for subtle brand and neutral fills.
  static Color primarySubtleBgOf(BuildContext c) =>
      _isDark(c) ? primarySubtleBgDark : primarySubtleBg;
  static Color primarySubtleBorderOf(BuildContext c) =>
      _isDark(c) ? primarySubtleBorderDark : primarySubtleBorder;
  // Gene - Nov, 26, 2026: Theme-aware surface and ink helpers for Service Order violet distinction.
  static Color serviceOrderSubtleBgOf(BuildContext c) =>
      _isDark(c) ? serviceOrderSubtleBgDark : serviceOrderSubtleBg;
  static Color serviceOrderSubtleBorderOf(BuildContext c) =>
      _isDark(c) ? serviceOrderSubtleBorderDark : serviceOrderSubtleBorder;
  static Color serviceOrderInkOf(BuildContext c) => violetInkOf(c);
  static Color fillOf(BuildContext c) => _isDark(c) ? fillDark : fillLight;

  /// Primary text ("ink") and page surface for the active theme.
  static Color inkOf(BuildContext c) => _isDark(c) ? white : darkSlate;
  static Color pageOf(BuildContext c) => _isDark(c) ? darkBg : lightBg;
  static Color cardOf(BuildContext c) => _isDark(c) ? darkCard : lightCard;
  static Color hairlineOf(BuildContext c) =>
      _isDark(c) ? borderDark : borderLight;

  // Radii, from DESIGN.md: not one radius for everything.
  static const double radiusCard = 16;
  static const double radiusButton = 14;
  static const double radiusInput = 12;
  static const double radiusStamp = 6;

  // Touch targets.
  static const double minTarget = 48;
  static const double primaryButtonHeight = 56;
  static const double stickyBarHeight = 64;

  /// Native feel where the platforms actually differ: a Cupertino push on
  /// iOS, Material 3's fade-forwards on Android. Everything else is shared.
  static const PageTransitionsTheme _pageTransitionsTheme =
      PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    },
  );

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// The Calm Utility scale (DESIGN.md, Typography). Built per brightness so
  /// secondary text carries the ink that passes contrast on that theme.
  ///
  /// Roles: displaySmall hero clock (mono 44), headlineSmall reading
  /// (mono 36), headlineMedium headline 24, titleLarge title 20, titleMedium
  /// row title 17, titleSmall body strong 15, bodyLarge data (mono 15),
  /// bodyMedium body 15, bodySmall footnote 13 (condensed, secondary ink),
  /// labelLarge button 15, labelMedium label 13 (condensed, tracked),
  /// labelSmall quiet label 13 (condensed, secondary ink).
  static TextTheme _textTheme({
    required Color onSurface,
    required Color secondary,
  }) {
    return TextTheme(
      displaySmall: TextStyle(
        fontFamily: fontMono,
        fontSize: 44,
        fontWeight: FontWeight.w500,
        height: 1.05,
        fontFeatures: _tabular,
        color: onSurface,
      ),
      headlineSmall: TextStyle(
        fontFamily: fontMono,
        fontSize: 36,
        fontWeight: FontWeight.w500,
        height: 1.0,
        fontFeatures: _tabular,
        color: onSurface,
      ),
      headlineMedium: TextStyle(
        fontFamily: fontUi,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.15,
        letterSpacing: -0.2,
        color: onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: fontUi,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.2,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: fontUi,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: onSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: fontUi,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: fontMono,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.4,
        fontFeatures: _tabular,
        color: onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontUi,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: onSurface,
      ),
      bodySmall: TextStyle(
        fontFamily: fontDense,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: secondary,
      ),
      labelLarge: TextStyle(
        fontFamily: fontUi,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: fontDense,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0.8,
        color: onSurface,
      ),
      labelSmall: TextStyle(
        fontFamily: fontDense,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.2,
        letterSpacing: 0.4,
        color: secondary,
      ),
    );
  }

  /// Filter and choice chips: the quiet fill with a hairline at rest; ink
  /// with page-coloured text when selected. Red stays free for the action.
  static ChipThemeData _chipTheme({
    required Color fill,
    required Color selectedFill,
    required Color border,
    required Color ink,
    required Color selectedInk,
  }) {
    return ChipThemeData(
      backgroundColor: fill,
      selectedColor: selectedFill,
      checkmarkColor: selectedInk,
      iconTheme: IconThemeData(color: ink, size: 20),
      labelStyle: TextStyle(
        fontFamily: fontUi,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.selected) ? selectedInk : ink),
      ),
      side: WidgetStateBorderSide.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? BorderSide(color: selectedFill, width: 1)
              : BorderSide(color: border, width: 1)),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      showCheckmark: false,
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color page,
    required Color card,
    required Color elevated,
    required Color inputFill,
    required Color hairline,
    required Color ink,
    required Color secondary,
    required Color brand,
    required Color brandSubtleBg,
    required Color chipFill,
  }) {
    final text = _textTheme(onSurface: ink, secondary: secondary);
    final isDark = brightness == Brightness.dark;

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontUi,
      primaryColor: primary,
      scaffoldBackgroundColor: page,
      canvasColor: page,
      pageTransitionsTheme: _pageTransitionsTheme,
      // Calm: no ripples on either platform. The primary button carries the
      // only press feedback (a spring scale, applied in its widget).
      splashFactory: NoSplash.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: text,
      iconTheme: IconThemeData(color: ink, size: 24),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        minTileHeight: 56,
        iconColor: secondary,
        textColor: ink,
      ),
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: white,
        primaryContainer: brandSubtleBg,
        onPrimaryContainer: brand,
        secondary: ink,
        onSecondary: page,
        secondaryContainer: ink,
        onSecondaryContainer: page,
        surface: card,
        onSurface: ink,
        surfaceContainerHighest: inputFill,
        onSurfaceVariant: secondary,
        outline: hairline,
        outlineVariant: hairline,
        error: danger,
        onError: white,
        errorContainer: isDark ? primarySubtleBgDark : dangerSubtle,
        onErrorContainer: brand,
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        primaryColor: primary,
        brightness: brightness,
        scaffoldBackgroundColor: page,
        barBackgroundColor: page.withValues(alpha: 0.92),
        textTheme: CupertinoTextThemeData(
          textStyle: text.bodyMedium,
          navTitleTextStyle: text.titleLarge,
        ),
      ),
      chipTheme: _chipTheme(
        fill: chipFill,
        selectedFill: ink,
        border: hairline,
        ink: secondary,
        selectedInk: page,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: page,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: text.titleLarge,
        toolbarTextStyle: text.bodyMedium,
        iconTheme: IconThemeData(color: ink, size: 24),
        actionsIconTheme: IconThemeData(color: ink, size: 24),
      ),
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: hairline, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: white,
          disabledBackgroundColor: primary.withValues(alpha: 0.45),
          disabledForegroundColor: white,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(minTarget, primaryButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: page,
          minimumSize: const Size(minTarget, minTarget),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      // Secondary action: card with a hairline and ink text. Red is reserved
      // for the one primary action on the screen.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          backgroundColor: card,
          side: BorderSide(color: hairline, width: 1),
          minimumSize: const Size(minTarget, minTarget),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusButton),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          minimumSize: const Size(minTarget, minTarget),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusInput),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(minTarget, minTarget),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(minTarget, minTarget)),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected) ? ink : card),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? page : secondary),
          side: WidgetStatePropertyAll(BorderSide(color: hairline, width: 1)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusInput),
          )),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? inputFill : card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: inputBorder(hairline),
        enabledBorder: inputBorder(hairline),
        focusedBorder: inputBorder(ink, 1.5),
        errorBorder: inputBorder(brand),
        focusedErrorBorder: inputBorder(brand, 1.5),
        labelStyle: text.bodyMedium!.copyWith(color: secondary),
        floatingLabelStyle: text.labelMedium!.copyWith(color: secondary),
        hintStyle: text.bodyMedium!.copyWith(color: secondary),
        errorStyle: text.bodySmall!.copyWith(color: brand),
        prefixIconColor: secondary,
        suffixIconColor: secondary,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: hairline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? elevated : card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
        elevation: 0,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: text.bodyMedium!.copyWith(color: page),
        actionTextColor: isDark ? brandInk : brandInkDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusInput),
        ),
        elevation: 0,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: ink,
        linearTrackColor: inputFill,
        circularTrackColor: inputFill,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? page : card),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? ink : inputFill),
        trackOutlineColor: WidgetStatePropertyAll(hairline),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: secondary,
        indicatorColor: ink,
        dividerColor: hairline,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
      ),
    );
  }

  /// Light theme: paper first, for sunlight.
  static ThemeData get lightTheme => _build(
        brightness: Brightness.light,
        page: lightBg,
        card: lightCard,
        elevated: lightCard,
        inputFill: fillLight,
        hairline: borderLight,
        ink: darkSlate,
        secondary: secondaryInk,
        brand: brandInk,
        brandSubtleBg: primarySubtleBg,
        chipFill: fillLight,
      );

  /// Dark theme: near-black paper, in-app toggle.
  static ThemeData get darkTheme => _build(
        brightness: Brightness.dark,
        page: darkBg,
        card: darkCard,
        elevated: darkCardElevated,
        inputFill: darkInput,
        hairline: borderDark,
        ink: white,
        secondary: secondaryInkDark,
        brand: brandInkDark,
        brandSubtleBg: primarySubtleBgDark,
        chipFill: darkInput,
      );
}
