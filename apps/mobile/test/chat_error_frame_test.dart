import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/services/chat_controller.dart';

void main() {
  test('register_ack with empty error is not an error frame', () {
    expect(ChatController.isErrorFrame({'type': 'register_ack', 'ok': true, 'error': ''}), isFalse);
    expect(ChatController.isErrorFrame({'type': 'terminal_ack', 'error': ''}), isFalse);
    expect(ChatController.isErrorFrame({'type': 'reply', 'content': 'x'}), isFalse);
    expect(ChatController.isErrorFrame({'type': 'tool_result', 'ok': true, 'error': 'x'}), isFalse);
  });

  test('real failures are error frames', () {
    expect(ChatController.isErrorFrame({'type': 'error', 'error': 'boom'}), isTrue);
    expect(ChatController.isErrorFrame({'type': 'error'}), isTrue);
    expect(ChatController.isErrorFrame({'type': 'run_done', 'error': 'agent crashed'}), isTrue);
    expect(ChatController.isErrorFrame({'type': 'x', 'error': {'code': 1}}), isTrue);
  });

  test('short permission decisions resolve to the button data', () {
    const rows = [
      [
        {'text': 'Allow', 'data': 'perm:r1:allow'},
        {'text': 'Deny', 'data': 'perm:r1:deny'},
        {'text': 'Allow all', 'data': 'perm:r1:allow_all'},
      ]
    ];
    expect(ChatController.resolvePermissionAction('deny', rows), 'perm:r1:deny');
    expect(ChatController.resolvePermissionAction('allow', rows), 'perm:r1:allow');
    expect(ChatController.resolvePermissionAction('allow_all', rows), 'perm:r1:allow_all');
    expect(ChatController.resolvePermissionAction('perm:x:deny', rows), 'perm:x:deny');
    expect(ChatController.resolvePermissionAction('deny', const []), 'deny');
  });
}
