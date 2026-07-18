import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/app_settings_controller.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';

/// Readonly Host logs feed (`GET /logs`).
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, required this.config});

  final ConnectionConfig config;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  late final MgmtClient _mgmt = MgmtClient(config: widget.config);
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = [];
  String _level = '';
  String _query = '';
  bool _queryCase = false;
  bool _queryRegex = false;
  bool _wrapLines = true;
  final _scroll = ScrollController();
  Timer? _timer;
  bool _newestFirst = true;
  bool _sortByMsg = false;
  bool _sortByLevel = false;
  bool _sortByLogger = false;
  bool _sortAsc = true;
  bool _autoRefresh = false;
  bool _relativeTs = false;

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
    super.dispose();
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _mgmt.logs(limit: 100, level: _level.isEmpty ? null : _level);
      final raw = data['logs'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      setState(() {
        _logs = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = Security.redactText(e.toString());
      });
    }
  }

  List<Map<String, dynamic>> get _visible {
    final rawQ = _query.trim();
    final q = _queryCase ? rawQ : rawQ.toLowerCase();
    List<Map<String, dynamic>> list;
    if (rawQ.isEmpty) {
      list = List<Map<String, dynamic>>.from(_logs);
    } else if (_queryRegex) {
      try {
        final re = RegExp(rawQ, caseSensitive: _queryCase);
        list = _logs.where((e) {
          final hay =
              '${e['message'] ?? ''} ${e['level'] ?? ''} ${e['ts'] ?? ''} ${e['logger'] ?? e['source'] ?? e['component'] ?? e['module'] ?? ''}';
          return re.hasMatch(hay);
        }).toList();
      } catch (_) {
        list = [];
      }
    } else {
      list = _logs.where((e) {
        String norm(Object? v) {
          final s = '${v ?? ''}';
          return _queryCase ? s : s.toLowerCase();
        }
        final msg = norm(e['message']);
        final level = norm(e['level']);
        final ts = norm(e['ts']);
        final logger = norm(e['logger'] ?? e['source'] ?? e['component'] ?? e['module']);
        return msg.contains(q) || level.contains(q) || logger.contains(q) || ts.contains(q);
      }).toList();
    }
    list.sort((a, b) {
      String loggerOf(Map x) =>
          (x['logger'] ?? x['source'] ?? x['component'] ?? x['module'] ?? x['name'] ?? '')
              .toString()
              .toLowerCase();
      if (_sortByLogger) {
        final c = loggerOf(a).compareTo(loggerOf(b));
        if (c != 0) return _sortAsc ? c : -c;
        final ma = '${a['message'] ?? ''}'.toLowerCase();
        final mb = '${b['message'] ?? ''}'.toLowerCase();
        final cm = ma.compareTo(mb);
        if (cm != 0) return _sortAsc ? cm : -cm;
      } else if (_sortByLevel) {
        final la = '${a['level'] ?? ''}'.toLowerCase();
        final lb = '${b['level'] ?? ''}'.toLowerCase();
        final cl = la.compareTo(lb);
        if (cl != 0) return _sortAsc ? cl : -cl;
        final ma = '${a['message'] ?? ''}'.toLowerCase();
        final mb = '${b['message'] ?? ''}'.toLowerCase();
        final cm = ma.compareTo(mb);
        if (cm != 0) return _sortAsc ? cm : -cm;
      } else if (_sortByMsg) {
        final ma = '${a['message'] ?? ''}'.toLowerCase();
        final mb = '${b['message'] ?? ''}'.toLowerCase();
        final c = ma.compareTo(mb);
        if (c != 0) return _sortAsc ? c : -c;
        final la = '${a['level'] ?? ''}'.toLowerCase();
        final lb = '${b['level'] ?? ''}'.toLowerCase();
        final cl = la.compareTo(lb);
        if (cl != 0) return _sortAsc ? cl : -cl;
      }
      int tsOf(Map<String, dynamic> e) {
        final v = e['ts'];
        if (v is num) {
          final n = v.toDouble();
          return n > 1e12 ? n.round() : (n * 1000).round();
        }
        final p = DateTime.tryParse(v?.toString() ?? '');
        return p?.millisecondsSinceEpoch ?? 0;
      }
      final c = tsOf(a).compareTo(tsOf(b));
      return _newestFirst ? -c : c;
    });
    return list;
  }

  String _fmtWhen(dynamic ts) {
    DateTime? dt;
    if (ts is int) {
      final ms = ts > 1e12 ? ts : ts * 1000;
      dt = DateTime.fromMillisecondsSinceEpoch(ms.round()).toLocal();
    } else if (ts is num) {
      final n = ts.toDouble();
      final ms = n > 1e12 ? n.round() : (n * 1000).round();
      dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    } else {
      dt = DateTime.tryParse(ts?.toString() ?? '')?.toLocal();
    }
    if (dt == null) return '$ts';
    if (!_relativeTs) return dt.toIso8601String();
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 48) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  Color _levelColor(String level, ColorScheme cs) {
    switch (level.toLowerCase()) {
      case 'error':
      case 'fatal':
      case 'critical':
        return cs.error;
      case 'warn':
      case 'warning':
        return Colors.orange.shade800;
      case 'debug':
      case 'trace':
        return cs.outline;
      case 'info':
        return cs.primary;
      default:
        return cs.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          () {
            final base = _visible.isEmpty
                ? 'Host logs'
                : (_visible.length == _logs.length
                    ? 'Host logs (${_visible.length})'
                    : 'Host logs (${_visible.length}/${_logs.length})');
            return _autoRefresh ? '$base · auto' : base;
          }(),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            onPressed: _visible.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    for (final e in _visible) {
                      final level = '${e['level'] ?? 'info'}';
                      final msg = '${e['message'] ?? ''}';
                      final ts = e['ts'];
                      buf.writeln('[$level] $ts $msg');
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied ${_visible.length} lines'), duration: const Duration(seconds: 1)),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Copy CSV',
            onPressed: _visible.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    buf.writeln('ts,level,message');
                    for (final e in _visible) {
                      final ts = '${e['ts'] ?? ''}'.replaceAll(',', ';');
                      final level = '${e['level'] ?? 'info'}'.replaceAll(',', ';');
                      final msg = '${e['message'] ?? ''}'.replaceAll(',', ';').replaceAll('\n', ' ');
                      buf.writeln('$ts,$level,$msg');
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied CSV (${_visible.length})'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: _newestFirst ? 'Oldest first' : 'Newest first',
            onPressed: () => setState(() => _newestFirst = !_newestFirst),
            icon: Icon(_newestFirst ? Icons.arrow_downward : Icons.arrow_upward),
          ),
          IconButton(
            tooltip: _sortByLogger
                ? (_sortAsc ? 'Logger Z→A' : 'Logger A→Z')
                : (_sortByLevel
                    ? (_sortAsc ? 'Levels Z→A' : 'Levels A→Z')
                    : (_sortByMsg
                        ? (_sortAsc ? 'Messages Z→A' : 'Messages A→Z')
                        : 'Sort by message / level / logger')),
            onPressed: () {
              setState(() {
                if (!_sortByMsg && !_sortByLevel && !_sortByLogger) {
                  _sortByMsg = true;
                  _sortByLevel = false;
                  _sortByLogger = false;
                  _sortAsc = true;
                } else if (_sortByMsg && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByMsg && !_sortAsc) {
                  _sortByMsg = false;
                  _sortByLevel = true;
                  _sortByLogger = false;
                  _sortAsc = true;
                } else if (_sortByLevel && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByLevel && !_sortAsc) {
                  _sortByMsg = false;
                  _sortByLevel = false;
                  _sortByLogger = true;
                  _sortAsc = true;
                } else if (_sortByLogger && _sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortByMsg = false;
                  _sortByLevel = false;
                  _sortByLogger = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(_sortByLogger
                ? Icons.account_tree_outlined
                : (_sortByLevel
                    ? Icons.low_priority
                    : (_sortByMsg ? Icons.sort_by_alpha : Icons.sort))),
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
            tooltip: _wrapLines ? 'No wrap' : 'Wrap lines',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.horizontal_rule),
          ),
          IconButton(
            tooltip: _relativeTs ? 'Absolute timestamps' : 'Relative timestamps',
            onPressed: () => setState(() => _relativeTs = !_relativeTs),
            icon: Icon(_relativeTs ? Icons.schedule : Icons.access_time),
          ),

          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in const [
                  ('', 'All'),
                  ('info', 'Info'),
                  ('debug', 'Debug'),
                  ('warn', 'Warn'),
                  ('error', 'Error'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                    selected: _level == f.$1,
                    onSelected: (_) {
                      setState(() => _level = f.$1);
                      _load();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: _queryRegex
                    ? (_queryCase ? 'Filter (regex · case)' : 'Filter (regex)')
                    : (_queryCase ? 'Filter (case-sensitive)' : 'Filter message / level'),
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: IconButton(
                  tooltip: _queryRegex
                      ? (_queryCase
                          ? 'Regex · case on (long-press: plain filter)'
                          : 'Regex · case off (long-press: plain filter)')
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
                        onPressed: () => setState(() => _query = ''),
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _logs.isEmpty && !_loading
                ? const Center(child: Text('No log lines (Host may omit /logs)'))
                : _visible.isEmpty && !_loading
                    ? const Center(child: Text('No lines match filter'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                    itemCount: _visible.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = _visible[i];
                      final level = '${e['level'] ?? 'info'}';
                      final msg = '${e['message'] ?? ''}';
                      final ts = e['ts'];
                      final when = _fmtWhen(ts);
                      final color = _levelColor(level, cs);
                      return Container(
                        decoration: BoxDecoration(
                          border: Border(left: BorderSide(color: color, width: 3)),
                          color: level.toLowerCase() == 'error'
                              ? cs.errorContainer.withOpacity(0.25)
                              : (level.toLowerCase() == 'warn' || level.toLowerCase() == 'warning')
                                  ? Colors.orange.withOpacity(0.08)
                                  : null,
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: color.withOpacity(0.5)),
                            ),
                            child: Text(
                              level.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: color,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          title: Text(
                            msg,
                            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                            maxLines: _wrapLines ? null : 1,
                            overflow: _wrapLines ? TextOverflow.visible : TextOverflow.ellipsis,
                            softWrap: _wrapLines,
                          ),
                          subtitle: Text(when, style: const TextStyle(fontSize: 10)),
                          onLongPress: () async {
                            await Clipboard.setData(ClipboardData(text: '[$level] $when $msg'));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Log line copied'), duration: Duration(seconds: 1)),
                              );
                            }
                          },
                        ),
                      );
                    },
                  )),
          ),
        ],
      ),
    );
  }
}
