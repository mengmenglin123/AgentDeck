import 'package:flutter/material.dart';

import '../models/connection_config.dart';
import '../models/session_info.dart';
import '../models/transcript.dart';
import '../services/audit_log.dart';
import '../services/chat_controller.dart';
import 'audit_screen.dart';

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
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _chat.connect();
    await _chat.reloadTranscript();
  }

  void _onChat() {
    if (!mounted) return;
    setState(() {});
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

  Future<void> _pickMode() async {
    const options = ['default', 'plan', 'acceptEdits', 'bypassPermissions'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Permission mode')),
            ...options.map(
              (m) => ListTile(
                title: Text(m),
                trailing: m == _chat.mode ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, m),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await _chat.sendSlash('/mode $selected');
      setState(() => _chat.mode = selected);
    }
  }

  Future<void> _pickModel() async {
    const options = ['mock-sonnet', 'mock-codex', 'mock-hermes'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Model')),
            ...options.map(
              (m) => ListTile(
                title: Text(m),
                trailing: m == _chat.model ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, m),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await _chat.sendSlash('/model $selected');
      setState(() => _chat.model = selected);
    }
  }

  Future<void> _pickDir() async {
    final ctrl = TextEditingController(text: _chat.workdir);
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Working directory'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: '/absolute/path',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (path != null && path.isNotEmpty) {
      await _chat.sendSlash('/dir $path');
      setState(() => _chat.workdir = path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.session.displayTitle, style: const TextStyle(fontSize: 16)),
            Text(
              '${widget.session.project} · ${_chat.model}',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reload transcript',
            onPressed: _chat.reloading ? null : _chat.reloadTranscript,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Audit log',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AuditScreen(audit: _chat.audit)),
              );
            },
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: _StatusChip(
                connecting: _chat.connecting,
                connected: _chat.connected,
                typing: _chat.typing,
                runActive: _chat.runActive,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_chat.error != null)
            Material(
              color: cs.errorContainer,
              child: ListTile(
                dense: true,
                title: Text(
                  _chat.error!,
                  style: TextStyle(color: cs.onErrorContainer),
                ),
                trailing: TextButton(
                  onPressed: () => _chat.connect(),
                  child: const Text('Retry'),
                ),
              ),
            ),
          _AgentToolbar(
            mode: _chat.mode,
            model: _chat.model,
            workdir: _chat.workdir,
            runActive: _chat.runActive,
            connected: _chat.connected,
            onMode: _pickMode,
            onModel: _pickModel,
            onDir: _pickDir,
            onStop: _chat.cancelRun,
            onStatus: () => _chat.sendSlash('/status'),
          ),
          Expanded(
            child: _chat.messages.isEmpty
                ? _EmptyChat(
                    project: widget.session.project,
                    connected: _chat.connected,
                    connecting: _chat.connecting,
                  )
                : ListView.builder(
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
                        hintText: _chat.connected
                            ? 'Message…  (/perm for permission demo)'
                            : 'Connecting to agent…',
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
                  if (_chat.runActive)
                    IconButton.filledTonal(
                      tooltip: 'Stop run',
                      onPressed: _chat.cancelRun,
                      icon: const Icon(Icons.stop),
                    )
                  else
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

class _AgentToolbar extends StatelessWidget {
  const _AgentToolbar({
    required this.mode,
    required this.model,
    required this.workdir,
    required this.runActive,
    required this.connected,
    required this.onMode,
    required this.onModel,
    required this.onDir,
    required this.onStop,
    required this.onStatus,
  });

  final String mode;
  final String model;
  final String workdir;
  final bool runActive;
  final bool connected;
  final VoidCallback onMode;
  final VoidCallback onModel;
  final VoidCallback onDir;
  final VoidCallback onStop;
  final VoidCallback onStatus;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            ActionChip(label: Text('mode:$mode'), onPressed: connected ? onMode : null),
            const SizedBox(width: 6),
            ActionChip(label: Text('model:$model'), onPressed: connected ? onModel : null),
            const SizedBox(width: 6),
            ActionChip(
              label: Text(workdir.length > 24 ? '…${workdir.substring(workdir.length - 22)}' : workdir),
              onPressed: connected ? onDir : null,
            ),
            const SizedBox(width: 6),
            ActionChip(label: const Text('status'), onPressed: connected ? onStatus : null),
            const SizedBox(width: 6),
            ActionChip(
              avatar: Icon(Icons.stop, size: 16, color: runActive ? Colors.red : null),
              label: const Text('stop'),
              onPressed: (connected && runActive) ? onStop : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({
    required this.project,
    required this.connected,
    required this.connecting,
  });

  final String project;
  final bool connected;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final subtitle = connecting
        ? 'Connecting to host…'
        : connected
            ? 'Send a message to drive $project on your server.\nTry /help, /perm, or a normal task.'
            : 'Offline — tap Retry when the host is reachable.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('No messages yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.connecting,
    required this.connected,
    required this.typing,
    required this.runActive,
  });

  final bool connecting;
  final bool connected;
  final bool typing;
  final bool runActive;

  @override
  Widget build(BuildContext context) {
    final label = connecting
        ? 'connecting'
        : typing
            ? 'typing…'
            : runActive
                ? 'running'
                : connected
                    ? 'online'
                    : 'offline';
    final color = connecting
        ? Colors.orange
        : !connected
            ? Colors.red
            : (typing || runActive)
                ? Colors.blue
                : Colors.green;
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
