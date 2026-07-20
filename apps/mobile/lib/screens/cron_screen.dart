import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/app_settings_controller.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';
import '../utils/catalog_ui.dart';
import '../utils/query_match.dart';

/// Readonly Host scheduled jobs (`GET /cron`). Console view only.
class CronScreen extends StatefulWidget {
  const CronScreen({super.key, required this.config});

  final ConnectionConfig config;

  @override
  State<CronScreen> createState() => _CronScreenState();
}

class _CronScreenState extends State<CronScreen> {
  late final MgmtClient _mgmt = MgmtClient(config: widget.config);
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _jobs = [];
  final _q = TextEditingController();
  String _query = '';
  bool _queryCase = false;
  bool _queryRegex = false;

  /// all | on | off
  String _enabled = 'all';
  String _kind = 'all';
  String _lastStatus = 'all';
  bool _wrapLines = false;
  bool _sortBySchedule = false;
  bool _sortByKind = false;
  bool _sortByLastStatus = false;
  bool _sortByNext = false;
  bool _sortById = false;
  bool _sortByEnabled = false;
  bool _sortByName = false;
  bool _sortByDesc = false;
  bool _sortByLastRun = false;
  bool _sortAsc = true;
  final _scroll = ScrollController();
  Timer? _timer;
  bool _autoRefresh = false;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _armTimer());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _mgmt.listCron();
      final raw = data['jobs'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      setState(() {
        _jobs = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = Security.redactText(e.toString());
      });
    }
  }

  String _fmtTs(dynamic v) {
    if (v is num) {
      final dt = DateTime.fromMillisecondsSinceEpoch((v * 1000).round());
      return dt
          .toLocal()
          .toIso8601String()
          .replaceFirst('T', ' ')
          .substring(0, 19);
    }
    return v?.toString() ?? '—';
  }

  List<Map<String, dynamic>> get _filtered {
    Iterable<Map<String, dynamic>> it = _jobs;
    if (_enabled == 'on') {
      it = it.where((j) => j['enabled'] == true);
    } else if (_enabled == 'off') {
      it = it.where((j) => j['enabled'] != true);
    }
    if (_kind != 'all' && _kind.isNotEmpty) {
      it = it.where((j) {
        final k = (j['kind'] ?? '').toString().toLowerCase();
        if (_kind == 'other') {
          return k.isNotEmpty &&
              k != 'prompt' &&
              k != 'http' &&
              k != 'bash' &&
              k != 'script';
        }
        return k.contains(_kind);
      });
    }
    if (_lastStatus != 'all' && _lastStatus.isNotEmpty) {
      it = it.where((j) {
        final s = (j['last_status'] ?? '').toString().toLowerCase();
        if (_lastStatus == 'other') {
          return s.isNotEmpty &&
              s != 'ok' &&
              s != 'success' &&
              s != 'error' &&
              s != 'fail' &&
              s != 'failed' &&
              s != 'running';
        }
        return s.contains(_lastStatus);
      });
    }
    final rawQ = _query.trim();
    if (rawQ.isNotEmpty) {
      it = it.where((j) {
        final hayRaw =
            '${j['name']} ${j['id']} ${j['kind']} ${j['schedule']} ${j['description']} ${j['last_status']} ${j['project']} ${j['tags']}';
        return QueryMatch.matches(
          hayRaw,
          rawQ,
          caseSensitive: _queryCase,
          regex: _queryRegex,
        );
      });
    }
    final list = it.toList();
    list.sort((a, b) {
      int nextOf(Map x) {
        final v = x['next_run_at'] ?? x['next_run'] ?? x['next'];
        if (v is num) {
          final n = v.toDouble();
          return n > 1e12 ? n.round() : (n * 1000).round();
        }
        final p = DateTime.tryParse(v?.toString() ?? '');
        return p?.millisecondsSinceEpoch ?? 0;
      }

      if (_sortByLastRun) {
        int lastOf(Map x) {
          final v = x['last_run'];
          if (v is num) {
            final n = v.toDouble();
            return n > 1e12 ? n.round() : (n * 1000).round();
          }
          final p = DateTime.tryParse(v?.toString() ?? '');
          return p?.millisecondsSinceEpoch ?? 0;
        }

        final c = lastOf(a).compareTo(lastOf(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByDesc) {
        final da = (a['description'] ?? a['summary'] ?? a['note'] ?? '')
            .toString()
            .toLowerCase();
        final db = (b['description'] ?? b['summary'] ?? b['note'] ?? '')
            .toString()
            .toLowerCase();
        final c = da.compareTo(db);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByName) {
        final na = (a['name'] ?? a['id'] ?? '').toString().toLowerCase();
        final nb = (b['name'] ?? b['id'] ?? '').toString().toLowerCase();
        final c = na.compareTo(nb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByEnabled) {
        int enOf(Map x) {
          final v = x['enabled'] ?? x['active'] ?? x['paused'];
          if (v is bool) {
            // paused inverted
            if (x.containsKey('paused') &&
                !x.containsKey('enabled') &&
                !x.containsKey('active')) {
              return v ? 0 : 1;
            }
            return v ? 1 : 0;
          }
          final s = (v ?? '').toString().toLowerCase();
          if (s == 'true' ||
              s == '1' ||
              s == 'yes' ||
              s == 'enabled' ||
              s == 'active')
            return 1;
          if (s == 'false' ||
              s == '0' ||
              s == 'no' ||
              s == 'disabled' ||
              s == 'paused')
            return 0;
          return -1;
        }

        final c = enOf(a).compareTo(enOf(b));
        if (c != 0) return _sortAsc ? -c : c; // asc => enabled first
      } else if (_sortById) {
        final ia = (a['id'] ?? a['job_id'] ?? a['name'] ?? '')
            .toString()
            .toLowerCase();
        final ib = (b['id'] ?? b['job_id'] ?? b['name'] ?? '')
            .toString()
            .toLowerCase();
        final c = ia.compareTo(ib);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByNext) {
        final c = nextOf(a).compareTo(nextOf(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByLastStatus) {
        final sa = (a['last_status'] ?? a['status'] ?? '')
            .toString()
            .toLowerCase();
        final sb = (b['last_status'] ?? b['status'] ?? '')
            .toString()
            .toLowerCase();
        final c = sa.compareTo(sb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByKind) {
        final ka = (a['kind'] ?? '').toString().toLowerCase();
        final kb = (b['kind'] ?? '').toString().toLowerCase();
        final c = ka.compareTo(kb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortBySchedule) {
        final sa = (a['schedule'] ?? '').toString().toLowerCase();
        final sb = (b['schedule'] ?? '').toString().toLowerCase();
        final c = sa.compareTo(sb);
        if (c != 0) return _sortAsc ? c : -c;
      }
      final na = (a['name'] ?? a['id'] ?? '').toString().toLowerCase();
      final nb = (b['name'] ?? b['id'] ?? '').toString().toLowerCase();
      final c = na.compareTo(nb);
      return _sortAsc ? c : -c;
    });
    return list;
  }

  void _armTimer() {
    _timer = CatalogUi.armAutoRefresh(
      context: context,
      current: _timer,
      enabled: _autoRefresh,
      isBusy: () => _loading,
      onTick: _load,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          items.isEmpty
              ? '主机定时任务'
              : (items.length == _jobs.length
                    ? 'Host schedules (${items.length})'
                    : 'Host schedules (${items.length}/${_jobs.length})'),
        ),
        actions: [
          IconButton(
            tooltip: '复制全部',
            onPressed: items.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    for (final j in items) {
                      buf.writeln('## ${j['name'] ?? j['id'] ?? 'job'}');
                      buf.writeln('id: ${j['id']}');
                      buf.writeln('enabled: ${j['enabled']}');
                      buf.writeln('schedule: ${j['schedule']}');
                      buf.writeln('kind: ${j['kind']}');
                      buf.writeln('last_status: ${j['last_status']}');
                      buf.writeln('last_run: ${_fmtTs(j['last_run'])}');
                      final desc = (j['description'] ?? '').toString();
                      if (desc.isNotEmpty) buf.writeln(desc);
                      buf.writeln();
                    }
                    await Clipboard.setData(
                      ClipboardData(text: buf.toString()),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已复制 ${items.length} jobs'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: '复制 CSV',
            onPressed: items.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    buf.writeln(
                      'id,name,enabled,schedule,kind,last_status,last_run',
                    );
                    for (final j in items) {
                      final id = '${j['id'] ?? ''}'.replaceAll(',', ';');
                      final name = '${j['name'] ?? ''}'.replaceAll(',', ';');
                      final en = '${j['enabled'] ?? ''}';
                      final schedule = '${j['schedule'] ?? ''}'.replaceAll(
                        ',',
                        ';',
                      );
                      final kind = '${j['kind'] ?? ''}'.replaceAll(',', ';');
                      final status = '${j['last_status'] ?? ''}'.replaceAll(
                        ',',
                        ';',
                      );
                      final last = _fmtTs(j['last_run']).replaceAll(',', ';');
                      buf.writeln(
                        '$id,$name,$en,$schedule,$kind,$status,$last',
                      );
                    }
                    await Clipboard.setData(
                      ClipboardData(text: buf.toString()),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已复制 CSV（${items.length}）'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: _sortByLastRun
                ? (_sortAsc ? 'Last run old→new' : 'Last run new→old')
                : (_sortByDesc
                      ? (_sortAsc ? '描述 Z→A' : '描述 A→Z')
                      : (_sortByName
                            ? (_sortAsc ? '名称 Z→A' : '名称 A→Z')
                            : (_sortByEnabled
                                  ? (_sortAsc
                                        ? '启用优先'
                                        : '禁用优先')
                                  : (_sortById
                                        ? (_sortAsc ? 'ID Z→A' : 'ID A→Z')
                                        : (_sortByNext
                                              ? (_sortAsc
                                                    ? 'Next run late→soon'
                                                    : 'Next run soon→late')
                                              : (_sortByLastStatus
                                                    ? (_sortAsc
                                                          ? '上次状态 Z→A'
                                                          : '上次状态 A→Z')
                                                    : (_sortByKind
                                                          ? (_sortAsc
                                                                ? 'Kind Z→A'
                                                                : 'Kind A→Z')
                                                          : (_sortBySchedule
                                                                ? (_sortAsc
                                                                      ? '计划 Z→A'
                                                                      : '计划 A→Z')
                                                                : (_sortAsc
                                                                      ? '名称 Z→A'
                                                                      : '名称 A→Z'))))))))),
            onPressed: () {
              setState(() {
                if (!_sortBySchedule &&
                    !_sortByKind &&
                    !_sortByLastStatus &&
                    !_sortByNext &&
                    !_sortById &&
                    !_sortByEnabled &&
                    !_sortByName &&
                    !_sortByDesc &&
                    !_sortByLastRun &&
                    _sortAsc) {
                  _sortAsc = false;
                } else if (!_sortBySchedule &&
                    !_sortByKind &&
                    !_sortByLastStatus &&
                    !_sortByNext &&
                    !_sortById &&
                    !_sortByEnabled &&
                    !_sortByName &&
                    !_sortByDesc &&
                    !_sortByLastRun &&
                    !_sortAsc) {
                  _sortBySchedule = true;
                  _sortByKind = false;
                  _sortByLastStatus = false;
                  _sortByNext = false;
                  _sortById = false;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortByDesc = false;
                  _sortByLastRun = false;
                  _sortAsc = true;
                } else if (_sortBySchedule && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortBySchedule && !_sortAsc) {
                  _sortBySchedule = false;
                  _sortByKind = true;
                  _sortByLastStatus = false;
                  _sortByNext = false;
                  _sortById = false;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortByDesc = false;
                  _sortByLastRun = false;
                  _sortAsc = true;
                } else if (_sortByKind && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByKind && !_sortAsc) {
                  _sortBySchedule = false;
                  _sortByKind = false;
                  _sortByLastStatus = true;
                  _sortByNext = false;
                  _sortById = false;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortByDesc = false;
                  _sortByLastRun = false;
                  _sortAsc = true;
                } else if (_sortByLastStatus && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByLastStatus && !_sortAsc) {
                  _sortBySchedule = false;
                  _sortByKind = false;
                  _sortByLastStatus = false;
                  _sortByNext = true;
                  _sortById = false;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortByDesc = false;
                  _sortByLastRun = false;
                  _sortAsc = true;
                } else if (_sortByNext && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByNext && !_sortAsc) {
                  _sortBySchedule = false;
                  _sortByKind = false;
                  _sortByLastStatus = false;
                  _sortByNext = false;
                  _sortById = true;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortByDesc = false;
                  _sortByLastRun = false;
                  _sortAsc = true;
                } else if (_sortById && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortById && !_sortAsc) {
                  _sortBySchedule = false;
                  _sortByKind = false;
                  _sortByLastStatus = false;
                  _sortByNext = false;
                  _sortById = false;
                  _sortByEnabled = true;
                  _sortByName = false;
                  _sortByDesc = false;
                  _sortByLastRun = false;
                  _sortAsc = true;
                } else if (_sortByEnabled && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByEnabled && !_sortAsc) {
                  _sortBySchedule = false;
                  _sortByKind = false;
                  _sortByLastStatus = false;
                  _sortByNext = false;
                  _sortById = false;
                  _sortByEnabled = false;
                  _sortByName = true;
                  _sortByDesc = false;
                  _sortByLastRun = false;
                  _sortAsc = true;
                } else if (_sortByName && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByName && !_sortAsc) {
                  _sortBySchedule = false;
                  _sortByKind = false;
                  _sortByLastStatus = false;
                  _sortByNext = false;
                  _sortById = false;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortByDesc = true;
                  _sortByLastRun = false;
                  _sortAsc = true;
                } else if (_sortByDesc && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByDesc && !_sortAsc) {
                  _sortBySchedule = false;
                  _sortByKind = false;
                  _sortByLastStatus = false;
                  _sortByNext = false;
                  _sortById = false;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortByDesc = false;
                  _sortByLastRun = true;
                  _sortAsc = false; // new first
                } else if (_sortByLastRun && !_sortAsc) {
                  _sortAsc = true;
                } else {
                  _sortBySchedule = false;
                  _sortByKind = false;
                  _sortByLastStatus = false;
                  _sortByNext = false;
                  _sortById = false;
                  _sortByEnabled = false;
                  _sortByName = false;
                  _sortByDesc = false;
                  _sortByLastRun = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(
              _sortByLastRun
                  ? Icons.history
                  : (_sortByDesc
                        ? Icons.notes
                        : (_sortByName
                              ? Icons.sort_by_alpha
                              : (_sortByEnabled
                                    ? Icons.toggle_on_outlined
                                    : (_sortById
                                          ? Icons.tag
                                          : (_sortByNext
                                                ? Icons.event
                                                : (_sortByLastStatus
                                                      ? Icons.flag_outlined
                                                      : (_sortByKind
                                                            ? Icons
                                                                  .category_outlined
                                                            : (_sortBySchedule
                                                                  ? Icons
                                                                        .schedule
                                                                  : (_sortAsc
                                                                        ? Icons
                                                                              .sort_by_alpha
                                                                        : Icons
                                                                              .sort))))))))),
            ),
          ),
          IconButton(
            tooltip: _wrapLines ? '截断详情' : '换行详情',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
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
            tooltip: _autoRefresh ? '暂停刷新' : '自动刷新',
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
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                hintText: _queryRegex
                    ? (_queryCase ? '筛选（正则 · 大小写）' : '筛选（正则）')
                    : (_queryCase
                          ? '筛选（区分大小写）'
                          : '筛选名称 / 计划 / 状态'),
                isDense: true,
                border: const OutlineInputBorder(),
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
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _q.clear();
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
                  ('on', 'Enabled'),
                  ('off', 'Disabled'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                    selected: _enabled == f.$1,
                    onSelected: (_) => setState(() => _enabled = f.$1),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final f in const [
                  ('all', '任意类型'),
                  ('prompt', 'prompt'),
                  ('http', 'http'),
                  ('bash', 'bash'),
                  ('other', 'other'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 11)),
                    selected: _kind == f.$1,
                    onSelected: (_) => setState(() => _kind = f.$1),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final f in const [
                  ('all', '任意状态'),
                  ('ok', 'ok'),
                  ('error', 'error'),
                  ('running', 'running'),
                  ('other', 'other'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 11)),
                    selected: _lastStatus == f.$1,
                    onSelected: (_) => setState(() => _lastStatus = f.$1),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('换行', style: TextStyle(fontSize: 11)),
                  selected: _wrapLines,
                  onSelected: (v) => setState(() => _wrapLines = v),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text('Regex', style: TextStyle(fontSize: 11)),
                  selected: _queryRegex,
                  onSelected: (v) => setState(() => _queryRegex = v),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text('Case', style: TextStyle(fontSize: 11)),
                  selected: _queryCase,
                  onSelected: (v) => setState(() => _queryCase = v),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text('自动', style: TextStyle(fontSize: 11)),
                  selected: _autoRefresh,
                  onSelected: (v) => setState(() => _autoRefresh = v),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _jobs.isEmpty && !_loading
                ? const Center(
                    child: Text('暂无定时任务（主机可能未暴露 /cron）'),
                  )
                : items.isEmpty
                ? const Center(child: Text('没有匹配的任务'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      controller: _scroll,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final j = items[i];
                        final enabled = j['enabled'] == true;
                        final name = (j['name'] ?? j['id'] ?? 'job').toString();
                        final kind = (j['kind'] ?? '').toString();
                        final schedule = (j['schedule'] ?? '').toString();
                        final last = (j['last_status'] ?? '').toString();
                        final proj = (j['project'] ?? '').toString();
                        final tags = j['tags'] is List
                            ? (j['tags'] as List)
                                  .map((e) => e.toString())
                                  .join(', ')
                            : '';
                        final sub =
                            '$kind · $schedule${proj.isNotEmpty ? ' · project=$proj' : ''}${tags.isNotEmpty ? ' · $tags' : ''}\nlast: $last · next: ${_fmtTs(j['next_run_at'])}\n${j['description'] ?? ''}';
                        return ListTile(
                          leading: Icon(
                            enabled ? Icons.schedule : Icons.schedule_outlined,
                            color: enabled ? Colors.green : Colors.grey,
                          ),
                          title: Text(name),
                          subtitle: Text(
                            sub,
                            maxLines: _wrapLines ? 8 : 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                          ),
                          isThreeLine: true,
                          trailing: Text(enabled ? 'on' : 'off'),
                          onLongPress: () async {
                            await Clipboard.setData(
                              ClipboardData(text: '$name\n$sub'),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('任务已复制'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
