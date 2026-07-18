import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light({bool highContrast = false}) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1F6FEB),
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
        : base;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      dividerTheme: DividerThemeData(
        color: highContrast ? Colors.black54 : null,
        thickness: highContrast ? 1.2 : null,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        enabledBorder: highContrast
            ? const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.black87, width: 1.4),
              )
            : null,
        focusedBorder: highContrast
            ? OutlineInputBorder(
                borderSide: BorderSide(color: scheme.primary, width: 2),
              )
            : null,
      ),
      listTileTheme: highContrast
          ? const ListTileThemeData(
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.black26),
              ),
            )
          : null,
    );
  }

  static ThemeData dark({bool highContrast = false}) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF58A6FF),
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
        : base;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      dividerTheme: DividerThemeData(
        color: highContrast ? Colors.white54 : null,
        thickness: highContrast ? 1.2 : null,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        enabledBorder: highContrast
            ? const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white70, width: 1.4),
              )
            : null,
        focusedBorder: highContrast
            ? OutlineInputBorder(
                borderSide: BorderSide(color: scheme.primary, width: 2),
              )
            : null,
      ),
    );
  }
}
