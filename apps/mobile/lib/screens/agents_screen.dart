import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/app_settings_controller.dart';
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
  /// all | agents | platforms | projects
  String _section = 'all';
  String _statusFilter = '';
  bool _wrapLines = false;
  bool _sortByType = false;
  bool _sortByModel = false;
  bool _sortByStatus = false;
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
      for (final k in ['type', 'agent_type', 'status', 'model', 'provider', 'description', 'version']) {
        final v = a[k];
        if (v != null && '$v'.isNotEmpty) parts.add('$k=$v');
      }
      return parts.isEmpty ? 'Host agent entry' : parts.join(' · ');
    }
    return 'Host agent entry';
  }

  bool _matchAgent(dynamic a) {
    if (_statusFilter.isNotEmpty) {
      final st = _agentStatusKey(a);
      if (st != _statusFilter) return false;
    }
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

  String _agentStatusKey(dynamic a) {
    if (a is Map) {
      return (a['status'] ?? a['state'] ?? a['phase'] ?? '').toString().toLowerCase();
    }
    return '';
  }

  List<String> get _statusOptions {
    final set = <String>{};
    for (final a in _agents) {
      final s = _agentStatusKey(a);
      if (s.isNotEmpty) set.add(s);
    }
    final list = set.toList()..sort();
    return list;
  }

  String _agentModelKey(dynamic a) {
    if (a is Map) {
      return (a['model'] ?? a['provider'] ?? a['llm'] ?? a['engine'] ?? '').toString().toLowerCase();
    }
    return '';
  }

  String _agentTypeKey(dynamic a) {
    if (a is Map) {
      return (a['type'] ?? a['agent_type'] ?? a['status'] ?? '').toString().toLowerCase();
    }
    return '';
  }

  List<dynamic> get _filteredAgents {
    final list = _agents.where(_matchAgent).toList();
    list.sort((a, b) {
      if (_sortByStatus) {
        final c = _agentStatusKey(a).compareTo(_agentStatusKey(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByModel) {
        final c = _agentModelKey(a).compareTo(_agentModelKey(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByType) {
        final c = _agentTypeKey(a).compareTo(_agentTypeKey(b));
        if (c != 0) return _sortAsc ? c : -c;
      }
      final c = _agentTitle(a).toLowerCase().compareTo(_agentTitle(b).toLowerCase());
      return _sortAsc ? c : -c;
    });
    return list;
  }

  List<Map<String, dynamic>> get _filteredProjects {
    final list = _projects.where(_matchProject).toList();
    list.sort((a, b) {
      final na = (a['name'] ?? a['id'] ?? '').toString().toLowerCase();
      final nb = (b['name'] ?? b['id'] ?? '').toString().toLowerCase();
      final c = na.compareTo(nb);
      return _sortAsc ? c : -c;
    });
    return list;
  }

  List<dynamic> get _filteredPlatforms {
    final q = _query.trim().toLowerCase();
    final list = _platforms.where((p) => q.isEmpty || '$p'.toLowerCase().contains(q)).toList();
    list.sort((a, b) {
      final c = '$a'.toLowerCase().compareTo('$b'.toLowerCase());
      return _sortAsc ? c : -c;
    });
    return list;
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
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
    final agents = _filteredAgents;
    final projects = _filteredProjects;
    final platforms = _filteredPlatforms;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          agents.isEmpty && projects.isEmpty
              ? 'Agents'
              : 'Agents (${agents.length}a · ${projects.length}p)',
        ),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            onPressed: (agents.isEmpty && projects.isEmpty && platforms.isEmpty)
                ? null
                : () async {
                    final buf = StringBuffer();
                    for (final a in agents) {
                      if (a is Map) {
                        final m = Map<String, dynamic>.from(a as Map);
                        buf.writeln('agent: ${m['name'] ?? m['id'] ?? m}');
                        buf.writeln('  $m');
                      } else {
                        buf.writeln('agent: $a');
                      }
                    }
                    for (final p in projects) {
                      buf.writeln('project: ${p['name'] ?? p['id'] ?? p}');
                    }
                    for (final p in platforms) {
                      buf.writeln('platform: $p');
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Copied ${agents.length} agents / ${projects.length} projects',
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Copy CSV',
            onPressed: (agents.isEmpty && projects.isEmpty && platforms.isEmpty)
                ? null
                : () async {
                    final buf = StringBuffer();
                    buf.writeln('kind,name,id,extra');
                    for (final a in agents) {
                      if (a is Map) {
                        final m = Map<String, dynamic>.from(a as Map);
                        final name = '${m['name'] ?? ''}'.replaceAll(',', ';');
                        final id = '${m['id'] ?? ''}'.replaceAll(',', ';');
                        final extra = '${m['model'] ?? m['provider'] ?? m['status'] ?? ''}'.replaceAll(',', ';');
                        buf.writeln('agent,$name,$id,$extra');
                      } else {
                        buf.writeln('agent,${'$a'.replaceAll(',', ';')},,');
                      }
                    }
                    for (final p in projects) {
                      final name = '${p['name'] ?? ''}'.replaceAll(',', ';');
                      final id = '${p['id'] ?? ''}'.replaceAll(',', ';');
                      buf.writeln('project,$name,$id,');
                    }
                    for (final p in platforms) {
                      final name = '$p'.replaceAll(',', ';');
                      buf.writeln('platform,$name,,');
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Copied CSV (${agents.length}a · ${projects.length}p · ${platforms.length}pl)',
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: _sortByStatus
                ? (_sortAsc ? 'Status Z→A' : 'Status A→Z')
                : (_sortByModel
                    ? (_sortAsc ? 'Model Z→A' : 'Model A→Z')
                    : (_sortByType
                        ? (_sortAsc ? 'Type Z→A' : 'Type A→Z')
                        : (_sortAsc ? 'Name Z→A' : 'Name A→Z'))),
            onPressed: () {
              setState(() {
                if (!_sortByType && !_sortByModel && !_sortByStatus && _sortAsc) {
                  _sortAsc = false;
                } else if (!_sortByType && !_sortByModel && !_sortByStatus && !_sortAsc) {
                  _sortByType = true;
                  _sortByModel = false;
                  _sortByStatus = false;
                  _sortAsc = true;
                } else if (_sortByType && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByType && !_sortAsc) {
                  _sortByType = false;
                  _sortByModel = true;
                  _sortByStatus = false;
                  _sortAsc = true;
                } else if (_sortByModel && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByModel && !_sortAsc) {
                  _sortByType = false;
                  _sortByModel = false;
                  _sortByStatus = true;
                  _sortAsc = true;
                } else if (_sortByStatus && _sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortByType = false;
                  _sortByModel = false;
                  _sortByStatus = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(_sortByStatus
                ? Icons.flag_outlined
                : (_sortByModel
                    ? Icons.memory_outlined
                    : (_sortByType
                        ? Icons.category_outlined
                        : (_sortAsc ? Icons.sort_by_alpha : Icons.sort)))),
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in const [
                  ('all', 'All'),
                  ('agents', 'Agents'),
                  ('platforms', 'Platforms'),
                  ('projects', 'Projects'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                    selected: _section == f.$1,
                    onSelected: (_) => setState(() => _section = f.$1),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          if (_statusOptions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: const Text('Any status', style: TextStyle(fontSize: 11)),
                        selected: _statusFilter.isEmpty,
                        onSelected: (_) => setState(() => _statusFilter = ''),
                      ),
                    ),
                    for (final s in _statusOptions)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(s, style: const TextStyle(fontSize: 11)),
                          selected: _statusFilter == s,
                          onSelected: (_) => setState(() {
                            _statusFilter = _statusFilter == s ? '' : s;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
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
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                      controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                children: [
                if (_section == 'all' || _section == 'agents') ...[
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
                          subtitle: Text(
                            _agentSub(a),
                            maxLines: _wrapLines ? 8 : 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                          ),
                          trailing: IconButton(
                            tooltip: 'Copy',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () => _copy('${_agentTitle(a)}\n${_agentSub(a)}'),
                          ),
                        ),
                    ],
                  ),
                ],
                if (_section == 'all' || _section == 'platforms') ...[
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
                ],
                if (_section == 'all' || _section == 'projects') ...[
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
                        maxLines: _wrapLines ? 8 : 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
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
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }
}
