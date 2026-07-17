import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/utils/security.dart';

void main() {
  test('redacts bearer and query tokens', () {
    final s = Security.redactText(
      'Authorization: Bearer super-secret-token-value '
      'ws://h/bridge/ws?token=abc123xyz '
      'api_key=should-hide',
    );
    expect(s, isNot(contains('super-secret-token-value')));
    expect(s, isNot(contains('abc123xyz')));
    expect(s, contains('token=***'));
    expect(s.toLowerCase(), contains('bearer ***'));
  });

  test('local host no TLS warn', () {
    expect(Security.shouldWarnPlaintext('127.0.0.1', false), isFalse);
    expect(Security.shouldWarnPlaintext('10.0.2.2', false), isFalse);
    expect(Security.shouldWarnPlaintext('example.com', false), isTrue);
    expect(Security.shouldWarnPlaintext('example.com', true), isFalse);
  });
}
