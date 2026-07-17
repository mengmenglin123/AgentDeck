
import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/services/audit_log.dart';

void main() {
  test('redacts tokens', () {
    final log = AuditLog();
    log.add('connect', detail: 'ws://h:9810/bridge/ws?token=secret-value');
    expect(log.entries.single.detail.contains('secret-value'), isFalse);
    expect(log.entries.single.detail.contains('token=***'), isTrue);
  });
}
