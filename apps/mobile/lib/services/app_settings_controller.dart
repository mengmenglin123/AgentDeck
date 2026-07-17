import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local console preferences (never uploaded to Host).
class AppSettingsController extends ChangeNotifier {
  static const _kScale = 'huanhermes.text_scale.v1';
  static const _kCompact = 'huanhermes.compact_mode.v1';
  static const _kDashRefresh = 'huanhermes.dashboard_refresh_sec.v1';
  static const _kShowTools = 'huanhermes.show_tools_default.v1';
  static const _kSort = 'huanhermes.session_sort.v1';
  static const _kContrast = 'huanhermes.high_contrast.v1';

  /// 0.85 | 1.0 | 1.15 | 1.3
  double textScale = 1.0;

  /// Tighter list tiles / denser UI.
  bool compactMode = false;

  /// Dashboard auto-refresh seconds; 0 = off.
  int dashboardRefreshSec = 15;

  /// Default for chat tools visibility preference (UI hint only).
  bool showToolsDefault = true;

  /// Session list sort: updated | title | project | created | recent
  String sessionSort = 'updated';

  /// Stronger borders / higher contrast surfaces for a11y.
  bool highContrast = false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    textScale = p.getDouble(_kScale) ?? 1.0;
    if (textScale < 0.8 || textScale > 1.5) textScale = 1.0;
    compactMode = p.getBool(_kCompact) ?? false;
    dashboardRefreshSec = p.getInt(_kDashRefresh) ?? 15;
    if (dashboardRefreshSec < 0 || dashboardRefreshSec > 120) {
      dashboardRefreshSec = 15;
    }
    showToolsDefault = p.getBool(_kShowTools) ?? true;
    sessionSort = p.getString(_kSort) ?? 'updated';
    const allowed = {'updated', 'title', 'project', 'created', 'recent'};
    if (!allowed.contains(sessionSort)) sessionSort = 'updated';
    highContrast = p.getBool(_kContrast) ?? false;
    notifyListeners();
  }

  Future<void> setTextScale(double v) async {
    textScale = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kScale, v);
  }

  Future<void> setCompactMode(bool v) async {
    compactMode = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kCompact, v);
  }

  Future<void> setDashboardRefreshSec(int v) async {
    dashboardRefreshSec = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kDashRefresh, v);
  }

  Future<void> setShowToolsDefault(bool v) async {
    showToolsDefault = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowTools, v);
  }

  Future<void> setSessionSort(String v) async {
    sessionSort = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSort, v);
  }

  Future<void> setHighContrast(bool v) async {
    highContrast = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kContrast, v);
  }
}
