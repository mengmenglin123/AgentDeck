import 'package:flutter/material.dart';

import '../models/connection_config.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';

/// Readonly Host activity feed (`GET /activity`).
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.config});

  final ConnectionConfig config;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late final MgmtClient _mgmt = MgmtClient(config: widget.config);
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];

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
      final data = await _mgmt.listActivity(limit: 80);
      final raw = data['events'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      setState(() {
        _events = list;
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

  IconData _icon(String kind) {
    if (kind.contains('session')) return Icons.forum_outlined;
    if (kind.contains('chat') || kind.contains('message')) return Icons.chat_bubble_outline;
    if (kind.contains('host')) return Icons.dns_outlined;
    if (kind.contains('cron')) return Icons.schedule;
    return Icons.bolt_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host activity'),
        actions: [
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
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _events.isEmpty && !_loading
                ? const Center(child: Text('No activity yet (Host may not expose /activity)'))
                : ListView.separated(
                    itemCount: _events.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final e = _events[i];
                      final kind = (e['kind'] ?? 'event').toString();
                      final summary = (e['summary'] ?? '').toString();
                      return ListTile(
                        leading: Icon(_icon(kind)),
                        title: Text(summary.isEmpty ? kind : summary),
                        subtitle: Text('$kind · ${_fmtTs(e['ts'])}'),
                        dense: true,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
