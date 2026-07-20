import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/connect_screen.dart';
import 'screens/home_shell.dart';
import 'services/app_settings_controller.dart';
import 'services/connection_controller.dart';
import 'services/theme_controller.dart';
import 'theme/app_theme.dart';

class HuanHermesApp extends StatelessWidget {
  const HuanHermesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeController, AppSettingsController>(
      builder: (context, theme, settings, _) {
        return MaterialApp(
          title: 'HuanHermes',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(highContrast: settings.highContrast),
          darkTheme: AppTheme.dark(highContrast: settings.highContrast),
          themeMode: theme.mode,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(settings.textScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: Consumer<ConnectionController>(
            builder: (context, c, _) {
              if (c.isReady) {
                return const HomeShell();
              }
              return const ConnectScreen();
            },
          ),
        );
      },
    );
  }
}
