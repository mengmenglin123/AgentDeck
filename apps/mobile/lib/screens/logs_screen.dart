import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/connection_config.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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
        title: const Text('Host logs'),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            onPressed: _logs.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    for (final e in _logs) {
                      final level = '${e['level'] ?? 'info'}';
                      final msg = '${e['message'] ?? ''}';
                      final ts = e['ts'];
                      buf.writeln('[$level] $ts $msg');
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied ${_logs.length} lines'), duration: const Duration(seconds: 1)),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_all_outlined),
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _logs.isEmpty && !_loading
                ? const Center(child: Text('No log lines (Host may omit /logs)'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                    itemCount: _logs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = _logs[i];
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
                          title: Text(msg, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
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
