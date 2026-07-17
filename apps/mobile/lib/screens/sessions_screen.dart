import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/session_info.dart';
import '../services/connection_controller.dart';
import '../services/session_controller.dart';
import '../services/app_settings_controller.dart';
import '../services/session_archive_store.dart';
import '../services/session_notes_store.dart';
import '../services/theme_controller.dart';
import '../services/session_pins_store.dart';
import 'chat_screen.dart';
import 'cron_screen.dart';
import 'diff_screen.dart';
import 'activity_screen.dart';
import 'agents_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';
import 'host_dashboard_screen.dart';
import 'mcp_screen.dart';
import 'memory_screen.dart';
import 'pairing_screen.dart';
import 'skills_screen.dart';
import 'terminal_screen.dart';
import 'workspace_screen.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  SessionController? _sessions;
  final _titleCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _pins = SessionPinsStore();
  final _notes = SessionNotesStore();
  final _archive = SessionArchiveStore();
  String _query = '';
  Set<String> _pinned = {};
  Set<String> _archived = {};
  Map<String, String> _noteMap = {};
  /// all | pinned | running | archived
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  Future<void> _loadPins() async {
    final pins = await _pins.pins();
    final notes = await _notes.all();
    final archived = await _archive.archived();
    if (!mounted) return;
    setState(() {
      _pinned = pins;
      _noteMap = notes;
      _archived = archived;
    });
  }

  Future<void> _toggleArchive(SessionInfo s) async {
    await _archive.toggle(s.sessionKey);
    await _loadPins();
  }

  Future<void> _renameSession(SessionController sessions, SessionInfo s) async {
    final ctrl = TextEditingController(text: s.displayTitle);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename session'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && mounted) {
      final t = ctrl.text.trim();
      if (t.isEmpty) return;
      final r = await sessions.renameSession(s, t);
      if (r == null && mounted && sessions.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sessions.error!)));
      }
    }
  }

  Future<void> _editNote(SessionInfo s) async {
    final ctrl = TextEditingController(text: _noteMap[s.sessionKey] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session note (device only)'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Local note — not uploaded to Host',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await _notes.set(s.sessionKey, '');
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Clear'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      await _notes.set(s.sessionKey, ctrl.text);
      await _loadPins();
    }
  }

  Future<void> _togglePin(SessionInfo s) async {
    await _pins.toggle(s.sessionKey);
    await _loadPins();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final conn = context.watch<ConnectionController>();
    final cfg = conn.saved;
    if (cfg == null) return;
    if (_sessions == null) {
      _sessions = SessionController(config: cfg)..refresh();
    } else {
      _sessions!.updateConfig(cfg);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    _sessions?.dispose();
    super.dispose();
  }

  List<SessionInfo> _filtered(List<SessionInfo> all) {
    final q = _query.trim().toLowerCase();
    Iterable<SessionInfo> base = all;
    if (_filter == 'archived') {
      base = base.where((s) => _archived.contains(s.sessionKey));
    } else {
      // default views hide archived
      base = base.where((s) => !_archived.contains(s.sessionKey));
      if (_filter == 'pinned') {
        base = base.where((s) => _pinned.contains(s.sessionKey));
      } else if (_filter == 'running') {
        base = base.where((s) => s.running || s.live);
      }
    }
    if (q.isNotEmpty) {
      base = base.where((s) {
        final note = _noteMap[s.sessionKey] ?? '';
        final hay =
            '${s.displayTitle} ${s.project} ${s.sessionKey} ${s.model ?? ''} $note'.toLowerCase();
        return hay.contains(q);
      });
    }
    final list = base.toList();
    list.sort((a, b) {
      final ap = _pinned.contains(a.sessionKey) ? 0 : 1;
      final bp = _pinned.contains(b.sessionKey) ? 0 : 1;
      if (ap != bp) return ap.compareTo(bp);
      return (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0);
    });
    return list;
  }

  Future<void> _openTerminal(SessionInfo session) async {
    final conn = context.read<ConnectionController>();
    final cfg = conn.saved;
    if (cfg == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalScreen(config: cfg, session: session),
      ),
    );
  }

  Future<void> _create() async {
    final s = _sessions;
    if (s == null) return;
    final created = await s.createSession(
      title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
    );
    _titleCtrl.clear();
    if (!mounted) return;
    if (created != null) {
      await _openChat(created);
    } else if (s.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.error!)));
    }
  }

  Future<void> _openChat(SessionInfo session) async {
    final conn = context.read<ConnectionController>();
    final cfg = conn.saved;
    if (cfg == null) return;
    final caps = _sessions?.projects
            .where((p) => p.name == session.project)
            .map((p) => p.capabilities)
            .firstWhere((_) => true, orElse: () => const <String>[]) ??
        const <String>[];
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          config: cfg,
          session: session,
          projectCapabilities: caps,
        ),
      ),
    );
    await _sessions?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionController>();
    final sessions = _sessions;
    if (sessions == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AnimatedBuilder(
      animation: sessions,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Sessions'),
            actions: [
            Builder(
              builder: (context) {
                final theme = context.watch<ThemeController>();
                return IconButton(
                  tooltip: 'Theme: ${theme.label}',
                  icon: Icon(theme.icon),
                  onPressed: () => theme.cycle(),
                );
              },
            ),

              IconButton(
                tooltip: 'Host status',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HostDashboardScreen()),
                  );
                },
                icon: const Icon(Icons.monitor_heart_outlined),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: sessions.loading ? null : sessions.refresh,
                icon: const Icon(Icons.refresh),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) {
                  final cfg = conn.saved;
                  if (cfg == null) return;
                  Widget page;
                  switch (v) {
                    case 'status':
                      page = const HostDashboardScreen();
                      break;
                    case 'agents':
                      page = AgentsScreen(config: cfg);
                      break;
                    case 'logs':
                      page = LogsScreen(config: cfg);
                      break;
                    case 'settings':
                      page = const SettingsScreen();
                      break;
                    case 'workspace':
                      page = WorkspaceScreen(config: cfg);
                      break;
                    case 'diff':
                      page = DiffScreen(config: cfg);
                      break;
                    case 'memory':
                      page = MemoryScreen(config: cfg);
                      break;
                    case 'activity':
                      page = ActivityScreen(config: cfg);
                      break;
                    case 'cron':
                      page = CronScreen(config: cfg);
                      break;
                    case 'skills':
                      page = SkillsScreen(config: cfg);
                      break;
                    case 'mcp':
                      page = McpScreen(config: cfg);
                      break;
                    case 'pairing':
                      page = PairingScreen(config: cfg);
                      break;
                    default:
                      return;
                  }
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(value: 'status', child: Text('Host status')),
                  PopupMenuItem(value: 'agents', child: Text('Agents')),
                  PopupMenuItem(value: 'logs', child: Text('Host logs')),
                  PopupMenuItem(value: 'settings', child: Text('Settings')),
                  PopupMenuItem(value: 'workspace', child: Text('Workspace')),
                  PopupMenuItem(value: 'diff', child: Text('Git diff')),
                  PopupMenuItem(value: 'memory', child: Text('Host memory')),
                  PopupMenuItem(value: 'activity', child: Text('Host activity')),
                  PopupMenuItem(value: 'cron', child: Text('Schedules')),
                  PopupMenuItem(value: 'skills', child: Text('Skills')),
                  PopupMenuItem(value: 'mcp', child: Text('MCP')),
                  PopupMenuItem(value: 'pairing', child: Text('Pairing')),
                ],
              ),
              IconButton(
                tooltip: 'Edit connection',
                onPressed: () => conn.disconnect(),
                icon: const Icon(Icons.settings_ethernet),
              ),
              IconButton(
                tooltip: 'Clear profile',
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear saved profile?'),
                      content: const Text('Removes host settings and tokens.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                      ],
                    ),
                  );
                  if (ok == true) await conn.disconnect(clearStorage: true);
                },
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: Column(
            children: [
              if (conn.saved != null)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.dns_outlined, size: 20),
                  title: Text(conn.saved!.host),
                  subtitle: Text(conn.saved!.mgmtBaseUrl),
                ),
              if (sessions.projects.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: DropdownButtonFormField<String>(
                    value: sessions.projects.any((p) => p.name == sessions.selectedProject)
                        ? sessions.selectedProject
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Project',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: sessions.projects
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.name,
                            child: Text('${p.name} (${p.agentType})'),
                          ),
                        )
                        .toList(),
                    onChanged: sessions.selectProject,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search sessions / notes',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final f in const [
                      ('all', 'All'),
                      ('pinned', 'Pinned'),
                      ('running', 'Running'),
                      ('archived', 'Archived'),
                    ])
                      FilterChip(
                        label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                        selected: _filter == f.$1,
                        onSelected: (_) => setState(() => _filter = f.$1),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(
                          hintText: 'New session title (optional)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _create(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: sessions.loading ? null : _create,
                      icon: const Icon(Icons.add),
                      label: const Text('New'),
                    ),
                  ],
                ),
              ),
              if (sessions.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(sessions.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final visible = _filtered(sessions.sessions);
                    return sessions.loading && sessions.sessions.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            onRefresh: sessions.refresh,
                            child: sessions.sessions.isEmpty
                                ? ListView(
                                    children: [
                                      const SizedBox(height: 48),
                                      Icon(
                                        Icons.forum_outlined,
                                        size: 40,
                                        color: Theme.of(context).colorScheme.outline,
                                      ),
                                      const SizedBox(height: 12),
                                      const Center(child: Text('No sessions yet')),
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 24),
                                        child: Text(
                                          'Create a session for Claude Code / Codex / Hermes and open chat to control the server agent.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : visible.isEmpty
                                    ? ListView(
                                        children: const [
                                          SizedBox(height: 48),
                                          Center(child: Text('No sessions match search')),
                                        ],
                                      )
                                    : ListView.separated(
                                        itemCount: visible.length,
                                        separatorBuilder: (_, __) => const Divider(height: 1),
                                        itemBuilder: (context, i) {
                                          final s = visible[i];
                                          final pinned = _pinned.contains(s.sessionKey);
                                          final note = _noteMap[s.sessionKey];
                                          final compact = context.watch<AppSettingsController>().compactMode;
                                          return ListTile(
                                            visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
                                            title: Text(s.displayTitle),
                                            subtitle: Text(
                                              [
                                                '${s.project} · ${s.model ?? "model?"}',
                                                s.sessionKey,
                                                if (note != null && note.isNotEmpty) '📝 $note',
                                              ].join('\n'),
                                            ),
                                            isThreeLine: true,
                                            leading: Icon(
                                              pinned
                                                  ? Icons.push_pin
                                                  : s.running
                                                      ? Icons.play_circle_fill
                                                      : Icons.chat_bubble_outline,
                                              color: pinned
                                                  ? Colors.amber
                                                  : s.running
                                                      ? Colors.blue
                                                      : null,
                                            ),
                                            onTap: () => _openChat(s),
                                            onLongPress: () => _editNote(s),
                                            trailing: Wrap(
                                              spacing: 0,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Rename',
                                                  icon: const Icon(Icons.drive_file_rename_outline, size: 20),
                                                  onPressed: () => _renameSession(sessions, s),
                                                ),
                                                IconButton(
                                                  tooltip: _archived.contains(s.sessionKey) ? 'Unarchive' : 'Archive',
                                                  icon: Icon(
                                                    _archived.contains(s.sessionKey)
                                                        ? Icons.unarchive_outlined
                                                        : Icons.archive_outlined,
                                                    size: 20,
                                                  ),
                                                  onPressed: () => _toggleArchive(s),
                                                ),
                                                IconButton(
                                                  tooltip: 'Note',
                                                  icon: Icon(
                                                    (note != null && note.isNotEmpty)
                                                        ? Icons.sticky_note_2
                                                        : Icons.sticky_note_2_outlined,
                                                    size: 20,
                                                  ),
                                                  onPressed: () => _editNote(s),
                                                ),
                                                IconButton(
                                                  tooltip: pinned ? 'Unpin' : 'Pin',
                                                  icon: Icon(
                                                    pinned ? Icons.push_pin : Icons.push_pin_outlined,
                                                    size: 20,
                                                  ),
                                                  onPressed: () => _togglePin(s),
                                                ),
                                                IconButton(
                                                  tooltip: 'Terminal',
                                                  icon: const Icon(Icons.terminal),
                                                  onPressed: () => _openTerminal(s),
                                                ),
                                                IconButton(
                                                  tooltip: 'Delete',
                                                  icon: const Icon(Icons.delete_outline),
                                                  onPressed: () => sessions.deleteSession(s),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                          );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
