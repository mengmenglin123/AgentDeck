import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/connect_screen.dart';
import 'screens/sessions_screen.dart';
import 'services/connection_controller.dart';
import 'services/theme_controller.dart';
import 'theme/app_theme.dart';

class HuanHermesApp extends StatelessWidget {
  const HuanHermesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeController>(
      builder: (context, theme, _) {
        return MaterialApp(
          title: 'HuanHermes',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme.mode,
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
