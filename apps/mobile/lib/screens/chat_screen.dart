import 'package:flutter/material.dart';

import '../models/connection_config.dart';
import '../models/session_info.dart';
import '../models/transcript.dart';
import '../services/chat_controller.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.config,
    required this.session,
  });

  final ConnectionConfig config;
  final SessionInfo session;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatController _chat;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _chat = ChatController(config: widget.config, session: widget.session);
    _chat.addListener(_onChat);
    _chat.connect();
  }

  void _onChat() {
    if (!mounted) return;
    setState(() {});
    // auto-scroll after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _chat.removeListener(_onChat);
    _chat.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    _input.clear();
    await _chat.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session.displayTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: _StatusChip(
                connecting: _chat.connecting,
                connected: _chat.connected,
                typing: _chat.typing,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_chat.error != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                dense: true,
                title: Text(
                  _chat.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                ),
                trailing: TextButton(
                  onPressed: () => _chat.connect(),
                  child: const Text('Retry'),
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _chat.messages.length,
              itemBuilder: (context, i) {
                final m = _chat.messages[i];
                return _MessageBubble(
                  message: m,
                  onPermission: _chat.respondPermission,
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: 'Message…  (/perm for permission demo)',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withOpacity(0.35),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      enabled: _chat.connected && !_chat.sending,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: (_chat.connected && !_chat.sending) ? _send : null,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.connecting,
    required this.connected,
    required this.typing,
  });

  final bool connecting;
  final bool connected;
  final bool typing;

  @override
  Widget build(BuildContext context) {
    final label = connecting
        ? 'connecting'
        : typing
            ? 'typing…'
            : connected
                ? 'online'
                : 'offline';
    final color = connecting
        ? Colors.orange
        : connected
            ? Colors.green
            : Colors.red;
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      avatar: Icon(Icons.circle, size: 10, color: color),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onPermission,
  });

  final TranscriptMessage message;
  final Future<void> Function(String action) onPermission;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final role = message.role;
    final align = role == 'user' ? Alignment.centerRight : Alignment.centerLeft;
    Color bg;
    Color fg;
    switch (role) {
      case 'user':
        bg = cs.primary;
        fg = cs.onPrimary;
      case 'assistant':
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurface;
      case 'permission':
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
      case 'tool':
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
      default:
        bg = cs.surfaceContainerHigh;
        fg = cs.onSurfaceVariant;
    }

    final buttons = _parseButtons(message.meta['buttons']);

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
        child: Card(
          color: bg,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role + (message.streaming ? ' · streaming' : ''),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: fg.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(message.content, style: TextStyle(color: fg)),
                if (role == 'permission' && buttons.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: buttons.map((b) {
                      return FilledButton.tonal(
                        onPressed: () => onPermission(b.action),
                        child: Text(b.label),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_Btn> _parseButtons(dynamic raw) {
    if (raw is! List) return const [];
    final out = <_Btn>[];
    for (final row in raw) {
      if (row is! List) continue;
      for (final item in row) {
        if (item is! Map) continue;
        final text = (item['text'] ?? item['label'] ?? 'Action').toString();
        final data = (item['data'] ?? item['action'] ?? '').toString();
        if (data.isEmpty) continue;
        out.add(_Btn(label: text, action: data));
      }
    }
    return out;
  }
}

class _Btn {
  const _Btn({required this.label, required this.action});
  final String label;
  final String action;
}
