import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/errors/app_errors.dart';
import 'package:huanhermes_app/models/connection_config.dart';
import 'package:huanhermes_app/models/session_info.dart';
import 'package:huanhermes_app/services/bridge_client.dart';
import 'package:huanhermes_app/services/chat_controller.dart';

class _FailingBridge extends BridgeClient {
  _FailingBridge(ConnectionConfig config) : super(config: config);

  @override
  Future<void> connect(
      {Duration timeout = const Duration(seconds: 12)}) async {}

  @override
  Map<String, String> sendUserMessage({
    required String content,
    required String conversationId,
    String? project,
    String userId = 'user',
    String userName = 'User',
    String? sessionKeyOverride,
    List<Map<String, dynamic>> images = const [],
    List<Map<String, dynamic>> files = const [],
  }) {
    throw DisconnectedError('test disconnect');
  }

  @override
  Future<void> close() async {}
}

void main() {
  final config = ConnectionConfig(
    bridgeToken: 'bridge',
    mgmtToken: 'mgmt',
    deviceId: 'test-device',
  );
  final session = SessionInfo(
    id: 's1',
    sessionKey: 'huan:test:s1',
    project: 'claude-code',
  );

  test('failed attachment send is not persisted to offline queue', () async {
    final controller = ChatController(
      config: config,
      session: session,
      bridgeFactory: _FailingBridge.new,
    );

    final sent = await controller.send(
      '',
      files: [
        {
          'name': 'secret.txt',
          'mime': 'text/plain',
          'size_bytes': 3,
          'data_base64': 'YWJj',
        },
      ],
    );

    expect(sent, isFalse);
    expect(controller.offlineQueue, isEmpty);
    expect(controller.error, contains('恢复连接后重试'));
    controller.dispose();
  });
}
