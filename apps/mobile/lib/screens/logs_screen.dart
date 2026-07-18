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
  bool _wrapLines = true;
  final _scroll = ScrollController();
  Timer? _timer;
  bool _newestFirst = true;
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
    final q = _query.trim().toLowerCase();
    List<Map<String, dynamic>> list;
    if (q.isEmpty) {
      list = List<Map<String, dynamic>>.from(_logs);
    } else {
      list = _logs.where((e) {
        final msg = '${e['message'] ?? ''}'.toLowerCase();
        final level = '${e['level'] ?? ''}'.toLowerCase();
        final ts = '${e['ts'] ?? ''}'.toLowerCase();
        return msg.contains(q) || level.contains(q) || ts.contains(q);
      }).toList();
    }
    if (!_newestFirst) {
      return list.reversed.toList();
    }
    return list;
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
                hintText: 'Filter message / level',
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search, size: 20),
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
                      final when = ts is int
                          ? DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal().toIso8601String()
                          : '$ts';
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
