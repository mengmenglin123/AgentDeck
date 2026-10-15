import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/theme/app_theme.dart';

double _luminance(Color c) => c.computeLuminance();

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  final themes = <String, ThemeData>{
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
    'light-hc': AppTheme.light(highContrast: true),
    'dark-hc': AppTheme.dark(highContrast: true),
  };

  for (final entry in themes.entries) {
    test('${entry.key}: container pairs are readable (WCAG AA 4.5:1)', () {
      final cs = entry.value.colorScheme;
      expect(entry.value.useMaterial3, isTrue);
      final pairs = <String, (Color, Color)>{
        'surface': (cs.onSurface, cs.surface),
        'primaryContainer': (cs.onPrimaryContainer, cs.primaryContainer),
        'secondaryContainer': (cs.onSecondaryContainer, cs.secondaryContainer),
        'tertiaryContainer': (cs.onTertiaryContainer, cs.tertiaryContainer),
        'errorContainer': (cs.onErrorContainer, cs.errorContainer),
      };
      for (final p in pairs.entries) {
        expect(
          _contrast(p.value.$1, p.value.$2),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} ${p.key}',
        );
      }
    });
  }

  test('light and dark schemes keep their brightness', () {
    expect(themes['light']!.colorScheme.brightness, Brightness.light);
    expect(themes['dark']!.colorScheme.brightness, Brightness.dark);
  });
}
