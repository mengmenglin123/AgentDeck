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

class _QuietBridge extends BridgeClient {
  _QuietBridge(ConnectionConfig config) : super(config: config);

  @override
  Future<void> connect(
      {Duration timeout = const Duration(seconds: 12)}) async {}

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

  group('stream batching', () {
    Future<(ChatController, _QuietBridge)> connected({
      Duration interval = const Duration(milliseconds: 20),
    }) async {
      late _QuietBridge bridge;
      final controller = ChatController(
        config: config,
        session: session,
        streamFlushInterval: interval,
        bridgeFactory: (c) => bridge = _QuietBridge(c),
      );
      await controller.connect();
      expect(controller.connected, isTrue);
      return (controller, bridge);
    }

    Map<String, dynamic> delta(String text, {bool done = false}) => {
          'type': 'reply_stream',
          'session_key': session.sessionKey,
          'delta': text,
          'done': done,
        };

    test('coalesces reply_stream deltas into one notification', () async {
      final (controller, bridge) = await connected();
      var notifications = 0;
      controller.addListener(() => notifications++);

      for (var i = 0; i < 50; i++) {
        bridge.onMessage!(delta('x'));
      }
      // Reducer state is current immediately; listeners are deferred.
      expect(controller.messages.single.content, 'x' * 50);
      expect(controller.messages.single.streaming, isTrue);
      expect(notifications, 0);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(notifications, 1);
      controller.dispose();
    });

    test('final chunk and other frames notify immediately', () async {
      final (controller, bridge) = await connected();
      var notifications = 0;
      controller.addListener(() => notifications++);

      bridge.onMessage!(delta('he'));
      bridge.onMessage!(delta('llo', done: true));
      expect(notifications, 1);
      expect(controller.messages.single.content, 'hello');
      expect(controller.messages.single.streaming, isFalse);

      // The pending coalesced flush was absorbed by the immediate notify.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(notifications, 1);
      controller.dispose();
    });

    test('pending flush is dropped on dispose', () async {
      final (controller, bridge) = await connected();
      var notifications = 0;
      controller.addListener(() => notifications++);
      bridge.onMessage!(delta('late'));
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(notifications, 0);
    });

    test('zero interval keeps per-chunk notifications', () async {
      final (controller, bridge) = await connected(interval: Duration.zero);
      var notifications = 0;
      controller.addListener(() => notifications++);
      bridge.onMessage!(delta('a'));
      bridge.onMessage!(delta('b'));
      expect(notifications, 2);
      controller.dispose();
    });
  });
}
