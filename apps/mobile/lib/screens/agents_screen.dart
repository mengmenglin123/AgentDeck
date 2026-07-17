import 'package:flutter/material.dart';

import '../models/connection_config.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';

/// Readonly Host agents / platforms catalog (`GET /agents`).
class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key, required this.config});

  final ConnectionConfig config;

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  late final MgmtClient _mgmt = MgmtClient(config: widget.config);
  bool _loading = true;
  String? _error;
  List<dynamic> _agents = [];
  List<dynamic> _platforms = [];
  List<Map<String, dynamic>> _projects = [];

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
      final data = await _mgmt.agents();
      final projects = await _mgmt.projects();
      setState(() {
        _agents = (data['agents'] is List) ? List<dynamic>.from(data['agents'] as List) : [];
        _platforms =
            (data['platforms'] is List) ? List<dynamic>.from(data['platforms'] as List) : [];
        _projects = projects
            .map(
              (p) => {
                'name': p.name,
                'agent_type': p.agentType,
                'sessions_count': p.sessionsCount,
                'note': p.note,
                'capabilities': p.capabilities,
              },
            )
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = Security.redactText(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agents'),
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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                Text('Host agent types', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                if (_agents.isEmpty)
                  const ListTile(dense: true, title: Text('No agents catalog (Host may omit /agents)'))
                else
                  Column(
                    children: [
                      for (final a in _agents)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.smart_toy_outlined),
                          title: Text(_agentTitle(a)),
                          subtitle: Text(_agentSub(a)),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                Text('Platforms', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                if (_platforms.isEmpty)
                  const ListTile(dense: true, title: Text('—'))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in _platforms) Chip(label: Text('$p')),
                    ],
                  ),
                const Divider(height: 32),
                Text('Projects (from /projects)', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final p in _projects)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.folder_special_outlined),
                      title: Text('${p['name']}'),
                      subtitle: Text(
                        'agent=${p['agent_type']} · sessions=${p['sessions_count']}'
                        '${(p['note'] != null && '${p['note']}'.isNotEmpty) ? '\n${p['note']}' : ''}',
                      ),
                      isThreeLine: (p['note'] != null && '${p['note']}'.isNotEmpty),
                      trailing: Text(
                        ((p['capabilities'] as List?) ?? const []).length.toString(),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
