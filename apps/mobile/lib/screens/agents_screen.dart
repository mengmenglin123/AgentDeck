import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  final _q = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
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

  String _agentTitle(dynamic a) {
    if (a is Map) {
      return (a['name'] ?? a['id'] ?? a['type'] ?? 'agent').toString();
    }
    return a.toString();
  }

  String _agentSub(dynamic a) {
    if (a is Map) {
      final parts = <String>[];
      for (final k in ['type', 'agent_type', 'status', 'description', 'version']) {
        final v = a[k];
        if (v != null && '$v'.isNotEmpty) parts.add('$k=$v');
      }
      return parts.isEmpty ? 'Host agent entry' : parts.join(' · ');
    }
    return 'Host agent entry';
  }

  bool _matchAgent(dynamic a) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${_agentTitle(a)} ${_agentSub(a)}'.toLowerCase().contains(q);
  }

  bool _matchProject(Map<String, dynamic> p) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final caps = ((p['capabilities'] as List?) ?? const []).join(' ');
    return '${p['name']} ${p['agent_type']} ${p['note']} $caps'.toLowerCase().contains(q);
  }

  List<dynamic> get _filteredAgents => _agents.where(_matchAgent).toList();
  List<Map<String, dynamic>> get _filteredProjects =>
      _projects.where(_matchProject).toList();
  List<dynamic> get _filteredPlatforms {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _platforms;
    return _platforms.where((p) => '$p'.toLowerCase().contains(q)).toList();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final agents = _filteredAgents;
    final projects = _filteredProjects;
    final platforms = _filteredPlatforms;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                hintText: 'Filter agents / platforms / projects',
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
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                Text('Host agent types', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                if (_agents.isEmpty)
                  const ListTile(dense: true, title: Text('No agents catalog (Host may omit /agents)'))
                else if (agents.isEmpty)
                  const ListTile(dense: true, title: Text('No agents match filter'))
                else
                  Column(
                    children: [
                      for (final a in agents)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.smart_toy_outlined),
                          title: Text(_agentTitle(a)),
                          subtitle: Text(_agentSub(a)),
                          trailing: IconButton(
                            tooltip: 'Copy',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () => _copy('${_agentTitle(a)}\n${_agentSub(a)}'),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                Text('Platforms', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                if (_platforms.isEmpty)
                  const ListTile(dense: true, title: Text('—'))
                else if (platforms.isEmpty)
                  const ListTile(dense: true, title: Text('No platforms match filter'))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in platforms)
                        ActionChip(
                          label: Text('$p'),
                          onPressed: () => _copy('$p'),
                        ),
                    ],
                  ),
                const Divider(height: 32),
                Text('Projects (from /projects)', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                if (projects.isEmpty && _projects.isNotEmpty)
                  const ListTile(dense: true, title: Text('No projects match filter')),
                for (final p in projects)
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
                      onLongPress: () => _copy(
                        '${p['name']}\nagent=${p['agent_type']} sessions=${p['sessions_count']}\n${p['note'] ?? ''}',
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
