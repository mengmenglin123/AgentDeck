import 'package:flutter/foundation.dart';

import '../errors/app_errors.dart';
import '../models/connection_config.dart';
import '../models/session_info.dart';
import '../models/transcript.dart';
import 'bridge_client.dart';

class ChatController extends ChangeNotifier {
  ChatController({
    required this.config,
    required this.session,
    BridgeClient Function(ConnectionConfig config)? bridgeFactory,
  }) : _bridgeFactory = bridgeFactory;

  final ConnectionConfig config;
  final SessionInfo session;
  final BridgeClient Function(ConnectionConfig config)? _bridgeFactory;

  final TranscriptReducer reducer = TranscriptReducer();
  BridgeClient? _bridge;

  bool connecting = false;
  bool connected = false;
  bool sending = false;
  String? error;
  String? lastReplyCtx;
  bool typing = false;

  List<TranscriptMessage> get messages => List.unmodifiable(reducer.messages);

  Future<void> connect() async {
    if (connected || connecting) return;
    connecting = true;
    error = null;
    notifyListeners();
    try {
      final client = (_bridgeFactory ??
          ((ConnectionConfig c) => BridgeClient(
                config: c,
                onMessage: _onBridgeMessage,
                onError: _onBridgeError,
                onClose: _onBridgeClose,
              )))(config);
      // ensure handlers if factory provided custom client without hooks
      client.onMessage ??= _onBridgeMessage;
      client.onError ??= _onBridgeError;
      client.onClose ??= _onBridgeClose;
      _bridge = client;
      await client.connect();
      connected = true;
    } on AuthError catch (e) {
      error = e.message;
      connected = false;
    } on DisconnectedError catch (e) {
      error = 'Bridge disconnected: ${e.message}';
      connected = false;
    } on ProtocolError catch (e) {
      error = e.message;
      connected = false;
    } catch (e) {
      error = e.toString();
      connected = false;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _bridge?.close();
    _bridge = null;
    connected = false;
    typing = false;
    notifyListeners();
  }

  Future<void> send(String text) async {
    final content = text.trim();
    if (content.isEmpty) return;
    if (!connected || _bridge == null) {
      await connect();
      if (!connected || _bridge == null) return;
    }
    sending = true;
    error = null;
    reducer.apply(
      TranscriptEvent(kind: EventKind.user, text: content),
    );
    notifyListeners();
    try {
      final meta = _bridge!.sendUserMessage(
        content: content,
        conversationId: session.id,
        sessionKeyOverride: session.sessionKey,
      );
      lastReplyCtx = meta['reply_ctx'];
    } on DisconnectedError catch (e) {
      error = e.message;
      connected = false;
    } catch (e) {
      error = e.toString();
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<void> respondPermission(String action) async {
    if (_bridge == null || !connected) return;
    final replyCtx = lastReplyCtx ?? '';
    // remove last pending permission bubble optional; keep history
    reducer.apply(
      TranscriptEvent(
        kind: EventKind.system,
        text: 'permission: $action',
      ),
    );
    notifyListeners();
    try {
      _bridge!.sendCardAction(
        sessionKey: session.sessionKey,
        action: action,
        replyCtx: replyCtx,
      );
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  void _onBridgeMessage(Map<String, dynamic> payload) {
    final type = payload['type']?.toString();
    if (type == 'typing_start') {
      typing = true;
      notifyListeners();
      return;
    }
    if (type == 'typing_stop') {
      typing = false;
      notifyListeners();
      // still record lightly? skip noise
      return;
    }
    if (payload['reply_ctx'] != null) {
      lastReplyCtx = payload['reply_ctx'].toString();
    }
    // Filter events for this session when session_key present
    final sk = payload['session_key']?.toString();
    if (sk != null && sk.isNotEmpty && sk != session.sessionKey) {
      return;
    }
    reducer.applyBridgePayload(payload);
    notifyListeners();
  }

  void _onBridgeError(Object e) {
    error = e.toString();
    notifyListeners();
  }

  void _onBridgeClose() {
    connected = false;
    typing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    // fire-and-forget close
    _bridge?.close();
    super.dispose();
  }
}
