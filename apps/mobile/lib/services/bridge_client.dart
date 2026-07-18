import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../errors/app_errors.dart';
import '../models/connection_config.dart';
import 'package:uuid/uuid.dart';

typedef BridgeMessageHandler = void Function(Map<String, dynamic> payload);
typedef BridgeErrorHandler = void Function(Object error);
typedef BridgeCloseHandler = void Function();

/// Minimal Bridge WebSocket client (HuanHermes protocol subset).
class BridgeClient {
  BridgeClient({
    required this.config,
    this.onMessage,
    this.onError,
    this.onClose,
    WebSocketChannel Function(Uri uri, {Iterable<String>? protocols})?
    connector,
  }) : _connector = connector;

  final ConnectionConfig config;
  BridgeMessageHandler? onMessage;
  BridgeErrorHandler? onError;
  BridgeCloseHandler? onClose;
  final WebSocketChannel Function(Uri uri, {Iterable<String>? protocols})?
  _connector;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  Completer<void>? _registerCompleter;
  bool _closedByUser = false;

  bool get isConnected => _channel != null;

  Future<void> connect({Duration timeout = const Duration(seconds: 12)}) async {
    _closedByUser = false;
    _registerCompleter = Completer<void>();

    // Prefer query token (mock + protocol); also send headers when possible.
    final uri = Uri.parse(config.bridgeWsUrl);
    try {
      final channel = _connector != null
          ? _connector(uri)
          : WebSocketChannel.connect(uri);
      _channel = channel;
      _sub = channel.stream.listen(
        _onData,
        onError: (Object e, StackTrace st) {
          onError?.call(DisconnectedError(e.toString()));
        },
        onDone: () {
          _cleanupTimers();
          if (!_closedByUser) {
            onClose?.call();
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      throw DisconnectedError(e.toString());
    }

    register();
    try {
      await _registerCompleter!.future.timeout(timeout);
    } on TimeoutException {
      await close();
      throw ProtocolError('register_ack timeout');
    }

    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      try {
        ping();
      } catch (e) {
        onError?.call(e);
      }
    });
  }

  void register() {
    send({
      'type': 'register',
      'platform': config.platformName,
      'capabilities': ['text', 'buttons', 'typing', 'preview', 'terminal'],
      'metadata': {'version': '0.1.11', 'device_id': config.deviceId},
    });
  }

  Map<String, String> sendUserMessage({
    required String content,
    required String conversationId,
    String userId = 'user',
    String userName = 'User',
    String? sessionKeyOverride,
    List<Map<String, dynamic>> images = const [],
    List<Map<String, dynamic>> files = const [],
  }) {
    final sk = sessionKeyOverride ?? 'huan:${config.deviceId}:$conversationId';
    final replyCtx =
        'ctx-${const Uuid().v4().replaceAll('-', '').substring(0, 12)}';
    final msgId =
        'msg-${const Uuid().v4().replaceAll('-', '').substring(0, 12)}';
    send({
      'type': 'message',
      'msg_id': msgId,
      'session_key': sk,
      'user_id': userId,
      'user_name': userName,
      'content': content,
      'reply_ctx': replyCtx,
      'images': images,
      'files': files,
      'audio': null,
    });
    return {'session_key': sk, 'reply_ctx': replyCtx, 'msg_id': msgId};
  }

  void sendCardAction({
    required String sessionKey,
    required String action,
    required String replyCtx,
  }) {
    send({
      'type': 'card_action',
      'session_key': sessionKey,
      'action': action,
      'reply_ctx': replyCtx,
    });
  }

  void ping() {
    send({'type': 'ping', 'ts': DateTime.now().millisecondsSinceEpoch});
  }

  void cancel({required String sessionKey, String? replyCtx}) {
    send({
      'type': 'cancel',
      'session_key': sessionKey,
      'reply_ctx': replyCtx ?? '',
    });
  }

  /// Lightweight terminal channel (Host may map to PTY; Mock echoes).
  void terminalInput({
    required String sessionKey,
    required String data,
    String? streamId,
  }) {
    send({
      'type': 'terminal_input',
      'session_key': sessionKey,
      'data': data,
      if (streamId != null) 'stream_id': streamId,
    });
  }

  void terminalResize({
    required String sessionKey,
    int cols = 80,
    int rows = 24,
  }) {
    send({
      'type': 'terminal_resize',
      'session_key': sessionKey,
      'cols': cols,
      'rows': rows,
    });
  }

  void send(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null) throw DisconnectedError('not connected');
    ch.sink.add(jsonEncode(payload));
  }

  Future<void> close() async {
    _closedByUser = true;
    _cleanupTimers();
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _cleanupTimers() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _onData(dynamic data) {
    try {
      final Map<String, dynamic> payload;
      if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is! Map) {
          onError?.call(ProtocolError('invalid bridge payload'));
          return;
        }
        payload = Map<String, dynamic>.from(decoded);
      } else {
        onError?.call(ProtocolError('unsupported frame type'));
        return;
      }

      final type = payload['type']?.toString();
      if (type == 'register_ack') {
        if (payload['ok'] == true) {
          if (_registerCompleter != null && !_registerCompleter!.isCompleted) {
            _registerCompleter!.complete();
          }
        } else {
          final err = AuthError(
            payload['error']?.toString() ?? 'register denied',
          );
          if (_registerCompleter != null && !_registerCompleter!.isCompleted) {
            _registerCompleter!.completeError(err);
          }
          onError?.call(err);
        }
      }
      if (type == 'pong') return;
      onMessage?.call(payload);
    } catch (e) {
      onError?.call(e);
    }
  }
}
