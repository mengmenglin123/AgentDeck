import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/app_settings_controller.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';

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
  /// all | on | off
  String _enabled = 'all';
  bool _wrapLines = false;
  bool _sortBySchedule = false;
  bool _sortByKind = false;
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
      return dt.toLocal().toIso8601String().replaceFirst('T', ' ').substring(0, 19);
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
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      it = it.where((j) {
        final hay =
            '${j['name']} ${j['id']} ${j['kind']} ${j['schedule']} ${j['description']} ${j['last_status']}'
                .toLowerCase();
        return hay.contains(q);
      });
    }
    final list = it.toList();
    list.sort((a, b) {
      if (_sortByKind) {
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
    _timer?.cancel();
    if (!_autoRefresh || !mounted) return;
    final sec = context.read<AppSettingsController>().dashboardRefreshSec;
    if (sec <= 0) return;
    _timer = Timer.periodic(Duration(seconds: sec), (_) {
      if (!mounted || _loading) return;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          items.isEmpty
              ? 'Host schedules'
              : (items.length == _jobs.length
                  ? 'Host schedules (${items.length})'
                  : 'Host schedules (${items.length}/${_jobs.length})'),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy all',
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
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied ${items.length} jobs'), duration: const Duration(seconds: 1)),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Copy CSV',
            onPressed: items.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    buf.writeln('id,name,enabled,schedule,kind,last_status,last_run');
                    for (final j in items) {
                      final id = '${j['id'] ?? ''}'.replaceAll(',', ';');
                      final name = '${j['name'] ?? ''}'.replaceAll(',', ';');
                      final en = '${j['enabled'] ?? ''}';
                      final schedule = '${j['schedule'] ?? ''}'.replaceAll(',', ';');
                      final kind = '${j['kind'] ?? ''}'.replaceAll(',', ';');
                      final status = '${j['last_status'] ?? ''}'.replaceAll(',', ';');
                      final last = _fmtTs(j['last_run']).replaceAll(',', ';');
                      buf.writeln('$id,$name,$en,$schedule,$kind,$status,$last');
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied CSV (${items.length})'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: _sortByKind
                ? (_sortAsc ? 'Kind Z→A' : 'Kind A→Z')
                : (_sortBySchedule
                    ? (_sortAsc ? 'Schedule Z→A' : 'Schedule A→Z')
                    : (_sortAsc ? 'Name Z→A' : 'Name A→Z')),
            onPressed: () {
              setState(() {
                if (!_sortBySchedule && !_sortByKind && _sortAsc) {
                  _sortAsc = false;
                } else if (!_sortBySchedule && !_sortByKind && !_sortAsc) {
                  _sortBySchedule = true;
                  _sortByKind = false;
                  _sortAsc = true;
                } else if (_sortBySchedule && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortBySchedule && !_sortAsc) {
                  _sortBySchedule = false;
                  _sortByKind = true;
                  _sortAsc = true;
                } else if (_sortByKind && _sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortBySchedule = false;
                  _sortByKind = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(_sortByKind
                ? Icons.category_outlined
                : (_sortBySchedule
                    ? Icons.schedule
                    : (_sortAsc ? Icons.sort_by_alpha : Icons.sort))),
          ),
          IconButton(
            tooltip: _wrapLines ? 'Clamp details' : 'Wrap details',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
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


          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                hintText: 'Filter name / schedule / status',
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search, size: 18),
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
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _jobs.isEmpty && !_loading
                ? const Center(child: Text('No cron jobs (Host may not expose /cron)'))
                : items.isEmpty
                    ? const Center(child: Text('No jobs match filter'))
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
                          final sub =
                              '$kind · $schedule\nlast: $last · next: ${_fmtTs(j['next_run_at'])}\n${j['description'] ?? ''}';
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
                              await Clipboard.setData(ClipboardData(text: '$name\n$sub'));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Job copied'), duration: Duration(seconds: 1)),
                                );
                              }
                            },
                          );
                        },
                      )),
          ),
        ],
      ),
    );
  }
}
