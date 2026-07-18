import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/notification_service.dart';
import 'services/app_settings_controller.dart';
import 'services/connection_controller.dart';
import 'services/secure_config_store.dart';
import 'services/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SecureConfigStore();
  await store.init();
  final controller = ConnectionController(store: store);
  await controller.bootstrap();
  final theme = ThemeController();
  await theme.load();
  final settings = AppSettingsController();
  await settings.load();
  await NotificationService.instance.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider.value(value: theme),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: const HuanHermesApp(),
    ),
  );
}
