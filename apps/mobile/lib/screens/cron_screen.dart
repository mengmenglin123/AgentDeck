import 'package:flutter/material.dart';

import '../models/connection_config.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host schedules'),
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
            child: _jobs.isEmpty && !_loading
                ? const Center(child: Text('No cron jobs (Host may not expose /cron)'))
                : ListView.separated(
                    itemCount: _jobs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final j = _jobs[i];
                      final enabled = j['enabled'] == true;
                      final name = (j['name'] ?? j['id'] ?? 'job').toString();
                      final kind = (j['kind'] ?? '').toString();
                      final schedule = (j['schedule'] ?? '').toString();
                      final last = (j['last_status'] ?? '').toString();
                      return ListTile(
                        leading: Icon(
                          enabled ? Icons.schedule : Icons.schedule_outlined,
                          color: enabled ? Colors.green : Colors.grey,
                        ),
                        title: Text(name),
                        subtitle: Text(
                          '$kind · $schedule\n'
                          'last: $last · next: ${_fmtTs(j['next_run_at'])}\n'
                          '${j['description'] ?? ''}',
                        ),
                        isThreeLine: true,
                        trailing: Text(enabled ? 'on' : 'off'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
