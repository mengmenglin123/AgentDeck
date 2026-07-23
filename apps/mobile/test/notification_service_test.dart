import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/services/notification_service.dart';

void main() {
  test('parses session and permission notification intents', () {
    final session = NotificationIntent.tryParse('session:demo');
    expect(session?.destination, NotificationDestination.sessions);
    expect(session?.sessionRef, 'demo');
    expect(NotificationService.sessionPayload(' huan:codex:stable '),
        'session:huan:codex:stable');
    expect(NotificationService.permissionPayload('huan:codex:stable'),
        'permission:huan:codex:stable');

    final permission = NotificationIntent.tryParse('permission:huan:1');
    expect(permission?.destination, NotificationDestination.sessions);
    expect(permission?.sessionRef, 'huan:1');
  });

  test('ignores empty and unknown notification payloads', () {
    expect(NotificationIntent.tryParse(null), isNull);
    expect(NotificationIntent.tryParse(''), isNull);
    expect(NotificationIntent.tryParse('other:value'), isNull);
    expect(
        NotificationIntent.tryParse(NotificationService.sessionPayload(
          'huan:codex:stable',
        ))?.sessionRef,
        'huan:codex:stable');
  });
}
