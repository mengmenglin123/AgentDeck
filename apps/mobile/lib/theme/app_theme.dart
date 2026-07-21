import 'package:flutter/material.dart';

/// Design tokens + Material 3 themes for HuanHermes console.
class AppTheme {
  AppTheme._();

  static const Color seedLight = Color(0xFF2563EB);
  static const Color seedDark = Color(0xFF60A5FA);
  static const double radius = 16;
  static const double radiusSm = 12;

  static ThemeData light({bool highContrast = false}) {
    final base = ColorScheme.fromSeed(
      seedColor: seedLight,
      brightness: Brightness.light,
    );
    final scheme = highContrast
        ? base.copyWith(
            outline: Colors.black,
            outlineVariant: Colors.black87,
            surfaceContainerHighest: const Color(0xFFE8E8E8),
            onSurface: Colors.black,
            primary: const Color(0xFF003D99),
            error: const Color(0xFFB00020),
          )
        : base.copyWith(
            surface: const Color(0xFFF7F8FA),
            surfaceContainerHighest: const Color(0xFFEEF1F6),
          );
    return _build(scheme, highContrast: highContrast);
  }

  static ThemeData dark({bool highContrast = false}) {
    final base = ColorScheme.fromSeed(
      seedColor: seedDark,
      brightness: Brightness.dark,
    );
    final scheme = highContrast
        ? base.copyWith(
            outline: Colors.white,
            outlineVariant: Colors.white70,
            surface: const Color(0xFF000000),
            surfaceContainerHighest: const Color(0xFF1A1A1A),
            onSurface: Colors.white,
            primary: const Color(0xFF8EC7FF),
            error: const Color(0xFFFF6B6B),
          )
        : base.copyWith(
            surface: const Color(0xFF0F1419),
            surfaceContainerHighest: const Color(0xFF1A2332),
          );
    return _build(scheme, highContrast: highContrast);
  }

  static ThemeData _build(ColorScheme scheme, {required bool highContrast}) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusSm),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHighest.withOpacity(0.55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(
            color: scheme.outlineVariant.withOpacity(highContrast ? 0.8 : 0.35),
          ),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.5)),
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(color: scheme.onSurface, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 2,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withOpacity(0.35),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(
            color: highContrast ? scheme.outline : scheme.outlineVariant,
            width: highContrast ? 1.4 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: shape,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        iconColor: scheme.primary,
      ),
      dividerTheme: DividerThemeData(
        color: highContrast
            ? (scheme.brightness == Brightness.dark
                ? Colors.white54
                : Colors.black54)
            : scheme.outlineVariant.withOpacity(0.5),
        thickness: highContrast ? 1.2 : 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
        ),
        showDragHandle: true,
      ),
    );
  }
}
