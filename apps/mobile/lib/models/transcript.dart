enum EventKind {
  user,
  assistantDelta,
  assistantFinal,
  thinking,
  toolCall,
  toolResult,
  permission,
  system,
  error,
  runDone,
}

class TranscriptEvent {
  TranscriptEvent({
    required this.kind,
    this.text = '',
    Map<String, dynamic>? meta,
  }) : meta = meta ?? <String, dynamic>{};

  final EventKind kind;
  final String text;
  final Map<String, dynamic> meta;
}

class TranscriptMessage {
  TranscriptMessage({
    required this.role,
    required this.content,
    this.streaming = false,
    Map<String, dynamic>? meta,
    DateTime? at,
  }) : meta = meta ?? <String, dynamic>{},
       at = at ?? DateTime.now();

  /// user | assistant | system | tool | permission
  final String role;
  String content;
  bool streaming;
  final Map<String, dynamic> meta;

  /// Local client timestamp (not Host authoritative).
  final DateTime at;

  TranscriptMessage copyWith({String? content, bool? streaming}) {
    return TranscriptMessage(
      role: role,
      content: content ?? this.content,
      streaming: streaming ?? this.streaming,
      meta: Map<String, dynamic>.from(meta),
      at: at,
    );
  }
}

/// Permission/action buttons arrive either flat (`[{text,data}]`) or as rows
/// (`[[{text,data}, ...]]`, the Bridge/Telegram shape). Returns them flat.
List<Map<String, dynamic>> flattenButtons(dynamic raw) {
  final out = <Map<String, dynamic>>[];
  if (raw is List) {
    for (final row in raw) {
      if (row is List) {
        for (final b in row) {
          if (b is Map) out.add(Map<String, dynamic>.from(b));
        }
      } else if (row is Map) {
        out.add(Map<String, dynamic>.from(row));
      }
    }
  }
  return out;
}

/// Reduce bridge host events into a list of UI messages.
class TranscriptReducer {
  final List<TranscriptMessage> messages = <TranscriptMessage>[];
  int? _streamingIdx;
  int lastSeq = 0;

  void reset() {
    messages.clear();
    _streamingIdx = null;
    lastSeq = 0;
  }

  void hydrate(List<Map<String, dynamic>> rows) {
    reset();
    for (final row in rows) {
      final role = (row['role'] ?? 'system').toString();
      final content = (row['content'] ?? '').toString();
      messages.add(TranscriptMessage(role: role, content: content));
    }
  }

  List<TranscriptMessage> apply(TranscriptEvent event) {
    switch (event.kind) {
      case EventKind.user:
        _streamingIdx = null;
        messages.add(
          TranscriptMessage(
            role: 'user',
            content: event.text,
            meta: event.meta,
          ),
        );
      case EventKind.assistantDelta:
        if (_streamingIdx == null) {
          messages.add(
            TranscriptMessage(
              role: 'assistant',
              content: event.text,
              streaming: true,
              meta: event.meta,
            ),
          );
          _streamingIdx = messages.length - 1;
        } else {
          final msg = messages[_streamingIdx!];
          final full = event.meta['full_text'];
          if (full is String) {
            msg.content = full;
          } else {
            msg.content += event.text;
          }
          final done = event.meta['done'] == true;
          msg.streaming = !done;
          if (done) _streamingIdx = null;
        }
      case EventKind.assistantFinal:
        if (_streamingIdx != null) {
          messages[_streamingIdx!].content = event.text;
          messages[_streamingIdx!].streaming = false;
          _streamingIdx = null;
        } else {
          if (messages.isNotEmpty &&
              messages.last.role == 'assistant' &&
              messages.last.content == event.text &&
              !messages.last.streaming) {
            break;
          }
          messages.add(
            TranscriptMessage(
              role: 'assistant',
              content: event.text,
              meta: event.meta,
            ),
          );
        }
      case EventKind.thinking:
        messages.add(
          TranscriptMessage(
            role: 'system',
            content: 'thinking: ${event.text}',
            meta: event.meta,
          ),
        );
      case EventKind.toolCall:
        messages.add(
          TranscriptMessage(
            role: 'tool',
            content: 'call: ${event.text}',
            meta: event.meta,
          ),
        );
      case EventKind.toolResult:
        messages.add(
          TranscriptMessage(
            role: 'tool',
            content: 'result: ${event.text}',
            meta: event.meta,
          ),
        );
      case EventKind.permission:
        messages.add(
          TranscriptMessage(
            role: 'permission',
            content: event.text,
            meta: event.meta,
          ),
        );
      case EventKind.error:
        messages.add(
          TranscriptMessage(
            role: 'system',
            content: 'error: ${event.text}',
            meta: event.meta,
          ),
        );
      case EventKind.runDone:
        if (_streamingIdx != null) {
          messages[_streamingIdx!].streaming = false;
          _streamingIdx = null;
        }
        final status = event.meta['status']?.toString() ?? 'done';
        messages.add(
          TranscriptMessage(
            role: 'system',
            content: event.text.isEmpty ? 'run $status' : event.text,
            meta: event.meta,
          ),
        );
      case EventKind.system:
        messages.add(
          TranscriptMessage(
            role: 'system',
            content: event.text,
            meta: event.meta,
          ),
        );
    }
    lastSeq += 1;
    return messages;
  }

