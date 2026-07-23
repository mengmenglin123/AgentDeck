import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/services/terminal_reconnect_policy.dart';

void main() {
  test('uses bounded exponential backoff', () {
    const policy = TerminalReconnectPolicy(
      maxAttempts: 5,
      maxDelay: Duration(seconds: 10),
    );

    expect(policy.delayForAttempt(1), const Duration(seconds: 1));
    expect(policy.delayForAttempt(2), const Duration(seconds: 2));
    expect(policy.delayForAttempt(4), const Duration(seconds: 8));
    expect(policy.delayForAttempt(5), const Duration(seconds: 10));
  });

  test('stops after configured retry count', () {
    const policy = TerminalReconnectPolicy(maxAttempts: 3);

    expect(policy.canRetry(0), isTrue);
    expect(policy.canRetry(2), isTrue);
    expect(policy.canRetry(3), isFalse);
  });
}
