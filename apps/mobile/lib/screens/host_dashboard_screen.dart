import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_controller.dart';
import '../services/connection_controller.dart';
import '../services/mgmt_client.dart';
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
  Timer? _timer;
  DateTime? _lastOk;

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
    _timer?.cancel();
    super.dispose();
  }

  void _armTimer() {
    _timer?.cancel();
    if (!mounted) return;
    final sec = context.read<AppSettingsController>().dashboardRefreshSec;
    if (sec <= 0) return;
    _timer = Timer.periodic(Duration(seconds: sec), (_) {
      if (!mounted || _loading) return;
      _refresh(silent: true);
    });
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

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionController>();
    final cfg = conn.saved;
    final cs = Theme.of(context).colorScheme;
    final refreshSec = context.watch<AppSettingsController>().dashboardRefreshSec;
    // Re-arm timer when setting changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final armed = _timer != null;
      final want = refreshSec > 0;
      if (armed != want || (want && _timer?.isActive != true)) {
        _armTimer();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Host status'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: cfg == null
          ? const Center(child: Text('Not connected'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.dns, color: cs.primary),
                  title: Text(cfg.host),
                  subtitle: Text(
                    'Mgmt ${cfg.mgmtBaseUrl}\nBridge ${cfg.bridgeWsUrlRedacted}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                ),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: TextStyle(color: cs.error, fontSize: 12)),
                  ),
                if (_lastOk != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Last refresh: ${_lastOk!.toLocal().toIso8601String().substring(11, 19)}'
                      ' · auto ${refreshSec == 0 ? "off" : "${refreshSec}s"}',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatChip(label: 'version', value: '${_status['version'] ?? '—'}'),
                    _StatChip(label: 'uptime', value: _fmtUptime(_status['uptime_seconds'])),
                    _StatChip(label: 'projects', value: '${_status['projects_count'] ?? '—'}'),
                    _StatChip(label: 'sessions', value: '${_status['sessions_count'] ?? '—'}'),
                    _StatChip(label: 'runs', value: '${_status['active_runs'] ?? '—'}'),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Capabilities', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in (_status['capabilities'] as List? ?? const []))
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('$c', style: const TextStyle(fontSize: 11)),
                      ),
                    if ((_status['capabilities'] as List? ?? const []).isEmpty)
                      const Text('—', style: TextStyle(fontSize: 12)),
                  ],
                ),
                const Divider(height: 32),
                Text('Shortcuts', style: Theme.of(context).textTheme.titleSmall),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Workspace (readonly)'),
                  subtitle: const Text('Browse host files + mock git status'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => WorkspaceScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.difference_outlined),
                  title: const Text('Git diff (readonly)'),
                  subtitle: const Text('Unified diff from Host'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => DiffScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.psychology_outlined),
                  title: const Text('Host memory'),
                  subtitle: const Text('Readonly catalog from Host'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MemoryScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Host schedules'),
                  subtitle: const Text('Readonly cron jobs'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => CronScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('Skills'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => SkillsScreen(config: cfg)),
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
                  title: const Text('Host activity'),
                  subtitle: const Text('Readonly event feed'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ActivityScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('Agents'),
                  subtitle: const Text('Host agent catalog'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AgentsScreen(config: cfg)),
                  ),
                ),

                ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: const Text('Pairing URI'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => PairingScreen(config: cfg)),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Host logs'),
                  subtitle: const Text('Readonly log feed'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => LogsScreen(config: cfg)),
                  ),
                ),

                const SizedBox(height: 12),
                ExpansionTile(
                  title: const Text('Raw /status'),
                  children: [
                    for (final e in _status.entries)
                      ListTile(
                        dense: true,
                        title: Text(e.key),
                        subtitle: Text(Security.redactText('${e.value}')),
                      ),
                  ],
                ),
              ],
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
