import 'dart:async';

import 'package:flutter/foundation.dart';

import '../errors/app_errors.dart';
import '../models/connection_config.dart';
import '../models/session_info.dart';
import '../models/transcript.dart';
import 'audit_log.dart';
import 'prompt_history_store.dart';
import 'bridge_client.dart';
import 'mgmt_client.dart';

class ChatController extends ChangeNotifier {
  ChatController({
    required this.config,
    required this.session,
    BridgeClient Function(ConnectionConfig config)? bridgeFactory,
    MgmtClient Function(ConnectionConfig config)? mgmtFactory,
    AuditLog? audit,
  })  : _bridgeFactory = bridgeFactory,
        _mgmtFactory = mgmtFactory ?? ((c) => MgmtClient(config: c)),
        audit = audit ?? AuditLog();

  final ConnectionConfig config;
  SessionInfo session;
  final BridgeClient Function(ConnectionConfig config)? _bridgeFactory;
  final MgmtClient Function(ConnectionConfig config) _mgmtFactory;
  final AuditLog audit;
  final PromptHistoryStore promptHistory = PromptHistoryStore();

  final TranscriptReducer reducer = TranscriptReducer();
  BridgeClient? _bridge;

  bool connecting = false;
  bool connected = false;
  bool sending = false;
  bool runActive = false;
  bool reloading = false;
  String? error;
  String? lastReplyCtx;
  bool typing = false;
  String mode = 'default';
  String model = 'mock-sonnet';
  String workdir = '/workspace';
  List<String> capabilities = const [
    'stream',
    'buttons',
    'cancel',
    'workdir',
    'mode',
    'model',
    'tools_visible',
  ];
  int reconnectAttempts = 0;
  /// Device-local; mirrored from AppSettings when ChatScreen boots.
  int maxReconnectAttempts = 5;
  bool autoReconnect = true;
  Timer? _reconnectTimer;
  bool _disposed = false;
  String? reconnectHint;

  List<TranscriptMessage> get messages => List.unmodifiable(reducer.messages);
  bool get isEmpty => messages.isEmpty;
  bool hasCap(String c) =>
      capabilities.isEmpty || capabilities.contains(c);

