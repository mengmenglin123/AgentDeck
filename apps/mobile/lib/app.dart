import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/connect_screen.dart';
import 'screens/home_shell.dart';
import 'services/app_settings_controller.dart';
import 'services/connection_controller.dart';
import 'services/notification_service.dart';
import 'services/theme_controller.dart';
import 'theme/app_theme.dart';

class HuanHermesApp extends StatefulWidget {
  const HuanHermesApp({super.key, this.startupNotice});

  /// One-time message shown after startup (e.g. saved profiles were reset).
  final String? startupNotice;

  @override
  State<HuanHermesApp> createState() => _HuanHermesAppState();
}

class _HuanHermesAppState extends State<HuanHermesApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<NotificationIntent>? _notificationSub;
  NotificationIntent? _deferredIntent;

  @override
  void initState() {
    super.initState();
    final notifications = NotificationService.instance;
    _notificationSub = notifications.intents.listen(_openNotification);
    _deferredIntent = notifications.takePendingIntent();
    final notice = widget.startupNotice;
    if (notice != null && notice.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(notice),
            duration: const Duration(seconds: 8),
          ),
        );
      });
    }
  }

  void _openNotification(NotificationIntent intent) {
    if (!mounted) return;
    final connection = context.read<ConnectionController>();
    if (!connection.isReady) {
      _deferredIntent = intent;
      return;
    }
    _deferredIntent = null;
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => HomeShell(
          initialIndex: 0,
          initialSessionRef: intent.sessionRef,
        ),
      ),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeController, AppSettingsController>(
      builder: (context, theme, settings, _) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          scaffoldMessengerKey: _messengerKey,
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
            builder: (context, connection, _) {
              final deferred = _deferredIntent;
              if (connection.isReady && deferred != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && identical(_deferredIntent, deferred)) {
                    _openNotification(deferred);
                  }
                });
              }
              if (connection.isReady) {
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
