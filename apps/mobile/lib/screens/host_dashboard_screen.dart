import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_controller.dart';
import '../services/connection_controller.dart';
import '../services/mgmt_client.dart';
import '../services/refresh_scheduler.dart';
import '../services/session_controller.dart';
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
import '../l10n/app_strings.dart';
import '../widgets/app_bar_actions.dart';

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
  late final RefreshScheduler _refreshScheduler;
  bool _wrapLines = false;
  bool _sortAsc = true;
  bool _sortByValue = false;
  bool _sortByType = false;
  bool _sortByKey = false;
  bool _queryCase = false;
  bool _queryRegex = false;
  bool _relativeTs = false;
  String _keyQuery = '';
  String _typeFilter = ''; // empty=all
  final _keyFilterCtrl = TextEditingController();
  bool _autoRefresh = true;
  final _scroll = ScrollController();
  DateTime? _lastOk;
  String _capFilter = '';
  String _capQuery = '';
  final _capQueryCtrl = TextEditingController();

  String _valueTypeLabel(dynamic v) {
    if (v == null) return '空';
    if (v is bool) return '布尔';
    if (v is num) return '数字';
    if (v is List) return '列表';
    if (v is Map) return 'map';
    return '文本';
  }

  @override
  void initState() {
    super.initState();
    _refreshScheduler = RefreshScheduler(
      onTick: () => _refresh(silent: true),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
      _configureRefresh();
    });
  }

  @override
  void dispose() {
    _keyFilterCtrl.dispose();
    _capQueryCtrl.dispose();
    _scroll.dispose();
    _refreshScheduler.dispose();
    super.dispose();
  }

  void _configureRefresh() {
    final seconds = context.read<AppSettingsController>().dashboardRefreshSec;
    _refreshScheduler.configure(
      enabled: _autoRefresh,
      interval: Duration(seconds: seconds),
    );
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
        if (_sortByKey) {
          final c = a.key.toLowerCase().compareTo(b.key.toLowerCase());
          if (c != 0) return _sortAsc ? c : -c;
        } else if (_sortByType) {
          final c = _valueTypeLabel(
            a.value,
          ).compareTo(_valueTypeLabel(b.value));
          if (c != 0) return _sortAsc ? c : -c;
        } else if (_sortByValue) {
          final c = '${a.value}'.toLowerCase().compareTo(
                '${b.value}'.toLowerCase(),
              );
          if (c != 0) return _sortAsc ? c : -c;
        }
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
      const SnackBar(
        content: Text(AppStrings.copiedStatusCsv),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _copyCapabilities() async {
    final caps = (_status['capabilities'] as List? ?? const [])
        .map((e) => '$e')
        .toList();
    final text = caps.isEmpty ? '（无能力列表）' : caps.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 ${caps.length} 项能力'),
        duration: const Duration(seconds: 1),
      ),
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
      if (_status['hermes'] is Map)
        'hermes: adapter=${(_status['hermes'] as Map)['adapter'] ?? '—'} process=${(_status['hermes'] as Map)['process']}',
      if (caps.isNotEmpty) 'capabilities: $caps',
      if (_error != null) 'error: $_error',
      if (_lastOk != null) 'last_ok: ${_lastOk!.toIso8601String()}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('状态已复制（无令牌）'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  String _fmtStatusValue(dynamic v) {
    final s = '$v';
    if (!_relativeTs) return s;
    DateTime? dt;
    if (v is int) {
      final ms = v > 1e12 ? v : v * 1000;
      dt = DateTime.fromMillisecondsSinceEpoch(ms.round()).toLocal();
    } else if (v is num) {
      final n = v.toDouble();
      final ms = n > 1e12 ? n.round() : (n * 1000).round();
      dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    } else {
      dt = DateTime.tryParse(s)?.toLocal();
    }
    if (dt == null) return s;
    final d = DateTime.now().difference(dt);
    if (d.isNegative) return s;
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 48) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionController>();
    final selectedProject = context.watch<SessionController>().selectedProject;
    final cfg = conn.saved;
    final cs = Theme.of(context).colorScheme;
    final refreshSec =
        context.watch<AppSettingsController>().dashboardRefreshSec;
    // Re-arm timer when setting changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final armed = _refreshScheduler.active;
      final want = refreshSec > 0 && _autoRefresh;
      if (armed != want || (want && !_refreshScheduler.active)) {
        _configureRefresh();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _autoRefresh && refreshSec > 0 ? '主机状态 · 自动 ${refreshSec}s' : '主机状态',
        ),
        actions: compactAppBarActions([
          IconButton(
            tooltip: _autoRefresh ? '暂停刷新' : '自动刷新',
            onPressed: () {
              setState(() => _autoRefresh = !_autoRefresh);
              _configureRefresh();
            },
            icon: Icon(
              _autoRefresh
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
            ),
          ),
          IconButton(
            tooltip: AppStrings.refresh,
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: AppStrings.more,
            onSelected: (v) {
              switch (v) {
                case 'copy_status':
                  if (_status.isEmpty && _error == null) return;
                  _copyStatus();
                  return;
                case 'copy_caps':
                  if (_status.isEmpty) return;
                  _copyCapabilities();
                  return;
                case 'copy_csv':
                  if (_status.isEmpty && _error == null) return;
                  _copyCsv();
                  return;
                case 'wrap':
                  setState(() => _wrapLines = !_wrapLines);
                  return;
                case 'relative':
                  setState(() => _relativeTs = !_relativeTs);
                  return;
                case 'sort_cycle':
                  setState(() {
                    if (!_sortByValue &&
                        !_sortByType &&
                        !_sortByKey &&
                        _sortAsc) {
                      _sortAsc = false;
                    } else if (!_sortByValue &&
                        !_sortByType &&
                        !_sortByKey &&
                        !_sortAsc) {
                      _sortByValue = true;
                      _sortByType = false;
                      _sortByKey = false;
                      _sortAsc = true;
                    } else if (_sortByValue && _sortAsc) {
                      _sortAsc = false;
                    } else if (_sortByValue && !_sortAsc) {
                      _sortByValue = false;
                      _sortByType = true;
                      _sortByKey = false;
                      _sortAsc = true;
                    } else if (_sortByType && _sortAsc) {
                      _sortAsc = false;
                    } else if (_sortByType && !_sortAsc) {
                      _sortByValue = false;
                      _sortByType = false;
                      _sortByKey = true;
                      _sortAsc = true;
                    } else if (_sortByKey && _sortAsc) {
                      _sortAsc = false;
                    } else {
                      _sortByValue = false;
                      _sortByType = false;
                      _sortByKey = false;
                      _sortAsc = true;
                    }
                  });
                  return;
                case 'top':
                  if (!_scroll.hasClients) return;
                  _scroll.animateTo(
                    0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                  return;
                case 'bottom':
                  if (!_scroll.hasClients) return;
                  _scroll.animateTo(
                    _scroll.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                  return;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'copy_status',
                enabled: !(_status.isEmpty && _error == null),
                child: Text(AppStrings.copyStatus),
              ),
              PopupMenuItem(
                value: 'copy_caps',
                enabled: _status.isNotEmpty,
                child: Text(AppStrings.copyCapabilities),
              ),
              PopupMenuItem(
                value: 'copy_csv',
                enabled: !(_status.isEmpty && _error == null),
                child: const Text('复制 CSV'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'wrap',
                child: Text(_wrapLines ? '截断详情' : '换行详情'),
              ),
              PopupMenuItem(
                value: 'relative',
                child: Text(_relativeTs ? '绝对时间戳' : '相对时间戳'),
              ),
              const PopupMenuItem(
                value: 'sort_cycle',
                child: Text('切换排序'),
              ),
              const PopupMenuItem(
                value: 'top',
                child: Text('回到顶部'),
              ),
              const PopupMenuItem(
                value: 'bottom',
                child: Text('跳到底部'),
              ),
            ],
          ),
        ]),
      ),
      body: cfg == null
          ? const Center(child: Text('未连接'))
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
                      '管理 ${cfg.mgmtBaseUrl}\n桥接 ${cfg.bridgeWsUrlRedacted}',
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
                                '最近成功 ${_lastOk!.toLocal().toIso8601String().substring(11, 19)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: Icon(
                              refreshSec > 0
                                  ? Icons.autorenew
                                  : Icons.pause_circle_outline,
                              size: 16,
                            ),
                            label: Text(
                              refreshSec > 0
                                  ? '每 ${refreshSec}s 自动刷新'
                                  : '自动刷新已关',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Live health strip: green when last /status ok, red on error
                  Builder(
                    builder: (context) {
                      final connOk = conn.isReady;
                      final degraded = conn.healthDegraded;
                      final healthy =
                          _error == null && _status.isNotEmpty && !degraded;
                      final Color barColor;
                      final String label;
                      if (_loading && _status.isEmpty) {
                        barColor = Colors.amber;
                        label = '正在探测主机状态…';
                      } else if (!connOk && _error != null) {
                        barColor = cs.error;
                        label = '主机不可达';
                      } else if (_error != null) {
                        barColor = cs.error;
                        label = '状态错误';
                      } else if (degraded) {
                        barColor = Colors.orange;
                        label = '健康降级（心跳）';
                      } else if (healthy) {
                        barColor = Colors.green;
                        label = '主机健康';
                      } else {
                        barColor = Colors.orange;
                        label = '等待状态';
                      }
                      final age = _lastOk == null
                          ? 'never'
                          : _lastOk!.toLocal().toIso8601String().substring(
                                11,
                                19,
                              );
                      return Card(
                        color: barColor.withValues(alpha: 0.12),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            healthy
                                ? Icons.favorite
                                : (_error != null
                                    ? Icons.heart_broken
                                    : Icons.monitor_heart_outlined),
                            color: barColor,
                          ),
                          title: Text(
                            label,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: barColor,
                            ),
                          ),
                          subtitle: Text(
                            '上次成功：$age · 自动 ${refreshSec == 0 ? "关" : "${refreshSec}s"}'
                            '${_error != null ? "\n$_error" : ""}',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          trailing: TextButton(
                            onPressed: _loading ? null : () => _refresh(),
                            child: const Text('检查'),
                          ),
                        ),
                      );
                    },
                  ),
                  if (_loading) const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatChip(
                        label: '版本',
                        value: '${_status['version'] ?? '—'}',
                      ),
                      _StatChip(
                        label: '运行',
                        value: _fmtUptime(_status['uptime_seconds']),
                      ),
                      _StatChip(
                        label: '项目',
                        value: '${_status['projects_count'] ?? '—'}',
                      ),
                      _StatChip(
                        label: '会话',
                        value: '${_status['sessions_count'] ?? '—'}',
                      ),
                      _StatChip(
                        label: '运行中',
                        value: '${_status['active_runs'] ?? '—'}',
                      ),
                      if (_status['hermes'] is Map)
                        _StatChip(
                          label: 'Hermes',
                          value:
                              '${((_status['hermes'] as Map)['adapter'] ?? '—')}'
                              '${((_status['hermes'] as Map)['process'] == true) ? ' · 在线' : ' · 模拟'}',
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    (() {
                      final caps =
                          (_status['capabilities'] as List? ?? const []);
                      if (caps.isEmpty) return '能力';
                      if (_capFilter.isEmpty) return '能力 (${caps.length})';
                      return '能力 · $_capFilter';
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
                        prefixIcon: IconButton(
                          tooltip: _queryRegex
                              ? (_queryCase
                                  ? '正则 · 大小写 开（长按恢复普通筛选）'
                                  : '正则 · 大小写 关（长按恢复普通筛选）')
                              : (_queryCase
                                  ? '区分大小写（长按切换正则）'
                                  : '不区分大小写（长按切换正则）'),
                          icon: Icon(
                            _queryRegex
                                ? Icons.code
                                : (_queryCase
                                    ? Icons.text_fields
                                    : Icons.search),
                            size: 18,
                          ),
                          onPressed: () =>
                              setState(() => _queryCase = !_queryCase),
                          onLongPress: () =>
                              setState(() => _queryRegex = !_queryRegex),
                        ),
                        hintText: _queryRegex
                            ? (_queryCase ? '筛选（正则 · 区分大小写）' : '筛选（正则）')
                            : (_queryCase ? '筛选（区分大小写）' : '筛选能力项'),
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
                        label: const Text(
                          AppStrings.wrap,
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: _wrapLines,
                        onSelected: (v) => setState(() => _wrapLines = v),
                      ),
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text(
                          AppStrings.regex,
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: _queryRegex,
                        onSelected: (v) => setState(() => _queryRegex = v),
                      ),
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text(
                          AppStrings.matchCase,
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: _queryCase,
                        onSelected: (v) => setState(() => _queryCase = v),
                      ),
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text(
                          'All',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: _capFilter.isEmpty,
                        onSelected: (_) => setState(() => _capFilter = ''),
                      ),
                      for (final c
                          in (_status['capabilities'] as List? ?? const []))
                        if (() {
                          final rawCq = _capQuery.trim();
                          if (rawCq.isEmpty) return true;
                          final hayRaw = '$c';
                          if (_queryRegex) {
                            try {
                              return RegExp(
                                rawCq,
                                caseSensitive: _queryCase,
                              ).hasMatch(hayRaw);
                            } catch (_) {
                              return false;
                            }
                          }
                          final cq = _queryCase ? rawCq : rawCq.toLowerCase();
                          final hay =
                              _queryCase ? hayRaw : hayRaw.toLowerCase();
                          return hay.contains(cq);
                        }())
                          FilterChip(
                            visualDensity: VisualDensity.compact,
                            avatar: Icon(_capIcon('$c'), size: 14),
                            label: Text(
                              '$c',
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: _capFilter == '$c',
                            onSelected: (_) => setState(() {
                              _capFilter = _capFilter == '$c' ? '' : '$c';
                            }),
                          ),
                      if ((_status['capabilities'] as List? ?? const [])
                          .isEmpty)
                        const Text('—', style: TextStyle(fontSize: 12)),
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text(
                          AppStrings.autoRefresh,
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: _autoRefresh,
                        onSelected: (value) {
                          setState(() => _autoRefresh = value);
                          _configureRefresh();
                        },
                      ),
                    ],
                  ),
                  if (_capFilter.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '已选能力：$_capFilter（筛选仅视觉高亮）',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const Divider(height: 32),
                  Text(
                    '快捷入口',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: const Text('工作区（只读）'),
                    subtitle: const Text('浏览主机文件 + mock git 状态'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WorkspaceScreen(config: cfg),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.difference_outlined),
                    title: const Text('Git 对比（只读）'),
                    subtitle: const Text('来自主机的统一 Diff'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DiffScreen(config: cfg),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.psychology_outlined),
                    title: const Text('主机记忆'),
                    subtitle: const Text('来自主机的只读目录'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MemoryScreen(
                          config: cfg,
                          project: selectedProject,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('主机定时任务'),
                    subtitle: const Text('只读定时任务'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CronScreen(config: cfg),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text('技能'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SkillsScreen(config: cfg),
                      ),
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
                    title: const Text('主机活动'),
                    subtitle: const Text('只读事件流'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ActivityScreen(config: cfg),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.smart_toy_outlined),
                    title: const Text('代理'),
                    subtitle: const Text('主机 Agent 目录'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AgentsScreen(config: cfg),
                      ),
                    ),
                  ),

                  ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: const Text('配对 URI'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PairingScreen(config: cfg),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.article_outlined),
                    title: const Text('主机日志'),
                    subtitle: const Text('只读日志流'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LogsScreen(config: cfg),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  ExpansionTile(
                    title: const Text('原始 /status'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          controller: _keyFilterCtrl,
                          decoration: InputDecoration(
                            isDense: true,
                            prefixIcon: IconButton(
                              tooltip: _queryRegex
                                  ? (_queryCase
                                      ? '正则 · 大小写 开（长按恢复普通筛选）'
                                      : '正则 · 大小写 关（长按恢复普通筛选）')
                                  : (_queryCase
                                      ? '区分大小写（长按切换正则）'
                                      : '不区分大小写（长按切换正则）'),
                              icon: Icon(
                                _queryRegex
                                    ? Icons.code
                                    : (_queryCase
                                        ? Icons.text_fields
                                        : Icons.search),
                                size: 18,
                              ),
                              onPressed: () =>
                                  setState(() => _queryCase = !_queryCase),
                              onLongPress: () =>
                                  setState(() => _queryRegex = !_queryRegex),
                            ),
                            hintText: _queryRegex
                                ? (_queryCase ? '筛选（正则 · 区分大小写）' : '筛选（正则）')
                                : (_queryCase ? '筛选（区分大小写）' : '筛选键 / 值'),
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            FilterChip(
                              visualDensity: VisualDensity.compact,
                              label: const Text(
                                AppStrings.wrap,
                                style: TextStyle(fontSize: 11),
                              ),
                              selected: _wrapLines,
                              onSelected: (v) => setState(() => _wrapLines = v),
                            ),
                            FilterChip(
                              visualDensity: VisualDensity.compact,
                              label: const Text(
                                AppStrings.regex,
                                style: TextStyle(fontSize: 11),
                              ),
                              selected: _queryRegex,
                              onSelected: (v) =>
                                  setState(() => _queryRegex = v),
                            ),
                            FilterChip(
                              visualDensity: VisualDensity.compact,
                              label: const Text(
                                AppStrings.matchCase,
                                style: TextStyle(fontSize: 11),
                              ),
                              selected: _queryCase,
                              onSelected: (v) => setState(() => _queryCase = v),
                            ),
                            for (final t in const [
                              '',
                              'string',
                              'number',
                              'bool',
                              'list',
                              'map',
                              'null',
                            ])
                              FilterChip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  t.isEmpty ? '任意类型' : t,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                selected: _typeFilter == t,
                                onSelected: (_) =>
                                    setState(() => _typeFilter = t),
                              ),
                          ],
                        ),
                      ),
                      for (final e in (() {
                        final rawQ = _keyQuery.trim();
                        final q = _queryCase ? rawQ : rawQ.toLowerCase();
                        var entries = _status.entries.toList();
                        if (_typeFilter.isNotEmpty) {
                          entries = entries
                              .where(
                                (e) => _valueTypeLabel(e.value) == _typeFilter,
                              )
                              .toList();
                        }
                        if (rawQ.isNotEmpty) {
                          entries = entries.where((e) {
                            final hayRaw = '${e.key} ${e.value}';
                            if (_queryRegex) {
                              try {
                                return RegExp(
                                  rawQ,
                                  caseSensitive: _queryCase,
                                ).hasMatch(hayRaw);
                              } catch (_) {
                                return false;
                              }
                            }
                            final k = _queryCase ? e.key : e.key.toLowerCase();
                            final v = _queryCase
                                ? '${e.value}'
                                : '${e.value}'.toLowerCase();
                            return k.contains(q) || v.contains(q);
                          }).toList();
                        }
                        entries.sort((a, b) {
                          if (_sortByType) {
                            final c = _valueTypeLabel(
                              a.value,
                            ).compareTo(_valueTypeLabel(b.value));
                            if (c != 0) return _sortAsc ? c : -c;
                          } else if (_sortByValue) {
                            final c = '${a.value}'.toLowerCase().compareTo(
                                  '${b.value}'.toLowerCase(),
                                );
                            if (c != 0) return _sortAsc ? c : -c;
                          }
                          final c = a.key.toLowerCase().compareTo(
                                b.key.toLowerCase(),
                              );
                          return _sortAsc ? c : -c;
                        });
                        return entries;
                      })())
                        ListTile(
                          dense: true,
                          title: Text(e.key),
                          subtitle: Text(
                            Security.redactText(_fmtStatusValue(e.value)),
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
  if (k.contains('diff') || k.contains('git') || k.contains('workspace'))
    return Icons.folder_open;
  if (k.contains('activity')) return Icons.bolt_outlined;
  if (k.contains('log')) return Icons.article_outlined;
  if (k.contains('pair')) return Icons.qr_code_2;
  if (k.contains('agent')) return Icons.smart_toy_outlined;
  if (k.contains('stream')) return Icons.waterfall_chart;
  if (k.contains('hermes')) return Icons.hub_outlined;
  return Icons.check_circle_outline;
}
