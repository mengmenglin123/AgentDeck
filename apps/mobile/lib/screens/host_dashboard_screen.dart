import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_controller.dart';
import '../services/connection_controller.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';
import 'activity_screen.dart';
import 'agents_screen.dart';
import 'logs_screen.dart';
import 'cron_screen.dart';
import 'diff_screen.dart';
import 'mcp_screen.dart';
import 'memory_screen.dart';
import 'pairing_screen.dart';
import 'skills_screen.dart';
import 'workspace_screen.dart';

/// Live Host status dashboard (refreshable /status + quick links).
class HostDashboardScreen extends StatefulWidget {
  const HostDashboardScreen({super.key});

  @override
  State<HostDashboardScreen> createState() => _HostDashboardScreenState();
}

class _HostDashboardScreenState extends State<HostDashboardScreen> {
  Map<String, dynamic> _status = const {};
  String? _error;
  bool _loading = true;
  Timer? _timer;
  bool _wrapLines = false;
  bool _sortAsc = true;
  String _keyQuery = '';
  final _keyFilterCtrl = TextEditingController();
  bool _autoRefresh = true;
  final _scroll = ScrollController();
  DateTime? _lastOk;
  String _capFilter = '';
  String _capQuery = '';
  final _capQueryCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _armTimer();
    });
  }

  @override
  void dispose() {
    _keyFilterCtrl.dispose();
    _capQueryCtrl.dispose();
    _scroll.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _armTimer() {
    _timer?.cancel();
    if (!mounted || !_autoRefresh) return;
    final sec = context.read<AppSettingsController>().dashboardRefreshSec;
    if (sec <= 0) return;
    _timer = Timer.periodic(Duration(seconds: sec), (_) {
      if (!mounted || _loading) return;
      _refresh(silent: true);
    });
  }

  Future<void> _refresh({bool silent = false}) async {
    final conn = context.read<ConnectionController>();
    final cfg = conn.saved;
    if (cfg == null) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final client = MgmtClient(config: cfg);
      final st = await client.status();
      if (!mounted) return;
      setState(() {
        _status = st;
        _loading = false;
        _lastOk = DateTime.now();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Security.redactText(e.toString());
      });
    }
  }



  Future<void> _copyCsv() async {
    final conn = context.read<ConnectionController>();
    final cfg = conn.saved;
    final buf = StringBuffer();
    buf.writeln('key,value');
    void row(String k, Object? v) {
      final raw = v == null ? '' : '$v'.replaceAll('"', '""');
      buf.writeln('$k,"$raw"');
    }
    if (cfg != null) {
      row('host', cfg.host);
      row('mgmt', cfg.mgmtBaseUrl);
      row('bridge', cfg.bridgeWsUrlRedacted);
    }
    for (final e in (_status.entries.toList()
                        ..sort((a, b) {
                          final c = a.key.toLowerCase().compareTo(b.key.toLowerCase());
                          return _sortAsc ? c : -c;
                        }))) {
      final v = e.value;
      if (v is List) {
        row(e.key, v.join('|'));
      } else if (v is Map) {
        row(e.key, v.toString());
      } else {
        row(e.key, v);
      }
    }
    if (_error != null) row('error', _error);
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied status CSV'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _copyCapabilities() async {
    final caps = (_status['capabilities'] as List? ?? const []).map((e) => '$e').toList();
    final text = caps.isEmpty ? '(no capabilities)' : caps.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${caps.length} capabilities'), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _copyStatus() async {
    final conn = context.read<ConnectionController>();
    final cfg = conn.saved;
    final caps = (_status['capabilities'] as List?)?.join(', ') ?? '';
    final text = [
      if (cfg != null) 'host: ${cfg.host}',
      if (cfg != null) 'mgmt: ${cfg.mgmtBaseUrl}',
      if (cfg != null) 'bridge: ${cfg.bridgeWsUrlRedacted}',
      'version: ${_status['version'] ?? '—'}',
      'uptime_seconds: ${_status['uptime_seconds'] ?? '—'}',
      'projects: ${_status['projects_count'] ?? '—'}',
      'sessions: ${_status['sessions_count'] ?? '—'}',
      'active_runs: ${_status['active_runs'] ?? '—'}',
      if (caps.isNotEmpty) 'capabilities: $caps',
      if (_error != null) 'error: $_error',
      if (_lastOk != null) 'last_ok: ${_lastOk!.toIso8601String()}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Status copied (no token)'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionController>();
    final cfg = conn.saved;
    final cs = Theme.of(context).colorScheme;
    final refreshSec = context.watch<AppSettingsController>().dashboardRefreshSec;
    // Re-arm timer when setting changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final armed = _timer != null;
      final want = refreshSec > 0 && _autoRefresh;
      if (armed != want || (want && _timer?.isActive != true)) {
        _armTimer();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _autoRefresh && refreshSec > 0 ? 'Host status · auto ${refreshSec}s' : 'Host status',
        ),
        actions: [
          IconButton(
            tooltip: 'Copy status',
            onPressed: _status.isEmpty && _error == null ? null : _copyStatus,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Copy capabilities',
            onPressed: _status.isEmpty ? null : _copyCapabilities,
            icon: const Icon(Icons.extension_outlined),
          ),
          IconButton(
            tooltip: 'Copy CSV',
            onPressed: _status.isEmpty && _error == null ? null : _copyCsv,
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: _wrapLines ? 'Clamp details' : 'Wrap details',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
          ),
          IconButton(
            tooltip: _sortAsc ? 'Sort keys Z→A' : 'Sort keys A→Z',
            onPressed: () => setState(() => _sortAsc = !_sortAsc),
            icon: Icon(_sortAsc ? Icons.sort_by_alpha : Icons.sort),
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
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: cfg == null
          ? const Center(child: Text('Not connected'))
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
        controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.dns, color: cs.primary),
                  title: Text(cfg.host),
                  subtitle: Text(
                    'Mgmt ${cfg.mgmtBaseUrl}\nBridge ${cfg.bridgeWsUrlRedacted}',
                    style: const TextStyle(fontSize: 12),
                    maxLines: _wrapLines ? 6 : 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                  isThreeLine: true,
                ),
                if (_lastOk != null || refreshSec > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (_lastOk != null)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.schedule, size: 16),
                            label: Text(
                              'Last ok ${_lastOk!.toLocal().toIso8601String().substring(11, 19)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(
                            refreshSec > 0 ? Icons.autorenew : Icons.pause_circle_outline,
                            size: 16,
                          ),
                          label: Text(
                            refreshSec > 0 ? 'Auto every ${refreshSec}s' : 'Auto refresh off',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Live health strip: green when last /status ok, red on error
                Builder(builder: (context) {
                  final connOk = conn.isReady;
                  final degraded = conn.healthDegraded;
                  final healthy = _error == null && _status.isNotEmpty && !degraded;
                  final Color barColor;
                  final String label;
                  if (_loading && _status.isEmpty) {
                    barColor = Colors.amber;
                    label = 'Probing Host /status…';
                  } else if (!connOk && _error != null) {
                    barColor = cs.error;
                    label = 'Host unreachable';
                  } else if (_error != null) {
                    barColor = cs.error;
                    label = 'Status error';
                  } else if (degraded) {
                    barColor = Colors.orange;
                    label = 'Health degraded (heartbeat)';
                  } else if (healthy) {
                    barColor = Colors.green;
                    label = 'Host healthy';
                  } else {
                    barColor = Colors.orange;
                    label = 'Waiting for status';
                  }
                  final age = _lastOk == null
                      ? 'never'
                      : _lastOk!.toLocal().toIso8601String().substring(11, 19);
                  return Card(
                    color: barColor.withOpacity(0.12),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        healthy ? Icons.favorite : (_error != null ? Icons.heart_broken : Icons.monitor_heart_outlined),
                        color: barColor,
                      ),
                      title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: barColor)),
                      subtitle: Text(
                        'Last OK: $age · auto ${refreshSec == 0 ? "off" : "${refreshSec}s"}'
                        '${_error != null ? "\n$_error" : ""}',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                      trailing: TextButton(
                        onPressed: _loading ? null : () => _refresh(),
                        child: const Text('Check'),
                      ),
                    ),
                  );
                }),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatChip(label: 'version', value: '${_status['version'] ?? '—'}'),
                    _StatChip(label: 'uptime', value: _fmtUptime(_status['uptime_seconds'])),
                    _StatChip(label: 'projects', value: '${_status['projects_count'] ?? '—'}'),
                    _StatChip(label: 'sessions', value: '${_status['sessions_count'] ?? '—'}'),
                    _StatChip(label: 'runs', value: '${_status['active_runs'] ?? '—'}'),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  (() {
                    final caps = (_status['capabilities'] as List? ?? const []);
                    if (caps.isEmpty) return 'Capabilities';
                    if (_capFilter.isEmpty) return 'Capabilities (${caps.length})';
                    return 'Capabilities · $_capFilter';
                  })(),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _capQueryCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: 'Filter capabilities',
                      border: const OutlineInputBorder(),
                      suffixIcon: _capQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _capQueryCtrl.clear();
                                setState(() => _capQuery = '');
                              },
                            ),
                    ),
                    onChanged: (v) => setState(() => _capQuery = v),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // full-width search sits above chips via parent Column if present;
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: const Text('All', style: TextStyle(fontSize: 11)),
                      selected: _capFilter.isEmpty,
                      onSelected: (_) => setState(() => _capFilter = ''),
                    ),
                    for (final c in (_status['capabilities'] as List? ?? const []))
                      if (_capQuery.trim().isEmpty ||
                          '$c'.toLowerCase().contains(_capQuery.trim().toLowerCase()))
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(_capIcon('$c'), size: 14),
                        label: Text('$c', style: const TextStyle(fontSize: 11)),
                        selected: _capFilter == '$c',
                        onSelected: (_) => setState(() {
                          _capFilter = _capFilter == '$c' ? '' : '$c';
                        }),
                      ),
                    if ((_status['capabilities'] as List? ?? const []).isEmpty)
                      const Text('—', style: TextStyle(fontSize: 12)),
                  ],
                ),
                if (_capFilter.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Selected capability: $_capFilter (filter is visual highlight only)',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                const Divider(height: 32),
                Text('Shortcuts', style: Theme.of(context).textTheme.titleSmall),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Workspace (readonly)'),
                  subtitle: const Text('Browse host files + mock git status'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => WorkspaceScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.difference_outlined),
                  title: const Text('Git diff (readonly)'),
                  subtitle: const Text('Unified diff from Host'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => DiffScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.psychology_outlined),
                  title: const Text('Host memory'),
                  subtitle: const Text('Readonly catalog from Host'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MemoryScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Host schedules'),
                  subtitle: const Text('Readonly cron jobs'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CronScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('Skills'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => SkillsScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.extension),
                  title: const Text('MCP'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => McpScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.bolt_outlined),
                  title: const Text('Host activity'),
                  subtitle: const Text('Readonly event feed'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ActivityScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('Agents'),
                  subtitle: const Text('Host agent catalog'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AgentsScreen(config: cfg)),
                  ),
                ),

                ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: const Text('Pairing URI'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => PairingScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Host logs'),
                  subtitle: const Text('Readonly log feed'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => LogsScreen(config: cfg)),
                  ),
                ),

                const SizedBox(height: 12),
                ExpansionTile(
                  title: const Text('Raw /status'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: _keyFilterCtrl,
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          hintText: 'Filter keys / values',
                          border: const OutlineInputBorder(),
                          suffixIcon: _keyQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _keyFilterCtrl.clear();
                                    setState(() => _keyQuery = '');
                                  },
                                ),
                        ),
                        onChanged: (v) => setState(() => _keyQuery = v),
                      ),
                    ),
                    for (final e in (() {
                      final q = _keyQuery.trim().toLowerCase();
                      var entries = _status.entries.toList();
                      if (q.isNotEmpty) {
                        entries = entries
                            .where((e) =>
                                e.key.toLowerCase().contains(q) ||
                                '${e.value}'.toLowerCase().contains(q))
                            .toList();
                      }
                      entries.sort((a, b) {
                        final c = a.key.toLowerCase().compareTo(b.key.toLowerCase());
                        return _sortAsc ? c : -c;
                      });
                      return entries;
                    })())
                      ListTile(
                        dense: true,
                        title: Text(e.key),
                        subtitle: Text(
                          Security.redactText('${e.value}'),
                          maxLines: _wrapLines ? 12 : 2,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
    );
  }

  String _fmtUptime(Object? sec) {
    final n = int.tryParse('$sec') ?? 0;
    if (n <= 0) return '—';
    final h = n ~/ 3600;
    final m = (n % 3600) ~/ 60;
    final s = n % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  Future<void> _copyStatus() async {
    final conn = context.read<ConnectionController>();
    final cfg = conn.saved;
    final caps = (_status['capabilities'] as List?)?.join(', ') ?? '';
    final text = [
      if (cfg != null) 'host: ${cfg.host}',
      if (cfg != null) 'mgmt: ${cfg.mgmtBaseUrl}',
      if (cfg != null) 'bridge: ${cfg.bridgeWsUrlRedacted}',
      'version: ${_status['version'] ?? '—'}',
      'uptime_seconds: ${_status['uptime_seconds'] ?? '—'}',
      'projects: ${_status['projects_count'] ?? '—'}',
      'sessions: ${_status['sessions_count'] ?? '—'}',
      'active_runs: ${_status['active_runs'] ?? '—'}',
      if (caps.isNotEmpty) 'capabilities: $caps',
      if (_error != null) 'error: $_error',
      if (_lastOk != null) 'last_ok: ${_lastOk!.toIso8601String()}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Status copied (no token)'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value', style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }
}

IconData _capIcon(String c) {
  final k = c.toLowerCase();
  if (k.contains('terminal') || k.contains('pty')) return Icons.terminal;
  if (k.contains('memory')) return Icons.psychology_outlined;
  if (k.contains('cron')) return Icons.schedule;
  if (k.contains('skill')) return Icons.auto_awesome;
  if (k.contains('mcp')) return Icons.extension;
  if (k.contains('diff') || k.contains('git') || k.contains('workspace')) return Icons.folder_open;
  if (k.contains('activity')) return Icons.bolt_outlined;
  if (k.contains('log')) return Icons.article_outlined;
  if (k.contains('pair')) return Icons.qr_code_2;
  if (k.contains('agent')) return Icons.smart_toy_outlined;
  if (k.contains('stream')) return Icons.waterfall_chart;
  if (k.contains('hermes')) return Icons.hub_outlined;
  return Icons.check_circle_outline;
}
