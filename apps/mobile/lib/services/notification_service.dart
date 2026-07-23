import 'dart:async';

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

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _pendingIntent = NotificationIntent.tryParse(
        launchDetails?.notificationResponse?.payload,
      );
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestNotificationsPermission();
    }

    _initialized = true;
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'huanhermes_main',
      'HuanHermes',
      channelDescription: 'HuanHermes app notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(id, title, body, details, payload: payload);
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
    await _plugin.cancelAll();
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  void _onNotificationTapped(NotificationResponse response) {
    final intent = NotificationIntent.tryParse(response.payload);
    if (intent != null) {
      _intents.add(intent);
    }
  }
}
