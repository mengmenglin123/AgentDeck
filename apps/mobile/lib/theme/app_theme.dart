import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// HuanHermes design tokens — Linear-inspired precision console.
/// Dark-native surfaces, single indigo accent, luminance stacking.
class AppTheme {
  AppTheme._();

  // Brand accent (Linear indigo-violet family)
  static const Color accent = Color(0xFF5E6AD2);
  static const Color accentBright = Color(0xFF7170FF);
  static const Color accentSoft = Color(0xFF828FFF);

  // Dark surfaces (near-black → elevated)
  static const Color darkCanvas = Color(0xFF08090A);
  static const Color darkPanel = Color(0xFF0F1011);
  static const Color darkSurface = Color(0xFF191A1B);
  static const Color darkElevated = Color(0xFF28282C);

  // Light surfaces
  static const Color lightCanvas = Color(0xFFF7F8F8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightMuted = Color(0xFFF3F4F5);

  // Status
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  static const double radius = 12;
  static const double radiusSm = 8;
  static const double radiusLg = 16;
  static const double radiusPill = 999;

  static ThemeData light({bool highContrast = false}) {
    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: highContrast ? const Color(0xFF2F3AA8) : accent,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE8EAFF),
      onPrimaryContainer: const Color(0xFF1A1F5C),
      secondary: const Color(0xFF5B6170),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE8EAEE),
      onSecondaryContainer: const Color(0xFF2A2E38),
      tertiary: accentBright,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFECEBFF),
      onTertiaryContainer: const Color(0xFF231F66),
      error: highContrast ? const Color(0xFFB00020) : danger,
      onError: Colors.white,
      errorContainer: const Color(0xFFFDE7E7),
      onErrorContainer: const Color(0xFF7A1414),
      surface: lightCanvas,
      onSurface: highContrast ? Colors.black : const Color(0xFF0F1011),
      onSurfaceVariant: const Color(0xFF5B6170),
      outline: highContrast ? Colors.black : const Color(0xFFD0D6E0),
      outlineVariant: const Color(0xFFE6E6E6),
      surfaceContainerHighest: lightMuted,
      surfaceContainerHigh: const Color(0xFFF5F6F7),
      surfaceContainer: lightSurface,
      surfaceContainerLow: lightCanvas,
      inverseSurface: darkPanel,
      onInverseSurface: const Color(0xFFF7F8F8),
      inversePrimary: accentSoft,
      shadow: Colors.black,
      scrim: Colors.black,
    );
    return _build(scheme, highContrast: highContrast);
  }

  static ThemeData dark({bool highContrast = false}) {
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: highContrast ? const Color(0xFF8EC7FF) : accentBright,
      onPrimary: const Color(0xFF0A0B1A),
      primaryContainer: const Color(0xFF2A2F6B),
      onPrimaryContainer: const Color(0xFFE0E4FF),
      secondary: const Color(0xFF8A8F98),
      onSecondary: darkCanvas,
      secondaryContainer: darkElevated,
      onSecondaryContainer: const Color(0xFFD0D6E0),
      tertiary: accentSoft,
      onTertiary: darkCanvas,
      tertiaryContainer: const Color(0xFF2B2A5E),
      onTertiaryContainer: const Color(0xFFE2E1FF),
      error: highContrast ? const Color(0xFFFF6B6B) : danger,
      onError: Colors.white,
      errorContainer: const Color(0xFF3A1517),
      onErrorContainer: const Color(0xFFFFD9D9),
      surface: highContrast ? Colors.black : darkCanvas,
      onSurface: highContrast ? Colors.white : const Color(0xFFF7F8F8),
      onSurfaceVariant: const Color(0xFF8A8F98),
      outline: highContrast ? Colors.white70 : const Color(0xFF34343A),
      outlineVariant: const Color(0xFF23252A),
      surfaceContainerHighest: darkElevated,
      surfaceContainerHigh: darkSurface,
      surfaceContainer: darkPanel,
      surfaceContainerLow: darkCanvas,
      inverseSurface: lightCanvas,
      onInverseSurface: const Color(0xFF0F1011),
      inversePrimary: accent,
      shadow: Colors.black,
      scrim: Colors.black,
    );
    return _build(scheme, highContrast: highContrast);
  }

  static ThemeData _build(ColorScheme scheme, {required bool highContrast}) {
    final isDark = scheme.brightness == Brightness.dark;
    final cardBg = isDark
        ? scheme.surfaceContainerHigh.withValues(alpha: 0.92)
        : scheme.surfaceContainer;
    final borderColor = highContrast
        ? scheme.outline
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : scheme.outlineVariant);
    final shapeSm = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusSm),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: borderColor, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
        side: BorderSide(color: borderColor),
        selectedColor: scheme.primaryContainer,
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : scheme.surfaceContainerHighest,
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: isDark ? darkPanel : scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer.withValues(alpha: isDark ? 0.55 : 1),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: -0.1,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        elevation: 0,
        highlightElevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? darkElevated : const Color(0xFF1A1B1E),
        contentTextStyle: const TextStyle(
          color: Color(0xFFF7F8F8),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        elevation: 4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(
            color: highContrast ? scheme.outline : borderColor,
            width: highContrast ? 1.4 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.error),
        ),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: shapeSm,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        iconColor: scheme.primary,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.1,
        ),
        subtitleTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12.5,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: highContrast
            ? scheme.outline
            : (isDark
                ? Colors.white.withValues(alpha: 0.06)
                : scheme.outlineVariant.withValues(alpha: 0.8)),
        thickness: highContrast ? 1.2 : 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : scheme.surfaceContainerHighest,
          foregroundColor: scheme.onSurface,
          shape: shapeSm,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: shapeSm,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: shapeSm,
          side: BorderSide(color: borderColor),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? darkSurface : lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? darkSurface : lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? darkElevated : lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
        elevation: 8,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? darkElevated : const Color(0xFF1A1B1E),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(
          color: Color(0xFFF7F8F8),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
