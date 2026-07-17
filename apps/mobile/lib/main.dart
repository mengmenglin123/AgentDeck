import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/connection_controller.dart';
import 'services/secure_config_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SecureConfigStore();
  await store.init();
  final controller = ConnectionController(store: store);
  await controller.bootstrap();
  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const HuanHermesApp(),
    ),
  );
}
