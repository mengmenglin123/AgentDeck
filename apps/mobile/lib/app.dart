import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/connect_screen.dart';
import 'screens/sessions_screen.dart';
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
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
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
                return const SessionsScreen();
              }
              return const ConnectScreen();
            },
          ),
        );
      },
    );
  }
}
