import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/session_info.dart';
import '../services/connection_controller.dart';
import '../services/session_controller.dart';
import '../services/app_settings_controller.dart';
import '../services/session_archive_store.dart';
import '../services/session_notes_store.dart';
import '../services/theme_controller.dart';
import '../services/session_pins_store.dart';
import '../services/session_recents_store.dart';
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
  final _scroll = ScrollController();
  Timer? _timer;
  bool _wrapLines = false;
  bool _sortAsc = true;
  bool _autoRefresh = false;
  final _pins = SessionPinsStore();
  final _notes = SessionNotesStore();
  final _archive = SessionArchiveStore();
  final _recents = SessionRecentsStore();
  String _query = '';
  bool _queryCase = false;
  bool _queryRegex = false;
  Set<String> _pinned = {};
  Set<String> _archived = {};
  Map<String, String> _noteMap = {};
  Map<String, int> _recentRank = {};
  /// all | pinned | running | archived
  String _filter = 'all';
  bool _groupByProject = false;
  bool _selectMode = false;
  final Set<String> _selected = {};
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadPins();
    WidgetsBinding.instance.addPostFrameCallback((_) => _armTimer());
  }

  void _armTimer() {
    _timer?.cancel();
    if (!_autoRefresh || !mounted) return;
    final sec = context.read<AppSettingsController>().dashboardRefreshSec;
    if (sec <= 0) return;
    _timer = Timer.periodic(Duration(seconds: sec), (_) {
      if (!mounted) return;
      final sessions = _sessions;
      if (sessions == null || sessions.loading) return;
      sessions.refresh();
    });
  }

  Future<void> _loadPins() async {
    final pins = await _pins.pins();
    final notes = await _notes.all();
    final archived = await _archive.archived();
    final ranks = await _recents.ranks();
    if (!mounted) return;
    setState(() {
      _pinned = pins;
      _noteMap = notes;
      _archived = archived;
      _recentRank = ranks;
    });
  }

  Future<void> _toggleArchive(SessionInfo s) async {
    await _archive.toggle(s.sessionKey);
    await _loadPins();
  }

  void _enterSelectMode([SessionInfo? first]) {
    setState(() {
      _selectMode = true;
      _selected.clear();
      if (first != null) _selected.add(first.sessionKey);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _toggleSelected(SessionInfo s) {
    setState(() {
      if (_selected.contains(s.sessionKey)) {
        _selected.remove(s.sessionKey);
        if (_selected.isEmpty) _selectMode = false;
      } else {
        _selected.add(s.sessionKey);
      }
    });
  }


  Future<void> _exportSessionMeta(SessionInfo s) async {
    final note = _noteMap[s.sessionKey] ?? '';
    final lines = <String>[
      '# HuanHermes session export',
      'id: ${s.id}',
      'session_key: ${s.sessionKey}',
      'title: ${s.displayTitle}',
      'project: ${s.project}',
      if (s.mode != null) 'mode: ${s.mode}',
      if (s.model != null) 'model: ${s.model}',
      if (s.workdir != null) 'workdir: ${s.workdir}',
      if (s.platform != null) 'platform: ${s.platform}',
      if (s.agentType != null) 'agent_type: ${s.agentType}',
      'running: ${s.running}',
      'live: ${s.live}',
      if (s.updatedAt != null) 'updated_at: ${s.updatedAt}',
      if (s.createdAt != null) 'created_at: ${s.createdAt}',
      'pinned_local: ${_pinned.contains(s.sessionKey)}',
      'archived_local: ${_archived.contains(s.sessionKey)}',
      if (note.isNotEmpty) 'note_local: $note',
      '',
      'Export is metadata only (device console). Transcript export lives in Chat.',
    ];
    final text = lines.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session metadata copied')),
    );
  }


  Future<void> _copyVisibleCsv(List<SessionInfo> list) async {
    if (list.isEmpty) return;
    final buf = StringBuffer();
    buf.writeln('title,project,session_key,pinned,archived,note');
    for (final s in list) {
      final title = s.displayTitle.replaceAll('"', '""');
      final project = s.project.replaceAll('"', '""');
      final key = s.sessionKey.replaceAll('"', '""');
      final pinned = _pinned.contains(s.sessionKey) ? '1' : '0';
      final archived = _archived.contains(s.sessionKey) ? '1' : '0';
      final note = (_noteMap[s.sessionKey] ?? '').replaceAll('"', '""');
      buf.writeln('"$title","$project","$key",$pinned,$archived,"$note"');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied CSV (${list.length})'), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _exportVisibleMeta(List<SessionInfo> list) async {
    if (list.isEmpty) return;
    final buf = StringBuffer('# HuanHermes sessions export (${list.length})\n');
    for (final s in list) {
      final note = _noteMap[s.sessionKey] ?? '';
      buf.writeln('- ${s.displayTitle} | ${s.project} | ${s.sessionKey}'
          '${note.isEmpty ? '' : ' | note: $note'}');
    }
    buf.writeln();
    buf.writeln('Local pins/archives/notes only; tokens never included.');
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${list.length} session row(s)')),
    );
  }

  List<SessionInfo> _selectedSessions(List<SessionInfo> all) {
    return all.where((s) => _selected.contains(s.sessionKey)).toList();
  }

  Future<void> _bulkArchive({required bool archive}) async {
    for (final k in _selected.toList()) {
      await _archive.setArchived(k, archive);
    }
    await _loadPins();
    _exitSelectMode();
  }

  Future<void> _bulkPin({required bool pin}) async {
    for (final k in _selected.toList()) {
      await _pins.setPinned(k, pin);
    }
    await _loadPins();
    _exitSelectMode();
  }

  Future<void> _bulkDelete(SessionController sessions, List<SessionInfo> all) async {
    final targets = _selectedSessions(all);
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${targets.length} session(s)?'),
        content: const Text(
          'Removes sessions on the Host. Local notes/pins for those keys stay until cleared.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    for (final s in targets) {
      await sessions.deleteSession(s);
    }
    _exitSelectMode();
  }

  Future<void> _shareConnection(ConnectionController conn) async {
    final cfg = conn.saved;
    if (cfg == null) return;
    await Clipboard.setData(ClipboardData(text: cfg.toPublicSummary()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Public connection summary copied (no tokens)'),
        duration: Duration(seconds: 2),
      ),
    );
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
    context.read<AppSettingsController>().buzzLight();
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
    _scroll.dispose();
    _searchDebounce?.cancel();
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    _sessions?.dispose();
    super.dispose();
  }

  List<SessionInfo> _filtered(List<SessionInfo> all) {
    final rawQ = _query.trim();
    final q = _queryCase ? rawQ : rawQ.toLowerCase();
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
      } else if (_filter == 'notes') {
        base = base.where((s) => (_noteMap[s.sessionKey] ?? '').trim().isNotEmpty);
      }
    }
    if (rawQ.isNotEmpty) {
      base = base.where((s) {
        final note = _noteMap[s.sessionKey] ?? '';
        final hayRaw =
            '${s.displayTitle} ${s.project} ${s.sessionKey} ${s.model ?? ''} $note';
        if (_queryRegex) {
          try {
            return RegExp(rawQ, caseSensitive: _queryCase).hasMatch(hayRaw);
          } catch (_) {
            return false;
          }
        }
        final hay = _queryCase ? hayRaw : hayRaw.toLowerCase();
        return hay.contains(q);
      });
    }
    final list = base.toList();
    final sortMode = context.mounted
        ? (context.read<AppSettingsController>().sessionSort)
        : 'updated';
    list.sort((a, b) {
      final ap = _pinned.contains(a.sessionKey) ? 0 : 1;
      final bp = _pinned.contains(b.sessionKey) ? 0 : 1;
      if (ap != bp) return ap.compareTo(bp);
      int dir(int c) => _sortAsc ? c : -c;
      switch (sortMode) {
        case 'title':
          return dir(a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        case 'project':
          final pc = a.project.toLowerCase().compareTo(b.project.toLowerCase());
          if (pc != 0) return dir(pc);
          return dir(a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        case 'created':
          return dir((b.createdAt ?? b.updatedAt ?? 0).compareTo(a.createdAt ?? a.updatedAt ?? 0));
        case 'model':
          final mc = (a.model ?? '').toLowerCase().compareTo((b.model ?? '').toLowerCase());
          if (mc != 0) return dir(mc);
          return dir(a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        case 'key':
          final kc = a.sessionKey.toLowerCase().compareTo(b.sessionKey.toLowerCase());
          if (kc != 0) return dir(kc);
          return dir(a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        case 'platform':
          final pc = (a.platform ?? '').toLowerCase().compareTo((b.platform ?? '').toLowerCase());
          if (pc != 0) return dir(pc);
          return dir(a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        case 'agent':
          final ac = (a.agentType ?? '').toLowerCase().compareTo((b.agentType ?? '').toLowerCase());
          if (ac != 0) return dir(ac);
          return dir(a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        case 'mode':
          final mc = (a.mode ?? '').toLowerCase().compareTo((b.mode ?? '').toLowerCase());
          if (mc != 0) return dir(mc);
          return dir(a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        case 'workdir':
          final wc = (a.workdir ?? '').toLowerCase().compareTo((b.workdir ?? '').toLowerCase());
          if (wc != 0) return dir(wc);
          return dir(a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        case 'running':
          final rc = (a.running ? 1 : 0).compareTo(b.running ? 1 : 0);
          if (rc != 0) return dir(-rc); // running first in default dir
          return dir(a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        case 'live':
          final lc = (a.live ? 1 : 0).compareTo(b.live ? 1 : 0);
          if (lc != 0) return dir(-lc); // live first
          return dir(a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        case 'recent':
          final ar = _recentRank[a.sessionKey];
          final br = _recentRank[b.sessionKey];
          if (ar == null && br == null) {
            return dir((b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));
          }
          if (ar == null) return dir(1);
          if (br == null) return dir(-1);
          return dir(ar.compareTo(br));
        case 'updated':
        default:
          return dir((b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));
      }
    });
    return list;
  }

  /// When grouping: returns alternating header String / SessionInfo.
  List<Object> _visibleRows(List<SessionInfo> visible) {
    if (!_groupByProject) return List<Object>.from(visible);
    final map = <String, List<SessionInfo>>{};
    for (final s in visible) {
      final p = s.project.isEmpty ? '(no project)' : s.project;
      map.putIfAbsent(p, () => []).add(s);
    }
    final keys = map.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final out = <Object>[];
    for (final k in keys) {
      out.add(k);
      out.addAll(map[k]!);
    }
    return out;
  }

  Future<void> _openTerminal(SessionInfo session) async {
    final conn = context.read<ConnectionController>();
    final cfg = conn.saved;
    if (cfg == null) return;
    await _recents.touch(session.sessionKey);
    await _loadPins();
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
    await _recents.touch(session.sessionKey);
    await _loadPins();
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
            leading: _selectMode
                ? IconButton(
                    tooltip: 'Cancel selection',
                    icon: const Icon(Icons.close),
                    onPressed: _exitSelectMode,
                  )
                : null,
            title: Text(_selectMode ? '${_selected.length} selected' : 'Sessions'),
            actions: [
              if (_selectMode) ...[
                IconButton(
                  tooltip: 'Export selected meta',
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _exportVisibleMeta(_selectedSessions(sessions.sessions)),
                  icon: const Icon(Icons.copy_all_outlined),
                ),
                IconButton(
                  tooltip: 'Pin selected',
                  onPressed: _selected.isEmpty ? null : () => _bulkPin(pin: true),
                  icon: const Icon(Icons.push_pin),
                ),
                IconButton(
                  tooltip: 'Archive selected',
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _bulkArchive(archive: _filter != 'archived'),
                  icon: Icon(
                    _filter == 'archived' ? Icons.unarchive_outlined : Icons.archive_outlined,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete selected',
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _bulkDelete(sessions, sessions.sessions),
                  icon: const Icon(Icons.delete_outline),
                ),
              ] else ...[
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
                tooltip: 'Share connection (no tokens)',
                onPressed: () => _shareConnection(conn),
                icon: const Icon(Icons.ios_share_outlined),
              ),
              IconButton(
                tooltip: 'Select sessions',
                onPressed: () => _enterSelectMode(),
                icon: const Icon(Icons.checklist),
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
              IconButton(
                tooltip: 'Jump to top',
                onPressed: () {
                  if (!_scroll.hasClients) return;
                  _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                },
                icon: const Icon(Icons.vertical_align_top),
              ),
              IconButton(
                tooltip: 'Jump to end',
                onPressed: () {
                  if (!_scroll.hasClients) return;
                  _scroll.animateTo(
                    _scroll.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                },
                icon: const Icon(Icons.vertical_align_bottom),
              ),
              IconButton(
                tooltip: _autoRefresh ? 'Pause auto-refresh' : 'Auto-refresh',
                onPressed: () {
                  setState(() => _autoRefresh = !_autoRefresh);
                  _armTimer();
                },
                icon: Icon(_autoRefresh ? Icons.pause_circle_outline : Icons.play_circle_outline),
              ),
              IconButton(
                tooltip: 'Copy CSV',
                onPressed: () {
                  final list = _filtered(sessions.sessions);
                  if (list.isEmpty) return;
                  _copyVisibleCsv(list);
                },
                icon: const Icon(Icons.table_chart_outlined),
              ),
          IconButton(
            tooltip: _wrapLines ? 'Clamp details' : 'Wrap details',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
          ),
          IconButton(
            tooltip: _sortAsc ? 'Sort direction Z→A / oldest' : 'Sort direction A→Z / newest',
            onPressed: () => setState(() => _sortAsc = !_sortAsc),
            icon: Icon(_sortAsc ? Icons.south : Icons.north),
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
                    case 'export_list':
                      _exportVisibleMeta(_filtered(sessions.sessions));
                      return;
                    case 'csv_list':
                      _copyVisibleCsv(_filtered(sessions.sessions));
                      return;
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
                      page = ActivityScreen(config: cfg, sessions: sessions.sessions);
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
                  PopupMenuItem(value: 'export_list', child: Text('Export visible list')),
                      PopupMenuItem(value: 'csv_list', child: Text('Copy visible CSV')),
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
              ], // end non-select actions
            ],
          ),
          body: Column(
            children: [
              if (conn.saved != null)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.dns_outlined, size: 20),
                  title: Text(
                    conn.profiles
                            .where((p) => p.id == conn.activeProfileId)
                            .map((p) => p.name)
                            .cast<String?>()
                            .firstWhere((_) => true, orElse: () => null) ??
                        conn.draftProfileName,
                  ),
                  subtitle: Text('${conn.saved!.host} · ${conn.saved!.mgmtBaseUrl}'),
                  trailing: conn.profiles.length > 1
                      ? PopupMenuButton<String>(
                          tooltip: 'Switch host profile',
                          icon: const Icon(Icons.swap_horiz, size: 20),
                          onSelected: (id) async {
                            if (id == conn.activeProfileId) return;
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Switch host profile?'),
                                content: const Text(
                                  'Disconnects the current Host and tests the selected profile. '
                                  'Sessions list will reload for the new Host.',
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Switch')),
                                ],
                              ),
                            );
                            if (ok != true || !context.mounted) return;
                            final success = await conn.switchAndConnect(id);
                            if (!context.mounted) return;
                            if (success) {
                              _sessions?.dispose();
                              _sessions = SessionController(config: conn.saved!)..refresh();
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Switched host profile')),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(conn.lastError ?? 'Switch failed'),
                                  backgroundColor: Colors.red.shade700,
                                ),
                              );
                            }
                          },
                          itemBuilder: (ctx) => [
                            for (final p in conn.profiles)
                              PopupMenuItem(
                                value: p.id,
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    p.id == conn.activeProfileId
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 18,
                                  ),
                                  title: Text(p.name),
                                  subtitle: Text(
                                    '${p.config.host}:${p.config.mgmtPort}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : null,
                ),
              if (conn.saved != null)
                Material(
                  color: conn.healthDegraded
                      ? Theme.of(context).colorScheme.errorContainer.withOpacity(0.55)
                      : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.45),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      conn.healthDegraded ? Icons.cloud_off : Icons.cloud_done_outlined,
                      size: 18,
                      color: conn.healthDegraded
                          ? Theme.of(context).colorScheme.error
                          : Colors.green.shade700,
                    ),
                    title: Text(
                      conn.healthDegraded
                          ? 'Host health degraded'
                          : 'Host health OK',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      [
                        if (conn.lastHealthOkAt != null)
                          'Last OK: ${conn.lastHealthOkAt!.toLocal().toIso8601String().substring(11, 19)}',
                        if (conn.lastHealthError != null)
                          'Error: ${conn.lastHealthError}',
                        if (conn.lastStatus != null && conn.lastStatus!['version'] != null)
                          'version: ${conn.lastStatus!['version']}',
                        'Probe every 30s while connected',
                      ].where((e) => e.toString().isNotEmpty).join(' · '),
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: TextButton(
                      onPressed: conn.healthChecking ? null : () => conn.probeHealth(),
                      child: Text(conn.healthChecking ? '…' : 'Check'),
                    ),
                  ),
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
                    hintText: _queryRegex
                        ? (_queryCase ? 'Search (regex · case)' : 'Search (regex)')
                        : (_queryCase ? 'Search (case-sensitive)' : 'Search sessions / notes'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: IconButton(
                      tooltip: _queryRegex
                          ? (_queryCase
                              ? 'Regex · case on (long-press: plain search)'
                              : 'Regex · case off (long-press: plain search)')
                          : (_queryCase
                              ? 'Case-sensitive (long-press: regex)'
                              : 'Case-insensitive (long-press: regex)'),
                      icon: Icon(
                        _queryRegex
                            ? Icons.code
                            : (_queryCase ? Icons.text_fields : Icons.search),
                        size: 20,
                      ),
                      onPressed: () => setState(() => _queryCase = !_queryCase),
                      onLongPress: () => setState(() => _queryRegex = !_queryRegex),
                    ),
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
                  onChanged: (v) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
                      if (!mounted) return;
                      setState(() => _query = v);
                    });
                  },
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
                      ('notes', 'Notes'),
                      ('archived', 'Archived'),
                    ])
                      FilterChip(
                        label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                        selected: _filter == f.$1,
                        onSelected: (_) => setState(() => _filter = f.$1),
                        visualDensity: VisualDensity.compact,
                      ),
                    FilterChip(
                      label: const Text('Group', style: TextStyle(fontSize: 12)),
                      selected: _groupByProject,
                      avatar: Icon(
                        _groupByProject ? Icons.folder : Icons.folder_outlined,
                        size: 16,
                      ),
                      onSelected: (v) => setState(() => _groupByProject = v),
                      visualDensity: VisualDensity.compact,
                    ),
                    Builder(
                      builder: (context) {
                        final settings = context.watch<AppSettingsController>();
                        return PopupMenuButton<String>(
                          tooltip: 'Sort',
                          initialValue: settings.sessionSort,
                          onSelected: (v) async {
                            await settings.setSessionSort(v);
                            setState(() {});
                          },
                          itemBuilder: (ctx) => const [
                            PopupMenuItem(value: 'updated', child: Text('Sort: Updated')),
                            PopupMenuItem(value: 'recent', child: Text('Sort: Recent')),
                            PopupMenuItem(value: 'title', child: Text('Sort: Title')),
                            PopupMenuItem(value: 'project', child: Text('Sort: Project')),
                            PopupMenuItem(value: 'created', child: Text('Sort: Created')),
                            PopupMenuItem(value: 'model', child: Text('Sort: Model')),
                            PopupMenuItem(value: 'key', child: Text('Sort: Key')),
                            PopupMenuItem(value: 'platform', child: Text('Sort: Platform')),
                            PopupMenuItem(value: 'agent', child: Text('Sort: Agent')),
                            PopupMenuItem(value: 'mode', child: Text('Sort: Mode')),
                            PopupMenuItem(value: 'workdir', child: Text('Sort: Workdir')),
                            PopupMenuItem(value: 'running', child: Text('Sort: Running')),
                            PopupMenuItem(value: 'live', child: Text('Sort: Live')),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Chip(
                              avatar: const Icon(Icons.sort, size: 16),
                              label: Text(
                                {
                                  'title': 'Title',
                                  'project': 'Project',
                                  'created': 'Created',
                                  'model': 'Model',
                                  'key': 'Key',
                                  'recent': 'Recent',
                                  'platform': 'Platform',
                                  'agent': 'Agent',
                                  'mode': 'Mode',
                                  'workdir': 'Workdir',
                                  'running': 'Running',
                                  'live': 'Live',
                                }[settings.sessionSort] ??
                                    'Updated',
                                style: const TextStyle(fontSize: 12),
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        );
                      },
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
                                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                                    children: [
                                      Icon(
                                        Icons.forum_outlined,
                                        size: 48,
                                        color: Theme.of(context).colorScheme.outline,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No sessions yet',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'This App is a remote console only — agents run on the Host.\n'
                                        '1) Confirm Host health above is OK\n'
                                        '2) Pick a project if listed\n'
                                        '3) Tap New to create a session\n'
                                        '4) Open chat to control Claude Code / Codex / Hermes',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Center(
                                        child: FilledButton.icon(
                                          onPressed: sessions.loading ? null : _create,
                                          icon: const Icon(Icons.add),
                                          label: const Text('Create first session'),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Center(
                                        child: TextButton.icon(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(builder: (_) => const HostDashboardScreen()),
                                            );
                                          },
                                          icon: const Icon(Icons.monitor_heart_outlined),
                                          label: const Text('Open Host dashboard'),
                                        ),
                                      ),
                                    ],
                                  )
                                : visible.isEmpty
                                    ? ListView(
                                        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                                        children: [
                                          Icon(
                                            Icons.filter_alt_off_outlined,
                                            size: 40,
                                            color: Theme.of(context).colorScheme.outline,
                                          ),
                                          const SizedBox(height: 12),
                                          const Center(child: Text('No sessions match filters')),
                                          const SizedBox(height: 8),
                                          Text(
                                            _filter == 'archived'
                                                ? 'Nothing archived on this device, or search hides them.'
                                                : 'Try All filter, clear search, or create a new session.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Center(
                                            child: TextButton(
                                              onPressed: () => setState(() {
                                                _filter = 'all';
                                                _query = '';
                                                _searchCtrl.clear();
                                              }),
                                              child: const Text('Reset filters'),
                                            ),
                                          ),
                                        ],
                                      )
                                    : ListView.separated(
                                        controller: _scroll,
                                        itemCount: _visibleRows(visible).length,
                                        separatorBuilder: (_, __) => const Divider(height: 1),
                                        itemBuilder: (context, i) {
                                          final row = _visibleRows(visible)[i];
                                          if (row is String) {
                                            return Material(
                                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.55),
                                              child: ListTile(
                                                dense: true,
                                                visualDensity: VisualDensity.compact,
                                                leading: const Icon(Icons.folder_outlined, size: 18),
                                                title: Text(
                                                  row,
                                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                                ),
                                                subtitle: Text(
                                                  '${visible.where((s) => (s.project.isEmpty ? '(no project)' : s.project) == row).length} sessions',
                                                  style: const TextStyle(fontSize: 11),
                                                ),
                                              ),
                                            );
                                          }
                                          final s = row as SessionInfo;
                                          final pinned = _pinned.contains(s.sessionKey);
                                          final note = _noteMap[s.sessionKey];
                                          final compact = context.watch<AppSettingsController>().compactMode;
                                          final selected = _selected.contains(s.sessionKey);
                                          final projCaps = sessions.projects
                                              .where((p) => p.name == s.project)
                                              .map((p) => p.capabilities)
                                              .firstWhere((_) => true, orElse: () => const <String>[]);
                                          final tile = ListTile(
                                            selected: selected,
                                            visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
                                            title: Text(
                                              s.displayTitle,
                                              maxLines: _wrapLines ? 4 : 1,
                                              overflow: TextOverflow.ellipsis,
                                              softWrap: true,
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  [
                                                    '${s.project} · ${s.model ?? "model?"}',
                                                    s.sessionKey,
                                                    if (note != null && note.isNotEmpty) '📝 $note',
                                                  ].join('\n'),
                                                  maxLines: _wrapLines ? 8 : 3,
                                                  overflow: TextOverflow.ellipsis,
                                                  softWrap: true,
                                                ),
                                                if (projCaps.isNotEmpty && !_selectMode) ...[
                                                  const SizedBox(height: 4),
                                                  Wrap(
                                                    spacing: 4,
                                                    runSpacing: 2,
                                                    children: [
                                                      for (final c in projCaps.take(4))
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            borderRadius: BorderRadius.circular(8),
                                                            color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.7),
                                                          ),
                                                          child: Text(
                                                            c.toString(),
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color: Theme.of(context).colorScheme.onSecondaryContainer,
                                                            ),
                                                          ),
                                                        ),
                                                      if (projCaps.length > 4)
                                                        Text(
                                                          '+${projCaps.length - 4}',
                                                          style: const TextStyle(fontSize: 10),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                            isThreeLine: true,
                                            leading: _selectMode
                                                ? Checkbox(
                                                    value: selected,
                                                    onChanged: (_) => _toggleSelected(s),
                                                  )
                                                : Icon(
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
                                            onTap: () {
                                              if (_selectMode) {
                                                _toggleSelected(s);
                                              } else {
                                                _openChat(s);
                                              }
                                            },
                                            onLongPress: () {
                                              if (_selectMode) {
                                                _toggleSelected(s);
                                              } else {
                                                _enterSelectMode(s);
                                              }
                                            },
                                            trailing: _selectMode
                                                ? null
                                                : PopupMenuButton<String>(
                                                    tooltip: 'Session actions',
                                                    onSelected: (v) async {
                                                      switch (v) {
                                                        case 'export':
                                                          _exportSessionMeta(s);
                                                        case 'rename':
                                                          await _renameSession(sessions, s);
                                                        case 'archive':
                                                          await _toggleArchive(s);
                                                        case 'note':
                                                          await _editNote(s);
                                                        case 'pin':
                                                          await _togglePin(s);
                                                        case 'copy_key':
                                                          final text = [
                                                            s.displayTitle,
                                                            'id: ${s.id}',
                                                            'session_key: ${s.sessionKey}',
                                                            'project: ${s.project}',
                                                          ].join('\n');
                                                          await Clipboard.setData(ClipboardData(text: text));
                                                          if (mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              const SnackBar(content: Text('Session ids copied'), duration: Duration(seconds: 1)),
                                                            );
                                                          }
                                                        case 'term':
                                                          await _openTerminal(s);
                                                        case 'delete':
                                                          await sessions.deleteSession(s);
                                                      }
                                                    },
                                                    itemBuilder: (ctx) => [
                                                      PopupMenuItem(value: 'pin', child: Text(pinned ? 'Unpin' : 'Pin')),
                                                      const PopupMenuItem(value: 'copy_key', child: Text('Copy ids')),
                                                      PopupMenuItem(
                                                        value: 'archive',
                                                        child: Text(_archived.contains(s.sessionKey) ? 'Unarchive' : 'Archive'),
                                                      ),
                                                      const PopupMenuItem(value: 'note', child: Text('Note')),
                                                      const PopupMenuItem(value: 'rename', child: Text('Rename')),
                                                      const PopupMenuItem(value: 'export', child: Text('Export meta')),
                                                      const PopupMenuItem(value: 'term', child: Text('Terminal')),
                                                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                                    ],
                                                  ),
                                          );
                                          if (_selectMode) return tile;
                                          return Dismissible(
                                            key: ValueKey('sess-${s.sessionKey}'),
                                            background: Container(
                                              color: Colors.amber.shade700,
                                              alignment: Alignment.centerLeft,
                                              padding: const EdgeInsets.only(left: 20),
                                              child: const Icon(Icons.push_pin, color: Colors.white),
                                            ),
                                            secondaryBackground: Container(
                                              color: Colors.blueGrey.shade600,
                                              alignment: Alignment.centerRight,
                                              padding: const EdgeInsets.only(right: 20),
                                              child: Icon(
                                                _archived.contains(s.sessionKey)
                                                    ? Icons.unarchive
                                                    : Icons.archive,
                                                color: Colors.white,
                                              ),
                                            ),
                                            confirmDismiss: (dir) async {
                                              if (dir == DismissDirection.startToEnd) {
                                                await _togglePin(s);
                                              } else {
                                                await _toggleArchive(s);
                                              }
                                              return false; // keep tile; state updates list
                                            },
                                            child: tile,
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
