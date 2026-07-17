import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local theme mode (system / light / dark).
class ThemeController extends ChangeNotifier {
  ThemeController();

  static const _k = 'huanhermes.theme_mode.v1';

  ThemeMode mode = ThemeMode.system;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_k) ?? 'system';
    mode = _fromString(raw);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode next) async {
    mode = next;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, _toString(next));
  }

  Future<void> cycle() async {
    final order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    final i = order.indexOf(mode);
    await setMode(order[(i + 1) % order.length]);
  }

  String get label {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  IconData get icon {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
        return Icons.brightness_auto;
    }
  }

  static ThemeMode _fromString(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _toString(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