  List<TranscriptMessage> applyBridgePayload(Map<String, dynamic> payload) {
    final t = payload['type']?.toString();
    switch (t) {
      case 'reply_stream':
        return apply(
          TranscriptEvent(
            kind: EventKind.assistantDelta,
            text: (payload['delta'] ?? '').toString(),
            meta: {
              'full_text': payload['full_text'],
              'done': payload['done'] == true,
              'session_key': payload['session_key'],
              'reply_ctx': payload['reply_ctx'],
            },
          ),
        );
      case 'reply':
        return apply(
          TranscriptEvent(
            kind: EventKind.assistantFinal,
            text: (payload['content'] ?? '').toString(),
            meta: {
              'session_key': payload['session_key'],
              'reply_ctx': payload['reply_ctx'],
              'format': payload['format'],
            },
          ),
        );
      case 'buttons':
        return apply(
          TranscriptEvent(
            kind: EventKind.permission,
            text: (payload['content'] ?? 'Permission required').toString(),
            meta: {
              'buttons': payload['buttons'] ?? [],
              'session_key': payload['session_key'],
              'reply_ctx': payload['reply_ctx'],
            },
          ),
        );
      case 'thinking':
        return apply(
          TranscriptEvent(
            kind: EventKind.thinking,
            text: (payload['content'] ?? payload['text'] ?? '').toString(),
            meta: payload,
          ),
        );
      case 'tool_call':
        final name = payload['name'] ?? 'tool';
        final input = payload['input'] ?? '';
        return apply(
          TranscriptEvent(
            kind: EventKind.toolCall,
            text: '$name $input',
            meta: payload,
          ),
        );
      case 'tool_result':
        final name = payload['name'] ?? 'tool';
        final output = payload['output'] ?? payload['content'] ?? '';
        return apply(
          TranscriptEvent(
            kind: EventKind.toolResult,
            text: '$name → $output',
            meta: payload,
          ),
        );
      case 'run_done':
        return apply(
          TranscriptEvent(
            kind: EventKind.runDone,
            text: (payload['content'] ?? '').toString(),
            meta: {
              'status': payload['status'] ?? 'completed',
              'session_key': payload['session_key'],
              'reply_ctx': payload['reply_ctx'],
            },
          ),
        );
      case 'typing_start':
      case 'typing_stop':
        // UI uses dedicated typing flag; skip transcript noise
        return messages;
      case 'preview_start':
        return apply(
          TranscriptEvent(
            kind: EventKind.system,
            text: (payload['content'] ?? 'preview…').toString(),
            meta: payload,
          ),
        );
      case 'update_message':
        return apply(
          TranscriptEvent(
            kind: EventKind.assistantDelta,
            text: (payload['content'] ?? '').toString(),
            meta: {
              'full_text': payload['content'],
              'done': false,
              'preview_handle': payload['preview_handle'],
            },
          ),
        );
      case 'card':
        return apply(
          TranscriptEvent(
            kind: EventKind.permission,
            text: (payload['content'] ??
                    payload['text'] ??
                    payload['title'] ??
                    'card')
                .toString(),
            meta: {
              'buttons': payload['buttons'] ?? [],
              'session_key': payload['session_key'],
              'reply_ctx': payload['reply_ctx'],
            },
          ),
        );
      case 'register_ack':
        final ok = payload['ok'] == true;
        return apply(
          TranscriptEvent(
            kind: ok ? EventKind.system : EventKind.error,
            text: ok
                ? 'registered'
                : (payload['error']?.toString() ?? 'register failed'),
            meta: payload,
          ),
        );
      default:
        return apply(
          TranscriptEvent(
            kind: EventKind.system,
            text: 'event:$t',
            meta: payload,
          ),
        );
    }
  }
}
