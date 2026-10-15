import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum NotificationDestination { sessions }

class NotificationIntent {
  const NotificationIntent({
    required this.destination,
    required this.payload,
    this.sessionRef,
  });

  final NotificationDestination destination;
  final String payload;
  final String? sessionRef;

  static NotificationIntent? tryParse(String? payload) {
    final value = payload?.trim() ?? '';
    if (value.isEmpty) return null;
    for (final prefix in const ['session:', 'permission:']) {
      if (value.startsWith(prefix)) {
        final ref = value.substring(prefix.length).trim();
        return NotificationIntent(
          destination: NotificationDestination.sessions,
          payload: value,
          sessionRef: ref.isEmpty ? null : ref,
        );
      }
    }
    return null;
  }
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  static String sessionPayload(String sessionKey) {
    return 'session:${sessionKey.trim()}';
  }

  static String permissionPayload(String sessionKey) {
    return 'permission:${sessionKey.trim()}';
  }

  final _plugin = FlutterLocalNotificationsPlugin();
  final _intents = StreamController<NotificationIntent>.broadcast();
  bool _initialized = false;
  NotificationIntent? _pendingIntent;

  Stream<NotificationIntent> get intents => _intents.stream;

  NotificationIntent? takePendingIntent() {
    final intent = _pendingIntent;
    _pendingIntent = null;
    return intent;
  }

  Future<void>? _initFuture;

  /// Small status-bar icon. Must be a monochrome drawable that survives R8
  /// resource shrinking (kept via res/raw/keep.xml). The old
  /// '@mipmap/ic_launcher' does not exist in release builds, which made
  /// initialize() throw `invalid_icon` before runApp (0.1.204 splash hang).
  static const smallIcon = '@drawable/ic_stat_notify';

  /// Initialises the plugin. Never throws and never asks for permissions;
  /// on failure notifications are simply disabled for this run.
  Future<void> init() {
    if (_initialized) return Future.value();
    return _initFuture ??= _doInit().whenComplete(() {
      if (!_initialized) _initFuture = null;
    });
  }

  Future<void> _doInit() async {
    try {
      const androidSettings = AndroidInitializationSettings(smallIcon);
      const initSettings = InitializationSettings(android: androidSettings);

      await _plugin
          .initialize(
            initSettings,
            onDidReceiveNotificationResponse: _onNotificationTapped,
          )
          .timeout(const Duration(seconds: 5));
      _initialized = true;

      final launchDetails = await _plugin
          .getNotificationAppLaunchDetails()
          .timeout(const Duration(seconds: 5));
      if (launchDetails?.didNotificationLaunchApp == true) {
        final intent = NotificationIntent.tryParse(
          launchDetails?.notificationResponse?.payload,
        );
        if (intent != null) {
          // The app UI may already be listening (init runs in background).
          if (_intents.hasListener) {
            _intents.add(intent);
          } else {
            _pendingIntent = intent;
          }
        }
      }
    } catch (e) {
      debugPrint('HuanHermes notifications unavailable: $e');
    }
  }

  /// Asks for POST_NOTIFICATIONS (Android 13+). Call only once UI is on
  /// screen; failures are ignored.
  Future<void> requestPermission() async {
    try {
      await init();
      if (!_initialized) return;
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('HuanHermes notification permission request failed: $e');
    }
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'huanhermes_main',
      'HuanHermes',
      channelDescription: 'HuanHermes app notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const details = NotificationDetails(android: androidDetails);

    try {
      await _plugin.show(id, title, body, details, payload: payload);
    } catch (e) {
      debugPrint('HuanHermes notification failed: $e');
    }
  }

  Future<void> showTaskComplete({
    required String sessionKey,
    required String sessionName,
    required String summary,
  }) async {
    await show(
      id: sessionName.hashCode & 0x7FFFFFFF,
      title: '任务完成：$sessionName',
      body: summary,
      payload: sessionPayload(sessionKey),
    );
  }

  Future<void> showError({
    required String title,
    required String message,
  }) async {
    await show(
      id: 'error_${DateTime.now().millisecondsSinceEpoch}'.hashCode &
          0x7FFFFFFF,
      title: title,
      body: message,
    );
  }

  Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<void> cancel(int id) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  void _onNotificationTapped(NotificationResponse response) {
    final intent = NotificationIntent.tryParse(response.payload);
    if (intent != null) {
      _intents.add(intent);
    }
  }
}
