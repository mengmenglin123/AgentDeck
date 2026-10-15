import 'dart:async';

import 'package:flutter/material.dart';

import 'services/notification_service.dart';
import 'services/secure_config_store.dart';
import 'startup/app_bootstrap.dart';
import 'startup/startup_gate.dart';

/// Nothing is awaited before [runApp]: a plugin that throws or hangs during
/// startup (secure storage, notifications, prefs) must never leave the
/// Android splash screen up forever. Initialisation runs behind a loading
/// screen with per-step timeouts — see [AppBootstrap].
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    StartupGate(
      bootstrap: () async {
        // Notifications are optional: initialise in the background, never
        // block startup on them, and ask for the permission only after the
        // first real frame (see onReady).
        unawaited(NotificationService.instance.init());
        return AppBootstrap(store: SecureConfigStore()).run();
      },
      onReady: () {
        unawaited(NotificationService.instance.requestPermission());
      },
    ),
  );
}
