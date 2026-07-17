import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
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
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider.value(value: theme),
      ],
      child: const HuanHermesApp(),
    ),
  );
}
