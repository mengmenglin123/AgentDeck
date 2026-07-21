import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_controller.dart';
import '../services/connection_controller.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';
import '../utils/catalog_ui.dart';
import '../utils/query_match.dart';
import 'host_dashboard_screen.dart';
import 'sessions_screen.dart';
import '../l10n/app_strings.dart';

/// Post-connect Host snapshot + quick actions.
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic> _status = const {};
  Timer? _timer;
  bool _wrapLines = false;
  bool _sortAsc = true;
  bool _sortByValue = false;
  bool _sortByType = false;
  bool _sortByKey = false;
  bool _queryCase = false;
  bool _queryRegex = false;
  bool _relativeTs = false;
  String _keyQuery = '';
  String _capQuery = '';
  String _typeFilter = ''; // empty=all
  final _capFilterCtrl = TextEditingController();
  final _keyFilterCtrl = TextEditingController();
  bool _autoRefresh = true;
  final _scroll = ScrollController();

  String _valueTypeLabel(dynamic v) {
    if (v == null) return 'null';
    if (v is bool) return 'bool';
    if (v is num) return 'number';
    if (v is List) return 'list';
    if (v is Map) return 'map';
    return 'string';
  }

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
    _capFilterCtrl.dispose();
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _armTimer() {
    _timer = CatalogUi.armAutoRefresh(
      context: context,
      current: _timer,
      enabled: _autoRefresh,
      isBusy: () => _loading,
      onTick: _refresh,
    );
  }

  Future<void> _refresh() async {
    final c = context.read<ConnectionController>();
    final cfg = c.saved;
    if (cfg == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final st = await MgmtClient(config: cfg).status();
      if (!mounted) return;
      setState(() {
        _status = st;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Security.redactText(e.toString());
        // fall back to last cached status
        _status = c.lastStatus ?? _status;
      });
    }
  }

  String _fmtUptime(dynamic v) {
    if (v is! num) return '—';
    final s = v.round();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s % 60}s';
  }

  Future<void> _copySummary(ConnectionController c) async {
    final cfg = c.saved;
    if (cfg == null) return;
    final caps = (_status['capabilities'] as List?)?.join(', ') ?? '';
    final text = [
      'host: ${cfg.host}',
      'mgmt: ${cfg.mgmtBaseUrl}',
      'bridge: ${cfg.bridgeWsUrlRedacted}',
      'version: ${_status['version'] ?? '—'}',
      if (_status['hermes'] is Map)
        'hermes: ${(_status['hermes'] as Map)['adapter'] ?? '—'}'
            ' process=${(_status['hermes'] as Map)['process']}'
            ' ${(_status['hermes'] as Map)['note'] ?? ''}',
      'uptime: ${_fmtUptime(_status['uptime_seconds'])}',
      'projects: ${_status['projects_count'] ?? '—'}',
      'sessions: ${_status['sessions_count'] ?? '—'}',
      'active_runs: ${_status['active_runs'] ?? '—'}',
      if (c.lastTestLatencyMs != null)
        'last_test_latency_ms: ${c.lastTestLatencyMs}',
      if (caps.isNotEmpty) 'capabilities: $caps',
      if (_status['bridge_adapters'] is List)
        'bridge_adapters: ${(_status['bridge_adapters'] as List).map((e) => e is Map ? (e['platform'] ?? e).toString() : '$e').join('|')}',
      if (_error != null) 'status_error: $_error',
      if (c.lastHealthOkAt != null)
        'last_health_ok: ${c.lastHealthOkAt!.toIso8601String()}',
      if (c.lastHealthError != null) 'last_health_error: ${c.lastHealthError}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制状态摘要（不含令牌）'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _copyCsv(ConnectionController c) async {
    final cfg = c.saved;
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
    if (c.lastTestLatencyMs != null)
      row('last_test_latency_ms', c.lastTestLatencyMs);
    if (c.lastHealthOkAt != null)
      row('last_health_ok', c.lastHealthOkAt!.toIso8601String());
    for (final e in _status.entries) {
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
        content: Text('已复制状态 CSV'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _copyJson(ConnectionController c) async {
    final cfg = c.saved;
    final payload = <String, dynamic>{
      if (cfg != null) 'host': cfg.host,
      if (cfg != null) 'mgmt': cfg.mgmtBaseUrl,
      if (cfg != null) 'bridge': cfg.bridgeWsUrlRedacted,
      if (c.lastTestLatencyMs != null)
        'last_test_latency_ms': c.lastTestLatencyMs,
      if (c.lastHealthOkAt != null)
        'last_health_ok': c.lastHealthOkAt!.toIso8601String(),
      'status': _status,
      if (_error != null) 'error': _error,
    };
    final text = const JsonEncoder.withIndent('  ').convert(payload);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制状态 JSON（令牌已脱敏）'),
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
    final c = context.watch<ConnectionController>();
    final cfg = c.saved;
    if (cfg == null) {
      return const Scaffold(body: Center(child: Text('未连接')));
    }
    final cs = Theme.of(context).colorScheme;
    final status = _status.isNotEmpty ? _status : (c.lastStatus ?? const {});
    final caps = (status['capabilities'] as List?) ?? const [];
    final healthy = _error == null && status.isNotEmpty;
    final barColor = _loading && status.isEmpty
        ? Colors.amber
        : (_error != null
              ? cs.error
              : (c.healthDegraded
                    ? Colors.orange
                    : (healthy ? Colors.green : Colors.orange)));
    final barLabel = _loading && status.isEmpty
        ? '探测中…'
        : (_error != null
              ? '状态错误'
              : (c.healthDegraded
                    ? '健康降级'
                    : (healthy ? '主机健康' : '等待中')));

    return Scaffold(
      appBar: AppBar(
        title: Text(_autoRefresh ? '主机已连接 · 自动' : '主机已连接'),
        actions: [
          IconButton(
            tooltip: '复制摘要',
            onPressed: () => _copySummary(c),
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: '复制 JSON',
            onPressed: () => _copyJson(c),
            icon: const Icon(Icons.data_object_outlined),
          ),
          IconButton(
            tooltip: '复制 CSV',
            onPressed: () => _copyCsv(c),
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: _wrapLines ? '截断详情' : '换行详情',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
          ),
          IconButton(
            tooltip: _relativeTs
                ? '绝对时间戳'
                : '相对时间戳',
            onPressed: () => setState(() => _relativeTs = !_relativeTs),
            icon: Icon(_relativeTs ? Icons.schedule : Icons.access_time),
          ),
          IconButton(
            tooltip: _sortByKey
                ? (_sortAsc ? '键 Z→A' : '键 A→Z')
                : (_sortByType
                      ? (_sortAsc ? '类型 Z→A' : '类型 A→Z')
                      : (_sortByValue
                            ? (_sortAsc ? '值 Z→A' : '值 A→Z')
                            : (_sortAsc ? '键 Z→A' : '键 A→Z'))),
            onPressed: () {
              setState(() {
                if (!_sortByValue && !_sortByType && !_sortByKey && _sortAsc) {
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
            },
            icon: Icon(
              _sortByKey
                  ? Icons.vpn_key_outlined
                  : (_sortByType
                        ? Icons.category_outlined
                        : (_sortByValue
                              ? Icons.text_fields
                              : (_sortAsc ? Icons.sort_by_alpha : Icons.sort))),
            ),
          ),

          IconButton(
            tooltip: '回到顶部',
            onPressed: () {
              if (!_scroll.hasClients) return;
              _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            },
            icon: const Icon(Icons.vertical_align_top),
          ),
          IconButton(
            tooltip: '跳到底部',
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
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: _autoRefresh
                ? '暂停刷新'
                : '恢复自动刷新',
            onPressed: () {
              setState(() => _autoRefresh = !_autoRefresh);
              _armTimer();
            },
            icon: Icon(
              _autoRefresh
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
            ),
          ),
          IconButton(
            tooltip: '断开连接',
            onPressed: () => c.disconnect(),
            icon: const Icon(Icons.link_off),
          ),
          IconButton(
            tooltip: '清除已保存配置',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('清除已保存配置？'),
                  content: const Text(
                    '将从安全存储中移除主机设置与令牌。',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('清除'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await c.disconnect(clearStorage: true);
              }
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              color: barColor.withOpacity(0.12),
              child: ListTile(
                leading: Icon(
                  healthy && !c.healthDegraded
                      ? Icons.favorite
                      : Icons.monitor_heart_outlined,
                  color: barColor,
                ),
                title: Text(
                  barLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: barColor,
                  ),
                ),
                subtitle: Text(
                  _error ?? 'Mgmt ${cfg.mgmtBaseUrl}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                trailing: TextButton(
                  onPressed: _loading ? null : _refresh,
                  child: const Text('检查'),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.dns_outlined),
              title: Text(cfg.host),
              subtitle: Text(
                'Mgmt ${cfg.mgmtBaseUrl}\nBridge ${cfg.bridgeWsUrlRedacted}',
              ),
              isThreeLine: true,
            ),
            Card(
              child: ListTile(
                leading: Icon(
                  c.lastHealthError == null
                      ? Icons.health_and_safety_outlined
                      : Icons.report_gmailerrorred_outlined,
                  color: c.lastHealthError == null ? Colors.green : cs.error,
                ),
                title: const Text('上次健康探测'),
                subtitle: Text(
                  [
                    if (c.lastHealthOkAt != null)
                      'OK at ${c.lastHealthOkAt!.toLocal().toIso8601String()}',
                    if (c.lastHealthError != null)
                      '错误：${c.lastHealthError}',
                    if (c.lastHealthOkAt == null && c.lastHealthError == null)
                      '尚未探测',
                  ].join('\n'),
                ),
                isThreeLine: true,
                trailing: c.lastHealthError == null
                    ? null
                    : IconButton(
                        tooltip: '复制错误',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: c.lastHealthError ?? ''),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('已复制健康错误'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                      ),
              ),
              ListTile(
                leading: Icon(
                  Icons.speed,
                  color: c.lastTestLatencyMs == null ? cs.outline : cs.primary,
                ),
                title: const Text('上次连接测试'),
                subtitle: Text(
                  c.lastTestLatencyMs == null
                      ? '尚无连接延迟数据'
                      : '${c.lastTestLatencyMs} ms（连接时 GET /status）',
                ),
              ),
            ),
            const Divider(),
            Text('快照', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('version ${status['version'] ?? '—'}')),
                if (status['hermes'] is Map)
                  Chip(
                    avatar: const Icon(Icons.psychology_alt_outlined, size: 16),
                    label: Text(
                      'hermes ${((status['hermes'] as Map)['adapter'] ?? '—')}'
                      '${((status['hermes'] as Map)['process'] == true) ? ' · live' : ' · no process'}',
                    ),
                  ),
                Chip(
                  label: Text('uptime ${_fmtUptime(status['uptime_seconds'])}'),
                ),
                Chip(
                  label: Text('projects ${status['projects_count'] ?? '—'}'),
                ),
                Chip(
                  label: Text('sessions ${status['sessions_count'] ?? '—'}'),
                ),
                Chip(label: Text('runs ${status['active_runs'] ?? '—'}')),
              ],
            ),
            if (status['bridge_adapters'] is List &&
                (status['bridge_adapters'] as List).isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Bridge 适配器',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              ...[
                for (final raw in (status['bridge_adapters'] as List))
                  if (raw is Map)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        (raw['status']?.toString() == 'mock')
                            ? Icons.science_outlined
                            : Icons.cable,
                        size: 20,
                      ),
                      title: Text(
                        '${raw['platform'] ?? '—'}'
                        '${raw['project'] != null ? ' · ${raw['project']}' : ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        [
                          if (raw['status'] != null) 'status=${raw['status']}',
                          if (raw['capabilities'] is List)
                            (raw['capabilities'] as List).join(', '),
                        ].where((s) => s.toString().isNotEmpty).join(' · '),
                        style: const TextStyle(fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('$raw', style: const TextStyle(fontSize: 13)),
                    ),
              ],
            ],
            if (caps.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '能力',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _capFilterCtrl,
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
                          : (_queryCase ? Icons.text_fields : Icons.search),
                      size: 18,
                    ),
                    onPressed: () => setState(() => _queryCase = !_queryCase),
                    onLongPress: () =>
                        setState(() => _queryRegex = !_queryRegex),
                  ),
                  hintText: _queryRegex
                      ? (_queryCase
                            ? '筛选（正则 · 大小写）'
                            : '筛选（正则）')
                      : (_queryCase
                            ? '筛选（区分大小写）'
                            : '筛选能力'),
                  border: const OutlineInputBorder(),
                  suffixIcon: _capQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _capFilterCtrl.clear();
                            setState(() => _capQuery = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _capQuery = v),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final cap in caps)
                    if (() {
                      final rawCq = _capQuery.trim();
                      if (rawCq.isEmpty) return true;
                      final hayRaw = '$cap';
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
                      final hay = _queryCase ? hayRaw : hayRaw.toLowerCase();
                      return hay.contains(cq);
                    }())
                      Chip(
                        label: Text(
                          '$cap',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
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
                        : (_queryCase ? Icons.text_fields : Icons.search),
                    size: 18,
                  ),
                  onPressed: () => setState(() => _queryCase = !_queryCase),
                  onLongPress: () => setState(() => _queryRegex = !_queryRegex),
                ),
                hintText: _queryRegex
                    ? (_queryCase ? '筛选（正则 · 大小写）' : '筛选（正则）')
                    : (_queryCase
                          ? '筛选（区分大小写）'
                          : '筛选键 / 值'),
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('换行', style: TextStyle(fontSize: 11)),
                  selected: _wrapLines,
                  onSelected: (v) => setState(() => _wrapLines = v),
                ),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text(AppStrings.regex, style: TextStyle(fontSize: 11)),
                  selected: _queryRegex,
                  onSelected: (v) => setState(() => _queryRegex = v),
                ),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text(AppStrings.matchCase, style: TextStyle(fontSize: 11)),
                  selected: _queryCase,
                  onSelected: (v) => setState(() => _queryCase = v),
                ),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('自动', style: TextStyle(fontSize: 11)),
                  selected: _autoRefresh,
                  onSelected: (v) {
                    setState(() => _autoRefresh = v);
                    _armTimer();
                  },
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
                    onSelected: (_) => setState(() => _typeFilter = t),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '原始 /status 键',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (status.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('尚无状态载荷。'),
              )
            else
              ...(() {
                final rawQ = _keyQuery.trim();
                final q = _queryCase ? rawQ : rawQ.toLowerCase();
                var entries = status.entries.toList();
                if (_typeFilter.isNotEmpty) {
                  entries = entries
                      .where((e) => _valueTypeLabel(e.value) == _typeFilter)
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
                  if (_sortByKey) {
                    final c = a.key.toLowerCase().compareTo(
                      b.key.toLowerCase(),
                    );
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
                });
                return entries;
              })().map(
                (e) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.key),
                  subtitle: Text(
                    _fmtStatusValue(e.value),
                    maxLines: _wrapLines ? 12 : 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SessionsScreen()),
                );
              },
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('打开会话'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const HostDashboardScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.dashboard_outlined),
              label: const Text('主机仪表盘'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => c.disconnect(),
              icon: const Icon(Icons.edit),
              label: const Text('编辑连接'),
            ),
          ],
        ),
      ),
    );
  }
}