  Future<void> connect({bool silent = false}) async {
    if (connected || connecting) return;
    connecting = true;
    if (!silent) error = null;
    notifyListeners();
    try {
      final client = (_bridgeFactory ??
          ((ConnectionConfig c) => BridgeClient(
                config: c,
                onMessage: _onBridgeMessage,
                onError: _onBridgeError,
                onClose: _onBridgeClose,
              )))(config);
      client.onMessage ??= _onBridgeMessage;
      client.onError ??= _onBridgeError;
      client.onClose ??= _onBridgeClose;
      _bridge = client;
      await client.connect();
      connected = true;
      reconnectAttempts = 0;
      reconnectHint = silent ? 'Reconnected' : null;
      if (silent) {
        // Clear brief status after a beat so banner does not stick forever.
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (!_disposed && reconnectHint == 'Reconnected') {
            reconnectHint = null;
            notifyListeners();
          }
        });
      }
      audit.add('bridge.connected', detail: config.bridgeWsUrlRedacted);
    } on AuthError catch (e) {
      error = e.message;
      connected = false;
      audit.add('bridge.auth_error', detail: e.message, level: 'error');
    } on DisconnectedError catch (e) {
      error = 'Bridge disconnected: ${e.message}';
      connected = false;
      audit.add('bridge.disconnected', detail: e.message, level: 'error');
    } on ProtocolError catch (e) {
      error = e.message;
      connected = false;
      audit.add('bridge.protocol_error', detail: e.message, level: 'error');
    } catch (e) {
      error = e.toString();
      connected = false;
      audit.add('bridge.error', detail: e.toString(), level: 'error');
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    await _bridge?.close();
    _bridge = null;
    connected = false;
    typing = false;
    runActive = false;
    notifyListeners();
  }

  /// Clear only the in-memory transcript view (does not delete Host history).
  void clearLocalTranscript() {
    reducer.reset();
    typing = false;
    runActive = false;
    error = null;
    notifyListeners();
    audit.add('session.clear_local', detail: session.id);
  }

  Future<void> reloadTranscript() async {
    reloading = true;
    notifyListeners();
    try {
      final data = await _mgmtFactory(config).sessionDetail(session.id, project: session.project);
      final rows = data['transcript'];
      if (rows is List) {
        final list = rows
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        reducer.hydrate(list);
      }
      mode = (data['mode'] ?? mode).toString();
      model = (data['model'] ?? model).toString();
      workdir = (data['workdir'] ?? workdir).toString();
      final caps = data['capabilities'];
      if (caps is List && caps.isNotEmpty) {
        capabilities = caps.map((e) => e.toString()).toList();
      }
      if (data['running'] == true) runActive = true;
      audit.add('session.reload', detail: session.id);
    } catch (e) {
      // non-fatal if host has no history yet
      audit.add('session.reload_failed', detail: e.toString(), level: 'warn');
    } finally {
      reloading = false;
      notifyListeners();
    }
  }

  Future<void> send(
    String text, {
    List<Map<String, dynamic>> images = const [],
    List<Map<String, dynamic>> files = const [],
  }) async {
    final content = text.trim();
    if (content.isEmpty && images.isEmpty && files.isEmpty) return;
    if (!connected || _bridge == null) {
      await connect();
      if (!connected || _bridge == null) return;
    }
    sending = true;
    error = null;
    final display = content.isEmpty
        ? '[attachment: ${images.length} image(s), ${files.length} file(s)]'
        : content;
    reducer.apply(TranscriptEvent(kind: EventKind.user, text: display));
    notifyListeners();
    try {
      final meta = _bridge!.sendUserMessage(
        content: content,
        conversationId: session.id,
        sessionKeyOverride: session.sessionKey,
        images: images,
        files: files,
      );
      lastReplyCtx = meta['reply_ctx'];
      runActive = true;
      if (content.isNotEmpty && !content.startsWith('/')) {
        await promptHistory.addRecent(content);
      }
      audit.add(
        'chat.send',
        detail: display.length > 80 ? '${display.substring(0, 80)}…' : display,
      );
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

  /// Apply project capabilities from Sessions list (P2-3).
  void applyProjectCapabilities(List<String> caps) {
    if (caps.isEmpty) return;
    capabilities = List<String>.from(caps);
    notifyListeners();
  }

  Future<void> sendSlash(String command) => send(command);

  /// Export current transcript as Markdown (client-side; no Host secrets).
  String exportTranscriptMarkdown() {
    final buf = StringBuffer();
    buf.writeln('# Session ${session.displayTitle}');
    buf.writeln();
    buf.writeln('- project: `${session.project}`');
    buf.writeln('- session_key: `${session.sessionKey}`');
    buf.writeln('- model: `$model` · mode: `$mode`');
    buf.writeln('- workdir: `$workdir`');
    buf.writeln('- exported: ${DateTime.now().toIso8601String()}');
    buf.writeln();
    for (final m in messages) {
      buf.writeln('## ${m.role}');
      buf.writeln();
      buf.writeln(m.content);
      buf.writeln();
    }
    return buf.toString();
  }

  String exportTranscriptPlain() {
    final buf = StringBuffer();
    for (final m in messages) {
      buf.writeln('[${m.role}] ${m.content}');
      buf.writeln();
    }
    return buf.toString();
  }

  void cancelReconnect() {
    _reconnectTimer?.cancel();
    reconnectAttempts = 0;
  }

  Future<void> reconnectNow() async {
    _reconnectTimer?.cancel();
    await disconnect();
    reconnectAttempts = 0;
    await connect();
  }

  Future<void> cancelRun() async {
    if (_bridge == null || !connected) return;
    try {
      _bridge!.cancel(sessionKey: session.sessionKey, replyCtx: lastReplyCtx);
      audit.add('chat.cancel', detail: lastReplyCtx ?? '');
      // also slash fallback
      // host accepts either
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> respondPermission(String action) async {
    if (_bridge == null || !connected) return;
    final replyCtx = lastReplyCtx ?? '';
    reducer.apply(
      TranscriptEvent(kind: EventKind.system, text: 'permission: $action'),
    );
    notifyListeners();
    try {
      _bridge!.sendCardAction(
        sessionKey: session.sessionKey,
        action: action,
        replyCtx: replyCtx,
      );
      audit.add('permission.action', detail: action);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  void _scheduleReconnect() {
    if (_disposed || connected || connecting) return;
    if (!autoReconnect) {
      reconnectHint = 'Disconnected · auto-reconnect off';
      notifyListeners();
      return;
    }
    final maxA = maxReconnectAttempts.clamp(1, 10);
    if (reconnectAttempts >= maxA) {
      reconnectHint = 'Reconnect gave up after $maxA attempts';
      notifyListeners();
      return;
    }
    reconnectAttempts += 1;
    final delay = Duration(seconds: reconnectAttempts * 2);
    audit.add('bridge.reconnect_scheduled', detail: 'attempt=$reconnectAttempts/$maxA delay=${delay.inSeconds}s');
    reconnectHint = 'Reconnecting in ${delay.inSeconds}s (attempt $reconnectAttempts/$maxA)…';
    notifyListeners();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_disposed && !connected) {
        reconnectHint = 'Reconnecting…';
        notifyListeners();
        connect(silent: true);
      }
    });
  }

  void _onBridgeMessage(Map<String, dynamic> payload) {
    final type = payload['type']?.toString();
    if (type == 'preview_start') {
      final ref = payload['ref_id']?.toString() ?? '';
      try {
        _bridge?.send({
          'type': 'preview_ack',
          'ref_id': ref,
          'preview_handle': 'app-${DateTime.now().millisecondsSinceEpoch}',
        });
      } catch (_) {}
    }
    if (type == 'typing_start') {
      typing = true;
      runActive = true;
      notifyListeners();
      return;
    }
    if (type == 'typing_stop') {
      typing = false;
      notifyListeners();
      return;
    }
    if (payload['reply_ctx'] != null) {
      lastReplyCtx = payload['reply_ctx'].toString();
    }
    final sk = payload['session_key']?.toString();
    if (sk != null && sk.isNotEmpty && sk != session.sessionKey) {
      return;
    }
    if (type == 'run_done') {
      runActive = false;
      typing = false;
    }
    reducer.applyBridgePayload(payload);
    notifyListeners();
  }

  void _onBridgeError(Object e) {
    error = e.toString();
    audit.add('bridge.on_error', detail: e.toString(), level: 'error');
    notifyListeners();
  }

  void _onBridgeClose() {
    connected = false;
    typing = false;
    runActive = false;
    error = error ?? 'Bridge connection closed';
    audit.add('bridge.closed', level: 'warn');
    notifyListeners();
    _scheduleReconnect();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _bridge?.close();
    super.dispose();
  }
}
