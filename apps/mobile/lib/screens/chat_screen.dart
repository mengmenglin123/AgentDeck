
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../models/session_info.dart';
import '../models/transcript.dart';
import '../services/app_settings_controller.dart';
import '../services/chat_controller.dart';
import '../widgets/markdown_lite.dart';
import 'audit_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.config,
    required this.session,
    this.projectCapabilities = const [],
  });

  final ConnectionConfig config;
  final SessionInfo session;
  final List<String> projectCapabilities;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatController _chat;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _pendingImages = [];
  final List<Map<String, dynamic>> _pendingFiles = [];
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();
  String _searchQ = '';
  bool _showTools = true;
  bool _stickToBottom = true;
  bool _showJumpBottom = false;
  int _hitIndex = 0;
  final Map<int, GlobalKey> _msgKeys = {};

  @override
  void initState() {
    super.initState();
    _chat = ChatController(config: widget.config, session: widget.session);
    try {
      _showTools = context.read<AppSettingsController>().showToolsDefault;
    } catch (_) {
      _showTools = true;
    }
    if (widget.projectCapabilities.isNotEmpty) {
      _chat.applyProjectCapabilities(widget.projectCapabilities);
    } else if (widget.session.project == 'hermes') {
      _chat.applyProjectCapabilities(const [
        'stream',
        'buttons',
        'cancel',
        'workdir',
        'mode',
        'model',
        'tools_visible',
      ]);
      _chat.model = 'mock-hermes';
    }
    _chat.addListener(_onChat);
    _scroll.addListener(_onScroll);
    _bootstrap();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 80;
    final showJump = !atBottom && pos.maxScrollExtent > 120;
    if (atBottom != _stickToBottom || showJump != _showJumpBottom) {
      setState(() {
        _stickToBottom = atBottom;
        _showJumpBottom = showJump;
      });
    }
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent + 80,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    setState(() {
      _stickToBottom = true;
      _showJumpBottom = false;
    });
  }

  Future<void> _bootstrap() async {
    await _chat.connect();
    await _chat.reloadTranscript();
  }

  void _onChat() {
    if (!mounted) return;
    setState(() {});
    if (!_stickToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || !_stickToBottom) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _chat.removeListener(_onChat);
    _chat.dispose();
    _input.dispose();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    final images = List<Map<String, dynamic>>.from(_pendingImages);
    final files = List<Map<String, dynamic>>.from(_pendingFiles);
    _input.clear();
    _pendingImages.clear();
    _pendingFiles.clear();
    setState(() {});
    await _chat.send(text, images: images, files: files);
  }

  Future<void> _attachDemo() async {
    // No file_picker dep: demo attachment via dialog (base64/text) for protocol path.
    final nameCtrl = TextEditingController(text: 'note.txt');
    final bodyCtrl = TextEditingController(text: 'hello from HuanHermes attach demo');
    final kind = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Attach (protocol demo)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sends Bridge message.files / images without native picker. '
              'Real camera/gallery can be wired later.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'filename')),
            TextField(controller: bodyCtrl, decoration: const InputDecoration(labelText: 'text content'), maxLines: 3),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'image'), child: const Text('As image meta')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'file'), child: const Text('As file')),
        ],
      ),
    );
    if (kind == null) return;
    final name = nameCtrl.text.trim().isEmpty ? 'attach.bin' : nameCtrl.text.trim();
    final b64 = base64Encode(utf8.encode(bodyCtrl.text));
    setState(() {
      if (kind == 'image') {
        _pendingImages.add({
          'name': name.endsWith('.png') ? name : '$name.png',
          'mime': 'image/png',
          'data_base64': b64,
          'note': 'demo-meta',
        });
      } else {
        _pendingFiles.add({
          'name': name,
          'mime': 'text/plain',
          'data_base64': b64,
        });
      }
    });
  }

  Future<void> _pickMode() async {
    if (!_chat.hasCap('mode')) return;
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
    if (!_chat.hasCap('model')) return;
    final options = widget.session.project == 'hermes'
        ? const ['mock-hermes', 'hermes-default']
        : const ['mock-sonnet', 'mock-codex', 'mock-hermes'];
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
    if (!_chat.hasCap('workdir')) return;
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

  Future<void> _openPromptHistory() async {
    final store = _chat.promptHistory;
    final recent = await store.recent();
    final favs = await store.favorites();
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, scroll) {
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              children: [
                ListTile(
                  title: Text('Prompts', style: Theme.of(ctx).textTheme.titleMedium),
                  subtitle: const Text('Local favorites + recent (device only)'),
                  trailing: IconButton(
                    tooltip: 'Clear recent',
                    onPressed: () async {
                      await store.clearRecent();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                ),
                if (favs.isNotEmpty) ...[
                  const ListTile(dense: true, title: Text('Favorites')),
                  for (final t in favs)
                    ListTile(
                      leading: const Icon(Icons.star, color: Colors.amber),
                      title: Text(t, maxLines: 3, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.star_border),
                        tooltip: 'Unfavorite',
                        onPressed: () async {
                          await store.removeFavorite(t);
                          if (ctx.mounted) Navigator.pop(ctx, '__refresh__');
                        },
                      ),
                      onTap: () => Navigator.pop(ctx, t),
                      onLongPress: () async {
                        await store.toggleFavorite(t);
                        if (ctx.mounted) Navigator.pop(ctx, '__refresh__');
                      },
                    ),
                ],
                const ListTile(dense: true, title: Text('Recent')),
                if (recent.isEmpty)
                  const ListTile(title: Text('No recent prompts yet')),
                for (final t in recent)
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(t, maxLines: 3, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: Icon(favs.contains(t) ? Icons.star : Icons.star_border),
                      tooltip: 'Toggle favorite',
                      onPressed: () async {
                        await store.toggleFavorite(t);
                        if (ctx.mounted) Navigator.pop(ctx, '__refresh__');
                      },
                    ),
                    onTap: () => Navigator.pop(ctx, t),
                  ),
                if (_input.text.trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.star_outline),
                    title: const Text('Favorite current draft'),
                    onTap: () async {
                      await store.toggleFavorite(_input.text);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
              ],
            );
          },
        );
      },
    );
    if (!mounted) return;
    if (picked == '__refresh__') {
      await _openPromptHistory();
      return;
    }
    if (picked != null && picked.isNotEmpty) {
      setState(() => _input.text = picked);
    }
  }

  Future<void> _openSlashPalette() async {
    const items = <(String, String)>[
      ('/status', 'Host/session status'),
      ('/mode default', 'Permission mode: default'),
      ('/mode plan', 'Permission mode: plan'),
      ('/mode acceptEdits', 'Permission mode: acceptEdits'),
      ('/mode bypassPermissions', 'Permission mode: bypassPermissions'),
      ('/model mock-sonnet', 'Switch model (mock-sonnet)'),
      ('/model mock-codex', 'Switch model (mock-codex)'),
      ('/model mock-hermes', 'Switch model (mock-hermes)'),
      ('/dir /workspace', 'Set workdir /workspace'),
      ('/stop', 'Request stop'),
      ('/perm', 'Permission demo'),
      ('/help', 'Host help (if supported)'),
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('Slash commands', style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: const Text('Fills input — review then send'),
            ),
            for (final it in items)
              ListTile(
                dense: true,
                leading: const Icon(Icons.terminal, size: 18),
                title: Text(it.$1, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                subtitle: Text(it.$2, style: const TextStyle(fontSize: 11)),
                onTap: () => Navigator.pop(ctx, it.$1),
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked.isNotEmpty && mounted) {
      setState(() => _input.text = picked);
    }
  }

  List<TranscriptMessage> get _visibleMessages {
    // Keep full transcript order so jump-to-hit can scroll by index.
    if (!_showTools && _chat.hasCap('tools_visible')) {
      return _chat.messages.where((m) => m.role != 'tool' && m.role != 'tool_result').toList();
    }
    return _chat.messages;
  }

  List<int> get _searchHits {
    final q = _searchQ.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final hits = <int>[];
    final msgs = _visibleMessages;
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      if (m.content.toLowerCase().contains(q) || m.role.toLowerCase().contains(q)) {
        hits.add(i);
      }
    }
    return hits;
  }

  void _gotoHit(int delta) {
    final hits = _searchHits;
    if (hits.isEmpty) return;
    setState(() {
      _hitIndex = (_hitIndex + delta) % hits.length;
      if (_hitIndex < 0) _hitIndex += hits.length;
    });
    final idx = hits[_hitIndex];
    final key = _msgKeys[idx];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        alignment: 0.2,
        curve: Curves.easeOut,
      );
    } else if (_scroll.hasClients) {
      // fallback approximate
      _scroll.animateTo(
        (idx * 96.0).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
    setState(() {
      _stickToBottom = false;
      _showJumpBottom = true;
    });
  }

  Future<void> _exportTranscript() async {
    final md = _chat.exportTranscriptMarkdown();
    await Clipboard.setData(ClipboardData(text: md));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied ${md.length} chars Markdown transcript'),
        action: SnackBarAction(
          label: 'Plain',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _chat.exportTranscriptPlain()));
          },
        ),
      ),
    );
  }

  void _previewAttachment(Map<String, dynamic> att, {required bool image}) {
    final name = (att['name'] ?? 'attachment').toString();
    final b64 = (att['data_base64'] ?? '').toString();
    String body = '';
    try {
      if (b64.isNotEmpty) {
        body = utf8.decode(base64Decode(b64), allowMalformed: true);
      }
    } catch (_) {
      body = '(binary ${b64.length} b64 chars)';
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: SingleChildScrollView(
          child: SelectableText(
            '# ${image ? 'image' : 'file'}: $name\n\nmime: ${att['mime'] ?? '?'}\n\n$body',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButton: _showJumpBottom
          ? FloatingActionButton.small(
              tooltip: 'Jump to latest',
              onPressed: _jumpToBottom,
              child: const Icon(Icons.arrow_downward),
            )
          : null,
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
            tooltip: 'Search chat',
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) {
                _searchCtrl.clear();
                _searchQ = '';
              }
            }),
            icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
          ),
          if (_chat.hasCap('tools_visible'))
            IconButton(
              tooltip: _showTools ? 'Hide tool messages' : 'Show tool messages',
              onPressed: () => setState(() => _showTools = !_showTools),
              icon: Icon(_showTools ? Icons.build_circle : Icons.build_circle_outlined),
            ),
          IconButton(
            tooltip: 'Export transcript',
            onPressed: _chat.messages.isEmpty ? null : _exportTranscript,
            icon: const Icon(Icons.ios_share_outlined),
          ),
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
                reconnectHint: _chat.reconnectHint,
                onReconnect: () => _chat.reconnectNow(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_chat.error != null || _chat.reconnectHint != null)
            Material(
              color: _chat.connected ? cs.secondaryContainer : cs.errorContainer,
              child: ListTile(
                dense: true,
                title: Text(
                  _chat.error ?? _chat.reconnectHint ?? '',
                  style: TextStyle(
                    color: _chat.connected ? cs.onSecondaryContainer : cs.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
                trailing: Wrap(
                  spacing: 0,
                  children: [
                    if (!_chat.connected)
                      TextButton(
                        onPressed: _chat.connecting ? null : () => _chat.reconnectNow(),
                        child: const Text('Reconnect'),
                      )
                    else
                      TextButton(
                        onPressed: () => _chat.connect(),
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ),
            ),
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search in transcript',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQ.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {
                                    _searchQ = '';
                                    _hitIndex = 0;
                                  });
                                },
                              ),
                      ),
                      onChanged: (v) => setState(() {
                        _searchQ = v;
                        _hitIndex = 0;
                      }),
                      onSubmitted: (_) => _gotoHit(1),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Builder(
                    builder: (context) {
                      final hits = _searchHits;
                      final label = hits.isEmpty
                          ? '0/0'
                          : '${(_hitIndex % hits.length) + 1}/${hits.length}';
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                          IconButton(
                            tooltip: 'Previous hit',
                            onPressed: hits.isEmpty ? null : () => _gotoHit(-1),
                            icon: const Icon(Icons.keyboard_arrow_up, size: 22),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            tooltip: 'Next hit',
                            onPressed: hits.isEmpty ? null : () => _gotoHit(1),
                            icon: const Icon(Icons.keyboard_arrow_down, size: 22),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          _AgentToolbar(
            mode: _chat.mode,
            model: _chat.model,
            workdir: _chat.workdir,
            runActive: _chat.runActive,
            connected: _chat.connected,
            showMode: _chat.hasCap('mode'),
            showModel: _chat.hasCap('model'),
            showDir: _chat.hasCap('workdir'),
            showStop: _chat.hasCap('cancel'),
            onMode: _pickMode,
            onModel: _pickModel,
            onDir: _pickDir,
            onStop: _chat.cancelRun,
            onStatus: () => _chat.sendSlash('/status'),
          ),
          if (_pendingImages.isNotEmpty || _pendingFiles.isNotEmpty)
            Material(
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.attach_file, size: 18),
                    title: Text(
                      '${_pendingImages.length} image(s), ${_pendingFiles.length} file(s) ready — tap to preview',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _pendingImages.clear();
                        _pendingFiles.clear();
                      }),
                    ),
                  ),
                  if (_pendingImages.isNotEmpty || _pendingFiles.isNotEmpty)
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        children: [
                          for (final img in _pendingImages)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                avatar: const Icon(Icons.image, size: 16),
                                label: Text((img['name'] ?? 'image').toString(), style: const TextStyle(fontSize: 11)),
                                onPressed: () => _previewAttachment(img, image: true),
                              ),
                            ),
                          for (final f in _pendingFiles)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                avatar: const Icon(Icons.insert_drive_file, size: 16),
                                label: Text((f['name'] ?? 'file').toString(), style: const TextStyle(fontSize: 11)),
                                onPressed: () => _previewAttachment(f, image: false),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _chat.messages.isEmpty
                ? _EmptyChat(
                    project: widget.session.project,
                    connected: _chat.connected,
                    connecting: _chat.connecting,
                  )
                : Builder(
                    builder: (context) {
                      final visible = _visibleMessages;
                      if (visible.isEmpty) {
                        return const Center(child: Text('No messages'));
                      }
                      final hits = _searchHits.toSet();
                      final activeHit = _searchHits.isEmpty
                          ? -1
                          : _searchHits[_hitIndex % _searchHits.length];
                      return ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final m = visible[i];
                          final key = _msgKeys.putIfAbsent(i, GlobalKey.new);
                          return KeyedSubtree(
                            key: key,
                            child: _MessageBubble(
                              message: m,
                              onPermission: _chat.respondPermission,
                              showTools: true, // filtering already applied in _visibleMessages
                              highlight: _searchQ.trim(),
                              isSearchHit: hits.contains(i),
                              isActiveSearchHit: i == activeHit,
                            ),
                          );
                        },
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
                  IconButton(
                    tooltip: 'Prompt history',
                    onPressed: _openPromptHistory,
                    icon: const Icon(Icons.bookmark_border),
                  ),
                  IconButton(
                    tooltip: 'Slash commands',
                    onPressed: (_chat.connected && !_chat.sending) ? _openSlashPalette : null,
                    icon: const Icon(Icons.flash_on_outlined),
                  ),
                  IconButton(
                    tooltip: 'Attach demo',
                    onPressed: (_chat.connected && !_chat.sending) ? _attachDemo : null,
                    icon: const Icon(Icons.attach_file),
                  ),
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
                  if (_chat.runActive && _chat.hasCap('cancel'))
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
    required this.showMode,
    required this.showModel,
    required this.showDir,
    required this.showStop,
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
  final bool showMode;
  final bool showModel;
  final bool showDir;
  final bool showStop;
  final VoidCallback onMode;
  final VoidCallback onModel;
  final VoidCallback onDir;
  final VoidCallback onStop;
  final VoidCallback onStatus;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (showMode) {
      chips.add(ActionChip(label: Text('mode:$mode'), onPressed: connected ? onMode : null));
    }
    if (showModel) {
      chips.add(ActionChip(label: Text('model:$model'), onPressed: connected ? onModel : null));
    }
    if (showDir) {
      chips.add(
        ActionChip(
          label: Text(workdir.length > 24 ? '…${workdir.substring(workdir.length - 22)}' : workdir),
          onPressed: connected ? onDir : null,
        ),
      );
    }
    chips.add(ActionChip(label: const Text('status'), onPressed: connected ? onStatus : null));
    if (showStop) {
      chips.add(
        ActionChip(
          avatar: Icon(Icons.stop, size: 16, color: runActive ? Colors.red : null),
          label: const Text('stop'),
          onPressed: (connected && runActive) ? onStop : null,
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              chips[i],
            ],
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
            ? project == 'hermes'
                ? 'Hermes project (Mock/ADR-002). Try a task, /help, or attach demo.'
                : 'Send a message to drive $project on your server.\nTry /help, /perm, or a normal task.'
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
    this.reconnectHint,
    this.onReconnect,
  });

  final bool connecting;
  final bool connected;
  final bool typing;
  final bool runActive;
  final String? reconnectHint;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    Color c;
    String label;
    if (connecting) {
      c = Colors.orange;
      label = '…';
    } else if (connected) {
      c = typing || runActive ? Colors.blue : Colors.green;
      label = typing ? 'typing' : (runActive ? 'run' : 'live');
    } else {
      c = Colors.red;
      label = reconnectHint != null ? 're…' : 'off';
    }
    return InkWell(
      onTap: connected ? null : onReconnect,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}


class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onPermission,
    this.showTools = true,
    this.highlight = '',
    this.isSearchHit = false,
    this.isActiveSearchHit = false,
  });

  final TranscriptMessage message;
  final Future<void> Function(String action) onPermission;
  final bool showTools;
  final String highlight;
  final bool isSearchHit;
  final bool isActiveSearchHit;

  List<Map<String, dynamic>> get _buttons {
    final raw = message.meta['buttons'];
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final role = message.role;
    final isUser = role == 'user';
    final isSystem = role == 'system';
    final isTool = role == 'tool';
    if (!showTools && isTool) {
      return const SizedBox.shrink();
    }
    final bg = isUser
        ? cs.primaryContainer
        : isSystem
            ? cs.surfaceContainerHighest
            : isTool
                ? cs.tertiaryContainer
                : cs.secondaryContainer;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final buttons = _buttons;
    final useMd = !isUser && !isTool && message.content.contains(RegExp(r'[#*`>\n-]'));
    final hl = isSearchHit ||
        (highlight.trim().isNotEmpty &&
            message.content.toLowerCase().contains(highlight.trim().toLowerCase()));
    final borderColor = isActiveSearchHit
        ? cs.primary
        : hl
            ? Colors.amber
            : null;

    return Align(
      alignment: align,
      child: GestureDetector(
        onLongPress: () async {
          final text = message.content.trim();
          if (text.isEmpty) return;
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('Message copied'), duration: Duration(seconds: 1)),
            );
          }
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: borderColor != null ? Border.all(color: borderColor, width: isActiveSearchHit ? 2 : 1.5) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                role + (message.streaming ? ' …' : ''),
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              if (useMd)
                MarkdownLite(message.content)
              else
                SelectableText(message.content),
              if (buttons.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: buttons
                      .map(
                        (b) => FilledButton.tonal(
                          onPressed: () {
                            final action = b['data']?.toString() ?? b['text']?.toString() ?? '';
                            if (action.contains('allow_all')) {
                              onPermission('allow_all');
                            } else if (action.contains('deny')) {
                              onPermission('deny');
                            } else {
                              onPermission('allow');
                            }
                          },
                          child: Text(b['text']?.toString() ?? 'action'),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
