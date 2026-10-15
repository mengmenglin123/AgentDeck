import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/app_settings_controller.dart';
import '../services/connection_controller.dart';
import '../services/connection_store.dart';
import '../services/theme_controller.dart';

/// Everything the main app needs once startup has finished.
class BootstrapResult {
  const BootstrapResult({
    required this.connection,
    required this.theme,
    required this.settings,
    this.profilesReset = false,
    this.failedSteps = const [],
  });

  final ConnectionController connection;
  final ThemeController theme;
  final AppSettingsController settings;

  /// Saved server profiles could not be read and were cleared.
  final bool profilesReset;

  /// Steps that failed or timed out (diagnostics only; the app still runs).
  final List<String> failedSteps;
}

/// Runs startup initialisation **after** `runApp`, so that no failure or hang
/// in a plugin can leave the Android splash screen up forever.
///
/// Every step has a timeout and a fallback:
/// - connection store unreadable → wipe it, continue with no profiles and
///   report [BootstrapResult.profilesReset] so the UI can tell the user;
/// - theme / settings load failure → defaults.
class AppBootstrap {
  AppBootstrap({
    required this.store,
    ThemeController? theme,
    AppSettingsController? settings,
    this.stepTimeout = const Duration(seconds: 5),
  })  : theme = theme ?? ThemeController(),
        settings = settings ?? AppSettingsController();

  final ConnectionStore store;
  final ThemeController theme;
  final AppSettingsController settings;
  final Duration stepTimeout;

  Future<BootstrapResult> run() async {
    final failed = <String>[];
    final connection = ConnectionController(store: store);
    var profilesReset = false;

    final ok = await _step('connection', failed, () async {
      await store.init();
      await connection.bootstrap();
    });
    if (!ok) {
      // Stored data is unreadable (typically encrypted prefs restored from a
      // backup whose Keystore key no longer exists). Wipe and start clean.
      final recovered = await _step('connection-reset', failed, () async {
        if (store is RecoverableConnectionStore) {
          await (store as RecoverableConnectionStore).resetCorrupted();
        } else {
          await store.clear();
        }
        await connection.bootstrap();
      });
      if (!recovered) connection.bootstrapEmpty();
      profilesReset = true;
    }

    await _step('theme', failed, theme.load);
    await _step('settings', failed, settings.load);

    return BootstrapResult(
      connection: connection,
      theme: theme,
      settings: settings,
      profilesReset: profilesReset,
      failedSteps: List.unmodifiable(failed),
    );
  }

  Future<bool> _step(
    String name,
    List<String> failed,
    Future<void> Function() body,
  ) async {
    try {
      await body().timeout(stepTimeout);
      return true;
    } catch (e, st) {
      failed.add(name);
      debugPrint('HuanHermes startup step "$name" failed: $e\n$st');
      return false;
    }
  }
}
