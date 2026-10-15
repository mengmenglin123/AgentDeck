import 'dart:async';

import 'package:flutter/foundation.dart';

import '../errors/app_errors.dart';
import '../models/connection_config.dart';
import '../models/host_capabilities.dart';
import '../models/session_info.dart';
import '../models/transcript.dart';
import 'audit_log.dart';
import 'notification_service.dart';
import 'offline_queue.dart';
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
    this.streamFlushInterval = const Duration(milliseconds: 32),
  })  : _bridgeFactory = bridgeFactory,
        _mgmtFactory = mgmtFactory ?? ((c) => MgmtClient(config: c)),
        audit = audit ?? AuditLog();

  final ConnectionConfig config;
  SessionInfo session;
  final BridgeClient Function(ConnectionConfig config)? _bridgeFactory;
  final MgmtClient Function(ConnectionConfig config) _mgmtFactory;
  final AuditLog audit;

  /// Streaming deltas (`reply_stream`/`thinking`) are applied to the reducer
  /// immediately, but listeners are notified at most once per interval so a
  /// fast token stream does not rebuild the whole chat page per chunk.
  final Duration streamFlushInterval;
  Timer? _streamFlushTimer;
  final PromptHistoryStore promptHistory = PromptHistoryStore();
  final OfflineQueue offlineQueue = OfflineQueue();

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
  CapabilitySet capabilitySet = CapabilitySet.from(const [
    'stream',
    'buttons',
    'cancel',
    'workdir',
    'mode',
    'model',
    'tools_visible',
  ]);
  int reconnectAttempts = 0;

  /// Device-local; mirrored from AppSettings when ChatScreen boots.
  int maxReconnectAttempts = 5;
  bool autoReconnect = true;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _offlineLoaded = false;
  String? reconnectHint;

  static const hintReconnected = '已重连';

  /// Notifies immediately and drops any pending coalesced stream notification.
  /// Safe to call after [dispose] (late async work becomes a no-op).
  @override
  void notifyListeners() {
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    if (_disposed) return;
    super.notifyListeners();
  }

  void _notifyCoalesced() {
    if (_disposed || _streamFlushTimer != null) return;
    if (streamFlushInterval <= Duration.zero) {
      notifyListeners();
      return;
    }
    _streamFlushTimer = Timer(streamFlushInterval, notifyListeners);
  }

  List<TranscriptMessage> get messages => List.unmodifiable(reducer.messages);
  // Avoid copying the transcript just to check emptiness on every rebuild.
  bool get isEmpty => reducer.messages.isEmpty;
  List<String> get capabilities => capabilitySet.toList();
  bool hasCap(String c) => capabilitySet.isEmpty || capabilitySet.supports(c);

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
      if (!_offlineLoaded) {
        await offlineQueue.load();
        _offlineLoaded = true;
      }
      await _flushOfflineQueue();
      reconnectAttempts = 0;
      reconnectHint = silent ? hintReconnected : null;
      if (silent) {
        // Clear brief status after a beat so banner does not stick forever.
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (!_disposed && reconnectHint == hintReconnected) {
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
      error = 'Bridge 已断开：${e.message}';
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
      final data = await _mgmtFactory(
        config,
      ).sessionDetail(session.id, project: session.project);
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
        capabilitySet = CapabilitySet.from(caps);
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

  Future<bool> send(
    String text, {
    List<Map<String, dynamic>> images = const [],
    List<Map<String, dynamic>> files = const [],
  }) async {
    final content = text.trim();
    if (content.isEmpty && images.isEmpty && files.isEmpty) return false;
    if (!connected || _bridge == null) {
      await connect();
      if (!connected || _bridge == null) return false;
    }
    sending = true;
    error = null;
    final display = content.isEmpty
        ? '[attachment: ${images.length} image(s), ${files.length} file(s)]'
        : content;
    var accepted = false;
    try {
      final meta = _bridge!.sendUserMessage(
        content: content,
        conversationId: session.id,
        project: session.project,
        sessionKeyOverride: session.sessionKey,
        images: images,
        files: files,
      );
      lastReplyCtx = meta['reply_ctx'];
      runActive = true;
      accepted = true;
    } on DisconnectedError catch (e) {
      connected = false;
      if (images.isNotEmpty || files.isNotEmpty) {
        error = '附件未发送，请恢复连接后重试';
      } else if (offlineQueue.enabled && content.isNotEmpty) {
        accepted = offlineQueue.enqueue(
          sessionKey: session.sessionKey,
          content: content,
        );
        error = accepted ? '消息已加入离线队列' : '离线队列已满';
      } else {
        error = e.message;
      }
    } catch (e) {
      error = e.toString();
    }
    if (accepted) {
      reducer.apply(TranscriptEvent(kind: EventKind.user, text: display));
      if (content.isNotEmpty && !content.startsWith('/')) {
        await promptHistory.addRecent(content);
      }
      audit.add(
        'chat.send',
        detail: display.length > 80 ? '${display.substring(0, 80)}…' : display,
      );
    }
    sending = false;
    notifyListeners();
    return accepted;
  }

  /// Apply project capabilities from Sessions list (P2-3).
  void applyProjectCapabilities(List<String> caps) {
    if (caps.isEmpty) return;
    capabilitySet = CapabilitySet.from(caps);
    notifyListeners();
  }

  Future<bool> sendSlash(String command) => send(command);

  /// Flush queued offline messages after reconnect.
  Future<void> _flushOfflineQueue() async {
    if (offlineQueue.isEmpty || !connected || _bridge == null) return;
    final sent = await offlineQueue.flush((msg) async {
      try {
        _bridge!.sendUserMessage(
          content: msg.content,
          conversationId: session.id,
          project: session.project,
          sessionKeyOverride: session.sessionKey,
        );
        return true;
      } catch (_) {
        return false;
      }
    });
    if (sent > 0) {
      audit.add('offline_queue.flushed', detail: '$sent message(s)');
      notifyListeners();
    }
  }

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
      _bridge!.cancel(
        sessionKey: session.sessionKey,
        replyCtx: lastReplyCtx,
        project: session.project,
      );
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
        project: session.project,
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
      reconnectHint = '已断开 · 自动重连已关闭';
      notifyListeners();
      return;
    }
    final maxA = maxReconnectAttempts.clamp(1, 10);
    if (reconnectAttempts >= maxA) {
      reconnectHint = '已重试 $maxA 次，停止自动重连';
      notifyListeners();
      return;
    }
    reconnectAttempts += 1;
    final delay = Duration(seconds: reconnectAttempts * 2);
    audit.add(
      'bridge.reconnect_scheduled',
      detail: 'attempt=$reconnectAttempts/$maxA delay=${delay.inSeconds}s',
    );
    reconnectHint = '${delay.inSeconds} 秒后重连（第 $reconnectAttempts/$maxA 次）…';
    notifyListeners();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_disposed && !connected) {
        reconnectHint = '重连中…';
        notifyListeners();
        connect(silent: true);
      }
    });
  }

  void _onBridgeMessage(Map<String, dynamic> payload) {
    // Late frames can arrive after the screen disposed this controller.
    if (_disposed) return;
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
      // Show notification when task completes
      final summary = payload['summary']?.toString() ?? 'Task completed';
      NotificationService.instance.showTaskComplete(
        sessionKey: session.sessionKey,
        sessionName: session.displayTitle,
        summary: summary,
      );
    }
    if (type == 'card') {
      // Permission request from agent — show notification
      final text = (payload['content'] ?? payload['text'])?.toString() ??
          'Agent needs permission';
      final buttons = payload['buttons'] as List? ?? [];
      if (buttons.isNotEmpty) {
        NotificationService.instance.show(
          id: 'perm_${session.displayTitle}'.hashCode & 0x7FFFFFFF,
          title: '需要权限：${session.displayTitle}',
          body: text.length > 100 ? '${text.substring(0, 100)}...' : text,
          payload: 'permission:${session.sessionKey}',
        );
      }
    }
    if (type == 'error' || (payload['error'] != null)) {
      // Task error — show notification
      final errorMsg = payload['error']?.toString() ??
          payload['message']?.toString() ??
          'Unknown error';
      NotificationService.instance.showError(
        title: '出错：${session.displayTitle}',
        message: errorMsg,
      );
    }
    reducer.applyBridgePayload(payload);
    final streamingDelta =
        (type == 'reply_stream' && payload['done'] != true) ||
            type == 'thinking';
    if (streamingDelta) {
      _notifyCoalesced();
    } else {
      notifyListeners();
    }
  }

  void _onBridgeError(Object e) {
    if (_disposed) return;
    error = e.toString();
    audit.add('bridge.on_error', detail: e.toString(), level: 'error');
    notifyListeners();
  }

  void _onBridgeClose() {
    if (_disposed) return;
    connected = false;
    // Notify user about disconnection
    NotificationService.instance.show(
      id: 'disconnect_${session.displayTitle}'.hashCode & 0x7FFFFFFF,
      title: '已断开：${session.displayTitle}',
      body: 'Bridge 连接已断开，正在尝试重连…',
    );
    typing = false;
    runActive = false;
    error = error ?? 'Bridge 连接已关闭';
    audit.add('bridge.closed', level: 'warn');
    notifyListeners();
    _scheduleReconnect();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _bridge?.close();
    super.dispose();
  }
}
