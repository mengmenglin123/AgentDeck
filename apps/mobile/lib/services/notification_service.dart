import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service for showing local notifications on the device.
/// Used to alert the user about important events (task completion, errors, etc.)
/// when the app is in the background or the screen is off.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Initialize the notification service. Call once at app startup.
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

    // Request notification permission on Android 13+
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.requestNotificationsPermission();
    }

    _initialized = true;
  }

  /// Show a notification with the given [title] and [body].
  /// [id] is used to replace/update existing notifications.
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

  /// Show a notification for task/session completion.
  Future<void> showTaskComplete({
    required String sessionName,
    required String summary,
  }) async {
    await show(
      id: sessionName.hashCode & 0x7FFFFFFF,
      title: '任务完成：$sessionName',
      body: summary,
      payload: 'session:$sessionName',
    );
  }

  /// Show a notification for errors or alerts.
  Future<void> showError({
    required String title,
    required String message,
  }) async {
    await show(
      id:
          'error_${DateTime.now().millisecondsSinceEpoch}'.hashCode &
          0x7FFFFFFF,
      title: title,
      body: message,
    );
  }

  /// Cancel all pending notifications.
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Cancel a specific notification by [id].
  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  void _onNotificationTapped(NotificationResponse response) {
    // TODO: Navigate to relevant screen based on payload
    // For now, just log the tap
    final payload = response.payload;
    if (payload != null) {
      print('Notification tapped: $payload');
    }
  }
}
