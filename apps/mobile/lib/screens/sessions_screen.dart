import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/responsive.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/session_info.dart';
import '../services/connection_controller.dart';
import '../services/session_controller.dart';
import '../services/refresh_scheduler.dart';
import '../services/app_settings_controller.dart';
import '../services/session_local_store.dart';
import '../services/theme_controller.dart';
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
  const SessionsScreen({
    super.key,
    this.embedded = false,
    this.initialSessionRef,
  });

  /// When true, hide nested bottom nav (used inside [HomeShell]).
  final bool embedded;
  final String? initialSessionRef;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  SessionController? _sessions;
  final _titleCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  late final RefreshScheduler _refreshScheduler;
  bool _wrapLines = false;
  bool _sortAsc = true;
  bool _autoRefresh = false;
  final _local = SessionLocalStore();
  String _query = '';
  bool _queryCase = false;
  bool _queryRegex = false;
  Set<String> _pinned = {};
  Set<String> _archived = {};
  Map<String, String> _noteMap = {};
  Map<String, int> _recentRank = {};

  /// all | pinned | running | archived
  String _filter = 'all';
  String _agent = '';
  String _platform = '';
  bool _groupByProject = false;
  bool _selectMode = false;
  final Set<String> _selected = {};
  Timer? _searchDebounce;
  String? _handledInitialSessionRef;

  @override
  void initState() {
    super.initState();
    _refreshScheduler = RefreshScheduler(onTick: () async {
      if (!mounted) return;
      final sessions = _sessions;
      if (sessions == null || sessions.loading) return;
      await sessions.refresh();
    });
    _loadPins();
    WidgetsBinding.instance.addPostFrameCallback((_) => _configureRefresh());
  }

  void _configureRefresh() {
    final seconds = context.read<AppSettingsController>().dashboardRefreshSec;
    _refreshScheduler.configure(
      enabled: _autoRefresh,
      interval: Duration(seconds: seconds),
    );
  }

  Future<void> _loadPins() async {
    final data = await _local.loadAll();
    if (!mounted) return;
    setState(() {
      _pinned = data.pins;
      _noteMap = data.notes;
      _archived = data.archived;
      _recentRank = data.recentRanks;
    });
  }

  Future<void> _toggleArchive(SessionInfo s) async {
    await _local.toggleArchive(s.sessionKey);
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
      '仅导出元数据（本机控制台）。对话导出请在聊天页操作。',
    ];
    final text = lines.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('会话元数据已复制')));
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
      SnackBar(
        content: Text('${AppStrings.copiedCsvN}（${list.length}）'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _exportVisibleMeta(List<SessionInfo> list) async {
    if (list.isEmpty) return;
    final buf = StringBuffer('# HuanHermes sessions export (${list.length})\n');
    for (final s in list) {
      final note = _noteMap[s.sessionKey] ?? '';
      buf.writeln(
        '- ${s.displayTitle} | ${s.project} | ${s.sessionKey}'
        '${note.isEmpty ? '' : ' | note: $note'}',
      );
    }
    buf.writeln();
    buf.writeln('Local pins/archives/notes only; tokens never included.');
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${list.length} 行会话')),
    );
  }

  List<SessionInfo> _selectedSessions(List<SessionInfo> all) {
    return all.where((s) => _selected.contains(s.sessionKey)).toList();
  }

  Future<void> _bulkArchive({required bool archive}) async {
    for (final k in _selected.toList()) {
      await _local.setArchived(k, archive);
    }
    await _loadPins();
    _exitSelectMode();
  }

  Future<void> _bulkPin({required bool pin}) async {
    for (final k in _selected.toList()) {
      await _local.setPinned(k, pin);
    }
    await _loadPins();
    _exitSelectMode();
  }

  Future<void> _bulkDelete(
    SessionController sessions,
    List<SessionInfo> all,
  ) async {
    final targets = _selectedSessions(all);
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除 ${targets.length} 个会话？'),
        content: const Text(
          '将在主机上删除会话。本机备注/置顶会保留直至手动清除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
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
        content: Text('公开连接摘要已复制（不含令牌）'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _renameSession(SessionController sessions, SessionInfo s) async {
    final ctrl = TextEditingController(text: s.displayTitle);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: AppStrings.sortByTitle,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final t = ctrl.text.trim();
      if (t.isEmpty) return;
      final r = await sessions.renameSession(s, t);
      if (r == null && mounted && sessions.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(sessions.error!)));
      }
    }
  }

  Future<void> _editNote(SessionInfo s) async {
    final ctrl = TextEditingController(text: _noteMap[s.sessionKey] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('会话备注（仅本机）'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '本机备注 — 不会上传到主机',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await _local.setNote(s.sessionKey, '');
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('清空'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _local.setNote(s.sessionKey, ctrl.text);
      await _loadPins();
    }
  }

  Future<void> _togglePin(SessionInfo s) async {
    context.read<AppSettingsController>().buzzLight();
    await _local.togglePin(s.sessionKey);
    await _loadPins();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final conn = context.watch<ConnectionController>();
    final cfg = conn.saved;
    if (cfg == null) return;
    _sessions = context.watch<SessionController>();
    _sessions!.updateConfig(cfg);
    final ref = widget.initialSessionRef?.trim();
    if (ref != null && ref.isNotEmpty && _handledInitialSessionRef != ref) {
      _handledInitialSessionRef = ref;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _openInitialSession(ref));
    }
  }

  Future<void> _openInitialSession(String reference) async {
    final controller = _sessions;
    if (controller == null) return;
    final session = await controller.locateSession(reference);
    if (!mounted) return;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('通知对应的会话不存在或已删除')),
      );
      return;
    }
    await _openChat(session);
  }

  @override
  void dispose() {
    _refreshScheduler.dispose();
    _scroll.dispose();
    _searchDebounce?.cancel();
    _titleCtrl.dispose();
    _searchCtrl.dispose();
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
        base = base.where(
          (s) => (_noteMap[s.sessionKey] ?? '').trim().isNotEmpty,
        );
      }
    }
    if (_agent.isNotEmpty) {
      base = base.where((s) {
        final a = (s.agentType ?? '').toLowerCase();
        if (_agent == 'other') {
          return a.isNotEmpty &&
              !a.contains('hermes') &&
              !a.contains('claude') &&
              !a.contains('codex');
        }
        return a.contains(_agent);
      });
    }
    if (_platform.isNotEmpty) {
      base = base.where((s) {
        final p = (s.platform ?? '').toLowerCase();
        if (_platform == 'other') {
          return p.isNotEmpty &&
              !p.contains('telegram') &&
              !p.contains('discord') &&
              !p.contains('slack') &&
              !p.contains('feishu') &&
              !p.contains('whatsapp') &&
              !p.contains('local') &&
              !p.contains('mock');
        }
        return p.contains(_platform);
      });
    }
    if (rawQ.isNotEmpty) {
      base = base.where((s) {
        final note = _noteMap[s.sessionKey] ?? '';
        final hayRaw =
            '${s.displayTitle} ${s.project} ${s.sessionKey} ${s.model ?? ''} ${s.platform ?? ''} $note';
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
      int dir(int c) => _sortAsc ? c : -c;
      if (sortMode != 'pinned' && sortMode != 'archived') {
        final ap = _pinned.contains(a.sessionKey) ? 0 : 1;
        final bp = _pinned.contains(b.sessionKey) ? 0 : 1;
        if (ap != bp) return ap.compareTo(bp);
      }
      switch (sortMode) {
        case 'title':
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
        case 'project':
          final pc = a.project.toLowerCase().compareTo(b.project.toLowerCase());
          if (pc != 0) return dir(pc);
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
        case 'created':
          return dir(
            (b.createdAt ?? b.updatedAt ?? 0).compareTo(
              a.createdAt ?? a.updatedAt ?? 0,
            ),
          );
        case 'model':
          final mc = (a.model ?? '').toLowerCase().compareTo(
                (b.model ?? '').toLowerCase(),
              );
          if (mc != 0) return dir(mc);
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
        case 'key':
          final kc = a.sessionKey.toLowerCase().compareTo(
                b.sessionKey.toLowerCase(),
              );
          if (kc != 0) return dir(kc);
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
        case 'platform':
          final pc = (a.platform ?? '').toLowerCase().compareTo(
                (b.platform ?? '').toLowerCase(),
              );
          if (pc != 0) return dir(pc);
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
        case 'agent':
          final ac = (a.agentType ?? '').toLowerCase().compareTo(
                (b.agentType ?? '').toLowerCase(),
              );
          if (ac != 0) return dir(ac);
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
        case 'mode':
          final mc = (a.mode ?? '').toLowerCase().compareTo(
                (b.mode ?? '').toLowerCase(),
              );
          if (mc != 0) return dir(mc);
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
        case 'workdir':
          final wc = (a.workdir ?? '').toLowerCase().compareTo(
                (b.workdir ?? '').toLowerCase(),
              );
          if (wc != 0) return dir(wc);
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
        case 'running':
          final rc = (a.running ? 1 : 0).compareTo(b.running ? 1 : 0);
          if (rc != 0) return dir(-rc); // running first in default dir
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
        case 'live':
          final lc = (a.live ? 1 : 0).compareTo(b.live ? 1 : 0);
          if (lc != 0) return dir(-lc); // live first
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
        case 'last':
          final la = (a.lastUser ?? '').toLowerCase();
          final lb = (b.lastUser ?? '').toLowerCase();
          final lsc = la.compareTo(lb);
          if (lsc != 0) return dir(lsc);
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
        case 'pinned':
          final pa = _pinned.contains(a.sessionKey) ? 1 : 0;
          final pb = _pinned.contains(b.sessionKey) ? 1 : 0;
          final pc = pa.compareTo(pb);
          if (pc != 0) return dir(-pc); // pinned first by default dir
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
        case 'note':
          final na = (_noteMap[a.sessionKey] ?? '').toLowerCase();
          final nb = (_noteMap[b.sessionKey] ?? '').toLowerCase();
          final nc = na.compareTo(nb);
          if (nc != 0) return dir(nc);
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
        case 'archived':
          final aa = _archived.contains(a.sessionKey) ? 1 : 0;
          final ab = _archived.contains(b.sessionKey) ? 1 : 0;
          final ac = aa.compareTo(ab);
          if (ac != 0) return dir(-ac); // archived first by default dir
          return dir(
            a.displayTitle.toLowerCase().compareTo(
                  b.displayTitle.toLowerCase(),
                ),
          );
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
      final p = s.project.isEmpty ? '（无项目）' : s.project;
      map.putIfAbsent(p, () => []).add(s);
    }
    final keys = map.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
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
    final project = _sessions?.projects
        .where((item) => item.name == session.project)
        .firstOrNull;
    if (project != null && !project.hasCapability('terminal')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前 Agent 未提供终端能力')),
        );
      }
      return;
    }
    await _local.touchRecent(session.sessionKey);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.error!)));
    }
  }

  Future<void> _openChat(SessionInfo session) async {
    final conn = context.read<ConnectionController>();
    final cfg = conn.saved;
    if (cfg == null) return;
    await _local.touchRecent(session.sessionKey);
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
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              SizedBox(height: 12),
              Text('加载会话…', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: sessions,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            leading: _selectMode
                ? IconButton(
                    tooltip: AppStrings.selectCancel,
                    icon: const Icon(Icons.close),
                    onPressed: _exitSelectMode,
                  )
                : null,
            title: Text(
              _selectMode
                  ? '${AppStrings.selectedN} ${_selected.length}'
                  : AppStrings.tabSessions,
            ),
            actions: [
              if (_selectMode) ...[
                IconButton(
                  tooltip: AppStrings.deleteSelected,
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _bulkDelete(sessions, sessions.sessions),
                  icon: const Icon(Icons.delete_outline),
                ),
                PopupMenuButton<String>(
                  tooltip: AppStrings.more,
                  enabled: _selected.isNotEmpty,
                  onSelected: (v) async {
                    final picked = _selectedSessions(sessions.sessions);
                    switch (v) {
                      case 'export':
                        _exportVisibleMeta(picked);
                        return;
                      case 'pin':
                        await _bulkPin(pin: true);
                        return;
                      case 'unpin':
                        await _bulkPin(pin: false);
                        return;
                      case 'archive':
                        await _bulkArchive(archive: true);
                        return;
                      case 'unarchive':
                        await _bulkArchive(archive: false);
                        return;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'export',
                      child: Text(AppStrings.exportSelected),
                    ),
                    const PopupMenuItem(
                      value: 'pin',
                      child: Text(AppStrings.pinSelected),
                    ),
                    const PopupMenuItem(
                      value: 'unpin',
                      child: Text('取消置顶所选'),
                    ),
                    PopupMenuItem(
                      value: _filter == 'archived' ? 'unarchive' : 'archive',
                      child: Text(
                        _filter == 'archived'
                            ? '取消归档所选'
                            : AppStrings.archiveSelected,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                IconButton(
                  tooltip: AppStrings.refresh,
                  onPressed: sessions.loading ? null : sessions.refresh,
                  icon: const Icon(Icons.refresh),
                ),
                PopupMenuButton<String>(
                  tooltip: AppStrings.more,
                  onSelected: (v) async {
                    final cfg = conn.saved;
                    switch (v) {
                      case 'theme':
                        context.read<ThemeController>().cycle();
                        return;
                      case 'select':
                        _enterSelectMode();
                        return;
                      case 'share':
                        _shareConnection(conn);
                        return;
                      case 'host':
                        if (!widget.embedded) {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const HostDashboardScreen(),
                            ),
                          );
                        }
                        return;
                      case 'export_list':
                        _exportVisibleMeta(_filtered(sessions.sessions));
                        return;
                      case 'csv_list':
                        _copyVisibleCsv(_filtered(sessions.sessions));
                        return;
                      case 'wrap':
                        setState(() => _wrapLines = !_wrapLines);
                        return;
                      case 'sort_dir':
                        setState(() => _sortAsc = !_sortAsc);
                        return;
                      case 'auto':
                        setState(() => _autoRefresh = !_autoRefresh);
                        _configureRefresh();
                        return;
                      case 'top':
                        if (_scroll.hasClients) {
                          _scroll.animateTo(
                            0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          );
                        }
                        return;
                      case 'bottom':
                        if (_scroll.hasClients) {
                          _scroll.animateTo(
                            _scroll.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                          );
                        }
                        return;
                      case 'disconnect':
                        conn.disconnect();
                        return;
                      case 'clear':
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('清除已保存配置？'),
                            content: const Text('将移除本机主机设置与令牌。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text(AppStrings.cancel),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('清除'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await conn.disconnect(clearStorage: true);
                        }
                        return;
                      default:
                        if (cfg == null) return;
                        Widget page;
                        switch (v) {
                          case 'status':
                            page = const HostDashboardScreen();
                            break;
                          case 'agents':
                            page = AgentsScreen(
                                config: cfg, project: sessions.selectedProject);
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
                            page = MemoryScreen(
                              config: cfg,
                              project: sessions.selectedProject,
                            );
                            break;
                          case 'activity':
                            page = ActivityScreen(
                              config: cfg,
                              sessions: sessions.sessions,
                            );
                            break;
                          case 'cron':
                            page = CronScreen(config: cfg);
                            break;
                          case 'skills':
                            page = SkillsScreen(
                                config: cfg, project: sessions.selectedProject);
                            break;
                          case 'mcp':
                            page = McpScreen(
                                config: cfg, project: sessions.selectedProject);
                            break;
                          case 'pairing':
                            page = PairingScreen(config: cfg);
                            break;
                          default:
                            return;
                        }
                        if (widget.embedded &&
                            (v == 'settings' || v == 'status')) {
                          // Prefer bottom tabs when embedded.
                          return;
                        }
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => page),
                        );
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'theme',
                      child: Text(AppStrings.theme),
                    ),
                    const PopupMenuItem(
                      value: 'select',
                      child: Text(AppStrings.select),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      child: Text(AppStrings.connectionShare),
                    ),
                    PopupMenuItem(
                      value: 'export_list',
                      child: Text(AppStrings.exportMeta),
                    ),
                    PopupMenuItem(
                      value: 'csv_list',
                      child: Text(AppStrings.copyCsv),
                    ),
                    PopupMenuItem(
                      value: 'wrap',
                      child: Text(
                        _wrapLines
                            ? AppStrings.clampDetails
                            : AppStrings.wrapDetails,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'sort_dir',
                      child: Text(AppStrings.sortDir),
                    ),
                    PopupMenuItem(
                      value: 'auto',
                      child: Text(
                        _autoRefresh
                            ? AppStrings.pauseRefresh
                            : AppStrings.autoRefresh,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'top',
                      child: Text(AppStrings.jumpTop),
                    ),
                    PopupMenuItem(
                      value: 'bottom',
                      child: Text(AppStrings.jumpBottom),
                    ),
                    if (!widget.embedded) ...[
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'status',
                        child: Text(AppStrings.hostStatus),
                      ),
                      const PopupMenuItem(
                        value: 'agents',
                        child: Text('代理'),
                      ),
                      const PopupMenuItem(
                        value: 'logs',
                        child: Text('主机日志'),
                      ),
                      const PopupMenuItem(
                        value: 'workspace',
                        child: Text('工作区'),
                      ),
                      const PopupMenuItem(
                        value: 'diff',
                        child: Text('Git 对比'),
                      ),
                      const PopupMenuItem(
                        value: 'memory',
                        child: Text('主机记忆'),
                      ),
                      const PopupMenuItem(
                        value: 'activity',
                        child: Text('主机活动'),
                      ),
                      const PopupMenuItem(
                        value: 'cron',
                        child: Text('定时任务'),
                      ),
                      const PopupMenuItem(
                        value: 'skills',
                        child: Text('技能'),
                      ),
                      const PopupMenuItem(
                        value: 'mcp',
                        child: Text('MCP'),
                      ),
                      const PopupMenuItem(
                        value: 'pairing',
                        child: Text('配对'),
                      ),
                      const PopupMenuItem(
                        value: 'settings',
                        child: Text(AppStrings.settings),
                      ),
                    ],
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'disconnect',
                      child: Text('编辑连接'),
                    ),
                    const PopupMenuItem(
                      value: 'clear',
                      child: Text('清除配置'),
                    ),
                  ],
                ),
              ], // end non-select actions
            ],
          ),
          bottomNavigationBar: widget.embedded
              ? null
              : NavigationBar(
                  selectedIndex: 0,
                  onDestinationSelected: (index) async {
                    final cfg = conn.saved;
                    if (cfg == null) return;
                    Widget? page;
                    switch (index) {
                      case 0:
                        return; // Already on Sessions
                      case 1:
                        page = WorkspaceScreen(config: cfg);
                        break;
                      case 2:
                        page = TerminalScreen(
                          config: cfg,
                          session: sessions.sessions.isNotEmpty
                              ? sessions.sessions.first
                              : SessionInfo(
                                  id: 'terminal',
                                  sessionKey: 'terminal',
                                  title: '终端',
                                  project: '',
                                ),
                        );
                        break;
                      case 3:
                        page = const SettingsScreen();
                        break;
                    }
                    if (page != null) {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => page!),
                      );
                    }
                  },
                  destinations: [
                    NavigationDestination(
                      icon: Icon(Icons.chat_outlined),
                      selectedIcon: Icon(Icons.chat),
                      label: AppStrings.tabSessions,
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.folder_outlined),
                      selectedIcon: Icon(Icons.folder),
                      label: '工作区',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.terminal_outlined),
                      selectedIcon: Icon(Icons.terminal),
                      label: AppStrings.toolTerminal,
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: AppStrings.tabSettings,
                    ),
                  ],
                ),
          body: Column(
            children: [
              // Responsive padding for tablet/desktop
              if (ResponsiveLayout.isTablet(context) ||
                  ResponsiveLayout.isDesktop(context))
                SizedBox(height: ResponsiveLayout.screenPadding(context).top),
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
                  subtitle: Text(
                    '${conn.saved!.host} · ${conn.saved!.mgmtBaseUrl}',
                  ),
                  trailing: conn.profiles.length > 1
                      ? PopupMenuButton<String>(
                          tooltip: '切换主机配置',
                          icon: const Icon(Icons.swap_horiz, size: 20),
                          onSelected: (id) async {
                            if (id == conn.activeProfileId) return;
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('切换主机配置?'),
                                content: const Text(
                                  '断开当前主机并测试所选配置。 '
                                  '会话列表将为新主机重新加载。',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('切换'),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true || !context.mounted) return;
                            final success = await conn.switchAndConnect(id);
                            if (!context.mounted) return;
                            if (success) {
                              final shared = context.read<SessionController>();
                              shared.updateConfig(conn.saved!);
                              await shared.refresh();
                              _sessions = shared;
                              if (mounted) setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已切换主机配置'),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    conn.lastError ?? '切换失败',
                                  ),
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
              // Quick action cards
              if (conn.saved != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _QuickActionCard(
                          icon: Icons.folder_outlined,
                          label: '工作区',
                          color: const Color(0xFF4A90E2),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  WorkspaceScreen(config: conn.saved!),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _QuickActionCard(
                          icon: Icons.terminal,
                          label: '终端',
                          color: const Color(0xFF7CB342),
                          onTap: () {
                            final s = _sessions;
                            if (s == null || s.sessions.isEmpty) return;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TerminalScreen(
                                  config: conn.saved!,
                                  session: s.sessions.first,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        _QuickActionCard(
                          icon: Icons.extension_outlined,
                          label: '技能',
                          color: const Color(0xFFFF8A65),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SkillsScreen(
                                  config: conn.saved!,
                                  project: sessions.selectedProject),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _QuickActionCard(
                          icon: Icons.schedule,
                          label: '定时任务',
                          color: const Color(0xFFAB47BC),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CronScreen(config: conn.saved!),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _QuickActionCard(
                          icon: Icons.hub_outlined,
                          label: 'MCP',
                          color: const Color(0xFF26A69A),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => McpScreen(
                                  config: conn.saved!,
                                  project: sessions.selectedProject),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (conn.saved != null)
                Material(
                  color: conn.healthDegraded
                      ? Theme.of(
                          context,
                        ).colorScheme.errorContainer.withOpacity(0.55)
                      : Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest.withOpacity(0.45),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      conn.healthDegraded
                          ? Icons.cloud_off
                          : Icons.cloud_done_outlined,
                      size: 18,
                      color: conn.healthDegraded
                          ? Theme.of(context).colorScheme.error
                          : Colors.green.shade700,
                    ),
                    title: Text(
                      conn.healthDegraded ? '主机健康降级' : '主机健康正常',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      [
                        if (conn.lastHealthOkAt != null)
                          'Last OK: ${conn.lastHealthOkAt!.toLocal().toIso8601String().substring(11, 19)}',
                        if (conn.lastHealthError != null)
                          '错误：${conn.lastHealthError}',
                        if (conn.lastStatus != null &&
                            conn.lastStatus!['version'] != null)
                          'version: ${conn.lastStatus!['version']}',
                        '连接期间每 30 秒探测',
                      ].where((e) => e.toString().isNotEmpty).join(' · '),
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: TextButton(
                      onPressed:
                          conn.healthChecking ? null : () => conn.probeHealth(),
                      child: Text(conn.healthChecking ? '…' : 'Check'),
                    ),
                  ),
                ),
              if (sessions.projects.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: DropdownButtonFormField<String>(
                    value: sessions.projects.any(
                      (p) => p.name == sessions.selectedProject,
                    )
                        ? sessions.selectedProject
                        : null,
                    decoration: const InputDecoration(
                      labelText: AppStrings.sortByProject,
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
                        ? (_queryCase
                            ? 'Search (regex · case)'
                            : 'Search (regex)')
                        : (_queryCase
                            ? 'Search (case-sensitive)'
                            : '搜索会话 / 备注'),
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
                      onLongPress: () =>
                          setState(() => _queryRegex = !_queryRegex),
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
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 220),
                      () {
                        if (!mounted) return;
                        setState(() => _query = v);
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final f in const [
                      ('all', '全部'),
                      ('pinned', '置顶'),
                      ('running', '运行中'),
                      ('notes', '备注'),
                      ('archived', '已归档'),
                    ])
                      FilterChip(
                        label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                        selected: _filter == f.$1,
                        onSelected: (_) => setState(() => _filter = f.$1),
                        visualDensity: VisualDensity.compact,
                      ),
                    FilterChip(
                      label: const Text(
                        AppStrings.groupBy,
                        style: TextStyle(fontSize: 12),
                      ),
                      selected: _groupByProject,
                      avatar: Icon(
                        _groupByProject ? Icons.folder : Icons.folder_outlined,
                        size: 16,
                      ),
                      onSelected: (v) => setState(() => _groupByProject = v),
                      visualDensity: VisualDensity.compact,
                    ),
                    FilterChip(
                      label: const Text(AppStrings.wrap,
                          style: TextStyle(fontSize: 11)),
                      selected: _wrapLines,
                      onSelected: (v) => setState(() => _wrapLines = v),
                      visualDensity: VisualDensity.compact,
                    ),
                    FilterChip(
                      label: const Text(
                        AppStrings.regex,
                        style: TextStyle(fontSize: 11),
                      ),
                      selected: _queryRegex,
                      onSelected: (v) => setState(() => _queryRegex = v),
                      visualDensity: VisualDensity.compact,
                    ),
                    FilterChip(
                      label: const Text(AppStrings.matchCase,
                          style: TextStyle(fontSize: 11)),
                      selected: _queryCase,
                      onSelected: (v) => setState(() => _queryCase = v),
                      visualDensity: VisualDensity.compact,
                    ),
                    FilterChip(
                      label: const Text(AppStrings.autoRefresh,
                          style: TextStyle(fontSize: 11)),
                      selected: _autoRefresh,
                      onSelected: (v) {
                        setState(() => _autoRefresh = v);
                        _configureRefresh();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                    for (final f in const [
                      ('', '任意 Agent'),
                      ('hermes', 'hermes'),
                      ('claude', 'claude'),
                      ('codex', 'codex'),
                      ('other', '其他'),
                    ])
                      FilterChip(
                        label: Text(f.$2, style: const TextStyle(fontSize: 11)),
                        selected: _agent == f.$1,
                        onSelected: (_) => setState(() => _agent = f.$1),
                        visualDensity: VisualDensity.compact,
                      ),
                    for (final f in const [
                      ('', '任意平台'),
                      ('telegram', 'telegram'),
                      ('discord', 'discord'),
                      ('slack', 'slack'),
                      ('feishu', 'feishu'),
                      ('other', '其他'),
                    ])
                      FilterChip(
                        label: Text(f.$2, style: const TextStyle(fontSize: 11)),
                        selected: _platform == f.$1,
                        onSelected: (_) => setState(() => _platform = f.$1),
                        visualDensity: VisualDensity.compact,
                      ),
                    Builder(
                      builder: (context) {
                        final settings = context.watch<AppSettingsController>();
                        return PopupMenuButton<String>(
                          tooltip: '排序',
                          initialValue: settings.sessionSort,
                          onSelected: (v) async {
                            await settings.setSessionSort(v);
                            setState(() {});
                          },
                          itemBuilder: (ctx) => const [
                            PopupMenuItem(
                              value: 'updated',
                              child: Text('排序：更新时间'),
                            ),
                            PopupMenuItem(
                              value: 'recent',
                              child: Text('排序：最近'),
                            ),
                            PopupMenuItem(
                              value: 'title',
                              child: Text('排序：标题'),
                            ),
                            PopupMenuItem(
                              value: 'project',
                              child: Text('排序：项目'),
                            ),
                            PopupMenuItem(
                              value: 'created',
                              child: Text('排序：创建时间'),
                            ),
                            PopupMenuItem(
                              value: 'model',
                              child: Text('排序：模型'),
                            ),
                            PopupMenuItem(
                              value: 'key',
                              child: Text('排序：键'),
                            ),
                            PopupMenuItem(
                              value: 'platform',
                              child: Text('排序：平台'),
                            ),
                            PopupMenuItem(
                              value: 'agent',
                              child: Text('排序：代理'),
                            ),
                            PopupMenuItem(
                              value: 'mode',
                              child: Text('排序：模式'),
                            ),
                            PopupMenuItem(
                              value: 'workdir',
                              child: Text('排序：工作目录'),
                            ),
                            PopupMenuItem(
                              value: 'running',
                              child: Text('排序：运行中'),
                            ),
                            PopupMenuItem(
                              value: 'live',
                              child: Text('排序：实时'),
                            ),
                            PopupMenuItem(
                              value: 'last',
                              child: Text('排序：最后消息'),
                            ),
                            PopupMenuItem(
                              value: 'pinned',
                              child: Text('排序：置顶'),
                            ),
                            PopupMenuItem(
                              value: 'note',
                              child: Text('排序：备注'),
                            ),
                            PopupMenuItem(
                              value: 'archived',
                              child: Text('排序：归档'),
                            ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Chip(
                              avatar: const Icon(Icons.sort, size: 16),
                              label: Text(
                                {
                                      'title': AppStrings.sortByTitle,
                                      'project': AppStrings.sortByProject,
                                      'created': '创建时间',
                                      'model': '模型',
                                      'key': '键',
                                      'recent': '最近',
                                      'platform': '平台',
                                      'agent': '代理',
                                      'mode': '模式',
                                      'workdir': '工作目录',
                                      'running': '运行中',
                                      'live': '实时',
                                      'last': '最近消息',
                                      'pinned': '置顶',
                                      'note': '备注',
                                      'archived': '已归档',
                                    }[settings.sessionSort] ??
                                    '更新时间',
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
                          hintText: '新会话标题（可选）',
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
                      label: const Text(AppStrings.createNew),
                    ),
                  ],
                ),
              ),
              if (sessions.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    sessions.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
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
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      32,
                                      24,
                                      24,
                                    ),
                                    children: [
                                      Icon(
                                        Icons.forum_outlined,
                                        size: 48,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '还没有会话',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '本应用仅为远程控制台 — Agent 在主机上运行。\n'
                                        '1) Confirm Host health above is OK\n'
                                        '2) Pick a project if listed\n'
                                        '3) Tap New to create a session\n'
                                        '4) 打开会话控制 Claude Code / Codex / Hermes',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          height: 1.35,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Center(
                                        child: FilledButton.icon(
                                          onPressed:
                                              sessions.loading ? null : _create,
                                          icon: const Icon(Icons.add),
                                          label: const Text(
                                            '创建第一个会话',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Center(
                                        child: TextButton.icon(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    const HostDashboardScreen(),
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.monitor_heart_outlined,
                                          ),
                                          label: const Text(
                                            '打开主机仪表盘',
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : visible.isEmpty
                                    ? ListView(
                                        padding: const EdgeInsets.fromLTRB(
                                          24,
                                          48,
                                          24,
                                          24,
                                        ),
                                        children: [
                                          Icon(
                                            Icons.filter_alt_off_outlined,
                                            size: 40,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.outline,
                                          ),
                                          const SizedBox(height: 12),
                                          const Center(
                                            child: Text(
                                              '没有匹配的会话',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _filter == 'archived'
                                                ? 'Nothing archived on this device, or search hides them.'
                                                : '请尝试清除筛选条件或创建新会话',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
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
                                              child: const Text('重置筛选'),
                                            ),
                                          ),
                                        ],
                                      )
                                    : ListView.separated(
                                        controller: _scroll,
                                        padding: const EdgeInsets.fromLTRB(
                                            12, 8, 12, 24),
                                        itemCount: _visibleRows(visible).length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 8),
                                        itemBuilder: (context, i) {
                                          final row = _visibleRows(visible)[i];
                                          if (row is String) {
                                            final count = visible
                                                .where((s) =>
                                                    (s.project.isEmpty
                                                        ? '（无项目）'
                                                        : s.project) ==
                                                    row)
                                                .length;
                                            final cs =
                                                Theme.of(context).colorScheme;
                                            final isDark =
                                                Theme.of(context).brightness ==
                                                    Brightness.dark;
                                            return Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? Colors.white
                                                        .withOpacity(0.03)
                                                    : cs.surfaceContainerHighest
                                                        .withOpacity(0.65),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: isDark
                                                      ? Colors.white
                                                          .withOpacity(0.06)
                                                      : cs.outlineVariant
                                                          .withOpacity(0.6),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.folder_outlined,
                                                    size: 18,
                                                    color: cs.primary,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      row,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 13,
                                                        letterSpacing: -0.1,
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    '$count 个会话',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          cs.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                          final s = row as SessionInfo;
                                          final pinned = _pinned.contains(
                                            s.sessionKey,
                                          );
                                          final note = _noteMap[s.sessionKey];
                                          final compact = context
                                              .watch<AppSettingsController>()
                                              .compactMode;
                                          final selected = _selected.contains(
                                            s.sessionKey,
                                          );
                                          final projCaps = sessions.projects
                                              .where((p) => p.name == s.project)
                                              .map((p) => p.capabilities)
                                              .firstWhere(
                                                (_) => true,
                                                orElse: () => const <String>[],
                                              );
                                          final cs =
                                              Theme.of(context).colorScheme;
                                          final isDark =
                                              Theme.of(context).brightness ==
                                                  Brightness.dark;
                                          final tile = ListTile(
                                            selected: selected,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            visualDensity: compact
                                                ? VisualDensity.compact
                                                : const VisualDensity(
                                                    horizontal: 0,
                                                    vertical: 1,
                                                  ),
                                            title: Text(
                                              s.displayTitle,
                                              maxLines: _wrapLines ? 4 : 2,
                                              overflow: TextOverflow.ellipsis,
                                              softWrap: true,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: -0.15,
                                              ),
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  [
                                                    '${s.project} · ${s.model ?? "未知模型"}',
                                                    s.sessionKey,
                                                    if (note != null &&
                                                        note.isNotEmpty)
                                                      '📝 $note',
                                                  ].join('\n'),
                                                  maxLines: _wrapLines ? 8 : 3,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  softWrap: true,
                                                ),
                                                if (projCaps.isNotEmpty &&
                                                    !_selectMode) ...[
                                                  const SizedBox(height: 4),
                                                  Wrap(
                                                    spacing: 4,
                                                    runSpacing: 2,
                                                    children: [
                                                      for (final c
                                                          in projCaps.take(
                                                        4,
                                                      ))
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 6,
                                                            vertical: 1,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              8,
                                                            ),
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .secondaryContainer
                                                                .withOpacity(
                                                                    0.7),
                                                          ),
                                                          child: Text(
                                                            c.toString(),
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color: Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .onSecondaryContainer,
                                                            ),
                                                          ),
                                                        ),
                                                      if (projCaps.length > 4)
                                                        Text(
                                                          '+${projCaps.length - 4}',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 10,
                                                          ),
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
                                                    onChanged: (_) =>
                                                        _toggleSelected(s),
                                                  )
                                                : Container(
                                                    width: 42,
                                                    height: 42,
                                                    decoration: BoxDecoration(
                                                      color: pinned
                                                          ? const Color(
                                                                  0xFFF59E0B)
                                                              .withOpacity(0.14)
                                                          : s.running
                                                              ? const Color(
                                                                      0xFF5E6AD2)
                                                                  .withOpacity(
                                                                      0.14)
                                                              : (isDark
                                                                  ? Colors.white
                                                                      .withOpacity(
                                                                          0.05)
                                                                  : cs.surfaceContainerHighest),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                      border: Border.all(
                                                        color: pinned
                                                            ? const Color(0xFFF59E0B)
                                                                .withOpacity(
                                                                    0.35)
                                                            : s.running
                                                                ? const Color(
                                                                        0xFF5E6AD2)
                                                                    .withOpacity(
                                                                        0.3)
                                                                : (isDark
                                                                    ? Colors
                                                                        .white
                                                                        .withOpacity(
                                                                            0.08)
                                                                    : cs.outlineVariant
                                                                        .withOpacity(
                                                                            0.7)),
                                                      ),
                                                    ),
                                                    child: Icon(
                                                      pinned
                                                          ? Icons.push_pin
                                                          : s.running
                                                              ? Icons
                                                                  .play_circle_fill
                                                              : Icons
                                                                  .chat_bubble_outline,
                                                      size: 20,
                                                      color: pinned
                                                          ? const Color(
                                                              0xFFF59E0B)
                                                          : s.running
                                                              ? const Color(
                                                                  0xFF5E6AD2)
                                                              : cs.onSurfaceVariant,
                                                    ),
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
                                                    tooltip: '会话操作',
                                                    onSelected: (v) async {
                                                      switch (v) {
                                                        case 'export':
                                                          _exportSessionMeta(s);
                                                        case 'rename':
                                                          await _renameSession(
                                                            sessions,
                                                            s,
                                                          );
                                                        case 'archive':
                                                          await _toggleArchive(
                                                              s);
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
                                                          await Clipboard
                                                              .setData(
                                                            ClipboardData(
                                                              text: text,
                                                            ),
                                                          );
                                                          if (mounted) {
                                                            ScaffoldMessenger
                                                                .of(
                                                              context,
                                                            ).showSnackBar(
                                                              const SnackBar(
                                                                content: Text(
                                                                  '会话 ID 已复制',
                                                                ),
                                                                duration:
                                                                    Duration(
                                                                  seconds: 1,
                                                                ),
                                                              ),
                                                            );
                                                          }
                                                        case 'term':
                                                          await _openTerminal(
                                                              s);
                                                        case 'delete':
                                                          await sessions
                                                              .deleteSession(s);
                                                      }
                                                    },
                                                    itemBuilder: (ctx) => [
                                                      PopupMenuItem(
                                                        value: 'pin',
                                                        child: Text(
                                                          pinned
                                                              ? '取消置顶'
                                                              : '置顶',
                                                        ),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'copy_key',
                                                        child: Text('复制 ID'),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 'archive',
                                                        child: Text(
                                                          _archived.contains(
                                                            s.sessionKey,
                                                          )
                                                              ? '取消归档'
                                                              : '归档',
                                                        ),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'note',
                                                        child: Text(
                                                            AppStrings.note),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'rename',
                                                        child: Text(
                                                            AppStrings.rename),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'export',
                                                        child: Text('导出元数据'),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'term',
                                                        child: Text('终端'),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'delete',
                                                        child: Text(
                                                            AppStrings.delete),
                                                      ),
                                                    ],
                                                  ),
                                          );
                                          Widget cardWrap(Widget child) {
                                            return Container(
                                              decoration: BoxDecoration(
                                                color: selected
                                                    ? cs.primaryContainer
                                                        .withOpacity(isDark
                                                            ? 0.28
                                                            : 0.45)
                                                    : (isDark
                                                        ? Colors.white
                                                            .withOpacity(0.03)
                                                        : cs.surfaceContainer),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: selected
                                                      ? cs.primary
                                                          .withOpacity(0.45)
                                                      : (isDark
                                                          ? Colors.white
                                                              .withOpacity(0.08)
                                                          : cs.outlineVariant
                                                              .withOpacity(
                                                                  0.7)),
                                                ),
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child: child,
                                            );
                                          }

                                          if (_selectMode) {
                                            return cardWrap(tile);
                                          }
                                          return Dismissible(
                                            key: ValueKey(
                                                'sess-${s.sessionKey}'),
                                            background: Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF59E0B),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              alignment: Alignment.centerLeft,
                                              padding: const EdgeInsets.only(
                                                left: 20,
                                              ),
                                              child: const Icon(
                                                Icons.push_pin,
                                                color: Colors.white,
                                              ),
                                            ),
                                            secondaryBackground: Container(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF64748B),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              alignment: Alignment.centerRight,
                                              padding: const EdgeInsets.only(
                                                right: 20,
                                              ),
                                              child: Icon(
                                                _archived.contains(s.sessionKey)
                                                    ? Icons.unarchive
                                                    : Icons.archive,
                                                color: Colors.white,
                                              ),
                                            ),
                                            confirmDismiss: (dir) async {
                                              if (dir ==
                                                  DismissDirection.startToEnd) {
                                                await _togglePin(s);
                                              } else {
                                                await _toggleArchive(s);
                                              }
                                              return false; // keep tile; state updates list
                                            },
                                            child: cardWrap(tile),
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

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 90,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
