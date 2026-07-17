import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/connection_controller.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';
import 'host_dashboard_screen.dart';
import 'sessions_screen.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
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
      'uptime: ${_fmtUptime(_status['uptime_seconds'])}',
      'projects: ${_status['projects_count'] ?? '—'}',
      'sessions: ${_status['sessions_count'] ?? '—'}',
      'active_runs: ${_status['active_runs'] ?? '—'}',
      if (caps.isNotEmpty) 'capabilities: $caps',
      if (_error != null) 'status_error: $_error',
      if (c.lastHealthOkAt != null) 'last_health_ok: ${c.lastHealthOkAt!.toIso8601String()}',
      if (c.lastHealthError != null) 'last_health_error: ${c.lastHealthError}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Status summary copied (no token)'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ConnectionController>();
    final cfg = c.saved;
    if (cfg == null) {
      return const Scaffold(body: Center(child: Text('Not connected')));
    }
    final cs = Theme.of(context).colorScheme;
    final status = _status.isNotEmpty ? _status : (c.lastStatus ?? const {});
    final caps = (status['capabilities'] as List?) ?? const [];
    final healthy = _error == null && status.isNotEmpty;
    final barColor = _loading && status.isEmpty
        ? Colors.amber
        : (_error != null
            ? cs.error
            : (c.healthDegraded ? Colors.orange : (healthy ? Colors.green : Colors.orange)));
    final barLabel = _loading && status.isEmpty
        ? 'Probing…'
        : (_error != null
            ? 'Status error'
            : (c.healthDegraded ? 'Health degraded' : (healthy ? 'Host healthy' : 'Waiting')));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Host connected'),
        actions: [
          IconButton(
            tooltip: 'Copy summary',
            onPressed: () => _copySummary(c),
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Disconnect',
            onPressed: () => c.disconnect(),
            icon: const Icon(Icons.link_off),
          ),
          IconButton(
            tooltip: 'Clear saved profile',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear saved profile?'),
                  content: const Text(
                    'Removes host settings and tokens from secure storage.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Clear'),
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: barColor.withOpacity(0.12),
            child: ListTile(
              leading: Icon(
                healthy && !c.healthDegraded ? Icons.favorite : Icons.monitor_heart_outlined,
                color: barColor,
              ),
              title: Text(barLabel, style: TextStyle(fontWeight: FontWeight.w600, color: barColor)),
              subtitle: Text(
                _error ?? 'Mgmt ${cfg.mgmtBaseUrl}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              trailing: TextButton(onPressed: _loading ? null : _refresh, child: const Text('Check')),
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
                c.lastHealthError == null ? Icons.health_and_safety_outlined : Icons.report_gmailerrorred_outlined,
                color: c.lastHealthError == null ? Colors.green : cs.error,
              ),
              title: const Text('Last health probe'),
              subtitle: Text(
                [
                  if (c.lastHealthOkAt != null)
                    'OK at ${c.lastHealthOkAt!.toLocal().toIso8601String()}',
                  if (c.lastHealthError != null)
                    'Error: ${c.lastHealthError}',
                  if (c.lastHealthOkAt == null && c.lastHealthError == null)
                    'No probe yet',
                ].join('\n'),
              ),
              isThreeLine: true,
              trailing: c.lastHealthError == null
                  ? null
                  : IconButton(
                      tooltip: 'Copy error',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: c.lastHealthError ?? ''));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Health error copied'), duration: Duration(seconds: 1)),
                          );
                        }
                      },
                    ),
            ),
          ),
          const Divider(),
          Text('Snapshot', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('version ${status['version'] ?? '—'}')),
              Chip(label: Text('uptime ${_fmtUptime(status['uptime_seconds'])}')),
              Chip(label: Text('projects ${status['projects_count'] ?? '—'}')),
              Chip(label: Text('sessions ${status['sessions_count'] ?? '—'}')),
              Chip(label: Text('runs ${status['active_runs'] ?? '—'}')),
            ],
          ),
          if (caps.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Capabilities', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final cap in caps) Chip(label: Text('$cap', style: const TextStyle(fontSize: 11)))],
            ),
          ],
          const SizedBox(height: 16),
          Text('Raw /status keys', style: Theme.of(context).textTheme.titleSmall),
          if (status.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No status payload yet.'),
            )
          else
            ...status.entries.map(
              (e) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(e.key),
                subtitle: Text('${e.value}'),
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
            label: const Text('Open sessions'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HostDashboardScreen()),
              );
            },
            icon: const Icon(Icons.dashboard_outlined),
            label: const Text('Host dashboard'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => c.disconnect(),
            icon: const Icon(Icons.edit),
            label: const Text('Edit connection'),
          ),
        ],
      ),
    );
  }
}
