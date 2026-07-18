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
  bool _queryCase = false;
  bool _queryRegex = false;
  /// all | agents | platforms | projects
  String _section = 'all';
  String _statusFilter = '';
  /// Adapter filter: '' | mock | hermes | claude | codex | other
  String _adapter = '';
  /// Model filter: '' | gpt | claude | codex | gemini | other
  String _model = '';
  bool _wrapLines = false;
  bool _sortByType = false;
  bool _sortByModel = false;
  bool _sortByStatus = false;
  bool _sortByPlatform = false;
  bool _sortByProject = false;
  bool _sortById = false;
  bool _sortByProvider = false;
  bool _sortBySessions = false;
  bool _sortByCwd = false;
  bool _sortByNote = false;
  bool _sortByCaps = false;
  bool _sortByVersion = false;
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
      for (final k in ['type', 'agent_type', 'status', 'model', 'provider', 'adapter', 'process', 'description', 'version', 'note']) {
        final v = a[k];
        if (v != null && '$v'.isNotEmpty) parts.add('$k=$v');
      }
      final caps = a['capabilities'] ?? a['caps'];
      if (caps is List && caps.isNotEmpty) {
        parts.add('caps=${caps.map((e) => '$e').join(',')}');
      } else if (caps != null && '$caps'.isNotEmpty) {
        parts.add('caps=$caps');
      }
      return parts.isEmpty ? 'Host agent entry' : parts.join(' · ');
    }
    return 'Host agent entry';
  }

  String _agentAdapterKey(dynamic a) {
    if (a is Map) {
      return (a['adapter'] ?? a['runtime'] ?? a['backend'] ?? '').toString().toLowerCase();
    }
    return '';
  }

  bool _matchAgent(dynamic a) {
    if (_statusFilter.isNotEmpty) {
      final st = _agentStatusKey(a);
      if (st != _statusFilter) return false;
    }
    if (_adapter.isNotEmpty) {
      final ad = _agentAdapterKey(a);
      if (_adapter == 'other') {
        const known = ['mock', 'hermes', 'claude', 'codex', 'cc'];
        if (known.any((k) => ad.contains(k))) return false;
      } else if (!ad.contains(_adapter.toLowerCase())) {
        return false;
      }
    }
    if (_model.isNotEmpty) {
      final mk = _agentModelKey(a);
      if (_model == 'other') {
        const known = [
          'gpt',
          'claude',
          'sonnet',
          'opus',
          'haiku',
          'codex',
          'o1',
          'o3',
          'gemini',
          'deepseek',
          'qwen',
          'mimo',
          'minimax',
        ];
        if (known.any((k) => mk.contains(k))) return false;
      } else if (!mk.contains(_model.toLowerCase())) {
        return false;
      }
    }
    final rawQ = _query.trim();
    final q = _queryCase ? rawQ : rawQ.toLowerCase();
    if (rawQ.isEmpty) return true;
    final adapterHay = _agentAdapterKey(a);
    final modelHay = _agentModelKey(a);
    final hayRaw = '${_agentTitle(a)} ${_agentSub(a)} $adapterHay $modelHay';
    if (_queryRegex) {
      try {
        return RegExp(rawQ, caseSensitive: _queryCase).hasMatch(hayRaw);
      } catch (_) {
        return false;
      }
    }
    final hay = _queryCase ? hayRaw : hayRaw.toLowerCase();
    return hay.contains(q);
  }

  bool _matchProject(Map<String, dynamic> p) {
    final rawQ = _query.trim();
    final q = _queryCase ? rawQ : rawQ.toLowerCase();
    if (rawQ.isEmpty) return true;
    final caps = ((p['capabilities'] as List?) ?? const []).join(' ');
    final hayRaw = '${p['name']} ${p['agent_type']} ${p['note']} $caps';
    if (_queryRegex) {
      try {
        return RegExp(rawQ, caseSensitive: _queryCase).hasMatch(hayRaw);
      } catch (_) {
        return false;
      }
    }
    final hay = _queryCase ? hayRaw : hayRaw.toLowerCase();
    return hay.contains(q);
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

  String _agentPlatformKey(dynamic a) {
    if (a is Map) {
      return (a['platform'] ?? a['platform_name'] ?? a['runtime'] ?? a['env'] ?? '')
          .toString()
          .toLowerCase();
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
      if (_sortByVersion) {
        final va = (a['version'] ?? a['ver'] ?? a['agent_version'] ?? '').toString().toLowerCase();
        final vb = (b['version'] ?? b['ver'] ?? b['agent_version'] ?? '').toString().toLowerCase();
        final c = va.compareTo(vb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByCaps) {
        int capsOf(Map x) {
          final v = x['capabilities'] ?? x['caps'];
          if (v is List) return v.length;
          if (v is Map) return v.length;
          if (v is num) return v.round();
          final s = (v ?? '').toString().trim();
          if (s.isEmpty) return 0;
          return s.split(RegExp(r'[,\s]+')).where((e) => e.isNotEmpty).length;
        }
        final c = capsOf(a).compareTo(capsOf(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByNote) {
        final na = (a['note'] ?? a['notes'] ?? a['description'] ?? a['remark'] ?? '').toString().toLowerCase();
        final nb = (b['note'] ?? b['notes'] ?? b['description'] ?? b['remark'] ?? '').toString().toLowerCase();
        final c = na.compareTo(nb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByCwd) {
        final ca = (a['cwd'] ?? a['workspace'] ?? a['work_dir'] ?? a['dir'] ?? '').toString().toLowerCase();
        final cb = (b['cwd'] ?? b['workspace'] ?? b['work_dir'] ?? b['dir'] ?? '').toString().toLowerCase();
        final c = ca.compareTo(cb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortBySessions) {
        int scOf(Map x) {
          final v = x['sessions_count'] ?? x['session_count'] ?? x['sessions'];
          if (v is num) return v.round();
          if (v is List) return v.length;
          return int.tryParse(v?.toString() ?? '') ?? 0;
        }
        final c = scOf(a).compareTo(scOf(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByProvider) {
        final pa = (a['provider'] ?? a['llm'] ?? a['engine'] ?? a['runtime'] ?? '').toString().toLowerCase();
        final pb = (b['provider'] ?? b['llm'] ?? b['engine'] ?? b['runtime'] ?? '').toString().toLowerCase();
        final c = pa.compareTo(pb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortById) {
        final ia = (a['id'] ?? a['agent_id'] ?? a['name'] ?? '').toString().toLowerCase();
        final ib = (b['id'] ?? b['agent_id'] ?? b['name'] ?? '').toString().toLowerCase();
        final c = ia.compareTo(ib);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByProject) {
        final pa = (a['project'] ?? a['project_id'] ?? a['cwd'] ?? a['workspace'] ?? '').toString().toLowerCase();
        final pb = (b['project'] ?? b['project_id'] ?? b['cwd'] ?? b['workspace'] ?? '').toString().toLowerCase();
        final c = pa.compareTo(pb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByPlatform) {
        final c = _agentPlatformKey(a).compareTo(_agentPlatformKey(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByStatus) {
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
    final rawQ = _query.trim();
    final q = _queryCase ? rawQ : rawQ.toLowerCase();
    final list = _platforms.where((p) {
      if (rawQ.isEmpty) return true;
      final hayRaw = '$p';
      if (_queryRegex) {
        try {
          return RegExp(rawQ, caseSensitive: _queryCase).hasMatch(hayRaw);
        } catch (_) {
          return false;
        }
      }
      final hay = _queryCase ? hayRaw : hayRaw.toLowerCase();
      return hay.contains(q);
    }).toList();
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
            tooltip: _sortByVersion
                ? (_sortAsc ? 'Version Z→A' : 'Version A→Z')
                : (_sortByCaps
                    ? (_sortAsc ? 'Capabilities many→few' : 'Capabilities few→many')
                    : (_sortByNote
                    ? (_sortAsc ? 'Note Z→A' : 'Note A→Z')
                    : (_sortByCwd
                        ? (_sortAsc ? 'Cwd Z→A' : 'Cwd A→Z')
                        : (_sortBySessions
                            ? (_sortAsc ? 'Sessions many→few' : 'Sessions few→many')
                            : (_sortByProvider
                                ? (_sortAsc ? 'Provider Z→A' : 'Provider A→Z')
                                : (_sortById
                                    ? (_sortAsc ? 'Id Z→A' : 'Id A→Z')
                                    : (_sortByProject
                                        ? (_sortAsc ? 'Project Z→A' : 'Project A→Z')
                                        : (_sortByPlatform
                                            ? (_sortAsc ? 'Platform Z→A' : 'Platform A→Z')
                                            : (_sortByStatus
                                                ? (_sortAsc ? 'Status Z→A' : 'Status A→Z')
                                                : (_sortByModel
                                                    ? (_sortAsc ? 'Model Z→A' : 'Model A→Z')
                                                    : (_sortByType
                                                        ? (_sortAsc ? 'Type Z→A' : 'Type A→Z')
                                                        : (_sortAsc ? 'Name Z→A' : 'Name A→Z')))))))))))),
            onPressed: () {
              setState(() {
                if (!_sortByType && !_sortByModel && !_sortByStatus && !_sortByPlatform && !_sortByProject && !_sortById && !_sortByProvider && !_sortBySessions && !_sortByCwd && !_sortByNote && !_sortByCaps && !_sortByVersion && _sortAsc) {
                  _sortAsc = false;
                } else if (!_sortByType && !_sortByModel && !_sortByStatus && !_sortByPlatform && !_sortByProject && !_sortById && !_sortByProvider && !_sortBySessions && !_sortByCwd && !_sortByNote && !_sortByCaps && !_sortByVersion && !_sortAsc) {
                  _sortByType = true;
                  _sortByModel = false;
                  _sortByStatus = false;
                  _sortByPlatform = false;
                  _sortByProject = false;
                  _sortById = false;
                  _sortByProvider = false;
                  _sortBySessions = false;
                  _sortByCwd = false;
                  _sortByNote = false;
                  _sortByCaps = false;
                  _sortByVersion = false;
                  _sortAsc = true;
                } else if (_sortByType && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByType && !_sortAsc) {
                  _sortByType = false;
                  _sortByModel = true;
                  _sortByStatus = false;
                  _sortByPlatform = false;
                  _sortByProject = false;
                  _sortById = false;
                  _sortByProvider = false;
                  _sortBySessions = false;
                  _sortByCwd = false;
                  _sortByNote = false;
                  _sortByCaps = false;
                  _sortByVersion = false;
                  _sortAsc = true;
                } else if (_sortByModel && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByModel && !_sortAsc) {
                  _sortByType = false;
                  _sortByModel = false;
                  _sortByStatus = true;
                  _sortByPlatform = false;
                  _sortByProject = false;
                  _sortById = false;
                  _sortByProvider = false;
                  _sortBySessions = false;
                  _sortByCwd = false;
                  _sortByNote = false;
                  _sortByCaps = false;
                  _sortByVersion = false;
                  _sortAsc = true;
                } else if (_sortByStatus && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByStatus && !_sortAsc) {
                  _sortByType = false;
                  _sortByModel = false;
                  _sortByStatus = false;
                  _sortByPlatform = true;
                  _sortByProject = false;
                  _sortById = false;
                  _sortByProvider = false;
                  _sortBySessions = false;
                  _sortByCwd = false;
                  _sortByNote = false;
                  _sortByCaps = false;
                  _sortByVersion = false;
                  _sortAsc = true;
                } else if (_sortByPlatform && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByPlatform && !_sortAsc) {
                  _sortByType = false;
                  _sortByModel = false;
                  _sortByStatus = false;
                  _sortByPlatform = false;
                  _sortByProject = true;
                  _sortById = false;
                  _sortByProvider = false;
                  _sortBySessions = false;
                  _sortByCwd = false;
                  _sortByNote = false;
                  _sortByCaps = false;
                  _sortByVersion = false;
                  _sortAsc = true;
                } else if (_sortByProject && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByProject && !_sortAsc) {
                  _sortByType = false;
                  _sortByModel = false;
                  _sortByStatus = false;
                  _sortByPlatform = false;
                  _sortByProject = false;
                  _sortById = true;
                  _sortByProvider = false;
                  _sortBySessions = false;
                  _sortByCwd = false;
                  _sortByNote = false;
                  _sortByCaps = false;
                  _sortByVersion = false;
                  _sortAsc = true;
                } else if (_sortById && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortById && !_sortAsc) {
                  _sortByType = false;
                  _sortByModel = false;
                  _sortByStatus = false;
                  _sortByPlatform = false;
                  _sortByProject = false;
                  _sortById = false;
                  _sortByProvider = true;
                  _sortBySessions = false;
                  _sortByCwd = false;
                  _sortByNote = false;
                  _sortByCaps = false;
                  _sortByVersion = false;
                  _sortAsc = true;
                } else if (_sortByProvider && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByProvider && !_sortAsc) {
                  _sortByType = false;
                  _sortByModel = false;
                  _sortByStatus = false;
                  _sortByPlatform = false;
                  _sortByProject = false;
                  _sortById = false;
                  _sortByProvider = false;
                  _sortBySessions = true;
                  _sortByCwd = false;
                  _sortByNote = false;
                  _sortByCaps = false;
                  _sortByVersion = false;
                  _sortAsc = false; // many first
                } else if (_sortBySessions && !_sortAsc) {
                  _sortAsc = true;
                } else if (_sortBySessions && _sortAsc) {
                  _sortByType = false;
                  _sortByModel = false;
                  _sortByStatus = false;
                  _sortByPlatform = false;
                  _sortByProject = false;
                  _sortById = false;
                  _sortByProvider = false;
                  _sortBySessions = false;
                  _sortByCwd = true;
                  _sortByNote = false;
                  _sortByCaps = false;
                  _sortByVersion = false;
                  _sortAsc = true;
                } else if (_sortByCwd && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByCwd && !_sortAsc) {
                  _sortByType = false;
                  _sortByModel = false;
                  _sortByStatus = false;
                  _sortByPlatform = false;
                  _sortByProject = false;
                  _sortById = false;
                  _sortByProvider = false;
                  _sortBySessions = false;
                  _sortByCwd = false;
                  _sortByNote = true;
                  _sortByCaps = false;
                  _sortByVersion = false;
                  _sortAsc = true;
                } else if (_sortByNote && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByNote && !_sortAsc) {
                  _sortByType = false;
                  _sortByModel = false;
                  _sortByStatus = false;
                  _sortByPlatform = false;
                  _sortByProject = false;
                  _sortById = false;
                  _sortByProvider = false;
                  _sortBySessions = false;
                  _sortByCwd = false;
                  _sortByNote = false;
                  _sortByCaps = true;
                  _sortAsc = false; // many first
                } else if (_sortByCaps && !_sortAsc) {
                  _sortAsc = true;
                } else if (_sortByCaps && _sortAsc) {
                  _sortByType = false;
                  _sortByModel = false;
                  _sortByStatus = false;
                  _sortByPlatform = false;
                  _sortByProject = false;
                  _sortById = false;
                  _sortByProvider = false;
                  _sortBySessions = false;
                  _sortByCwd = false;
                  _sortByNote = false;
                  _sortByCaps = false;
                  _sortByVersion = true;
                  _sortAsc = true;
                } else if (_sortByVersion && _sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortByType = false;
                  _sortByModel = false;
                  _sortByStatus = false;
                  _sortByPlatform = false;
                  _sortByProject = false;
                  _sortById = false;
                  _sortByProvider = false;
                  _sortBySessions = false;
                  _sortByCwd = false;
                  _sortByNote = false;
                  _sortByCaps = false;
                  _sortByVersion = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(_sortByVersion
                ? Icons.numbers
                : (_sortByCaps
                    ? Icons.extension_outlined
                    : (_sortByNote
                    ? Icons.sticky_note_2_outlined
                    : (_sortByCwd
                        ? Icons.folder_outlined
                        : (_sortBySessions
                            ? Icons.forum_outlined
                            : (_sortByProvider
                                ? Icons.hub_outlined
                                : (_sortById
                                    ? Icons.tag
                                    : (_sortByProject
                                        ? Icons.folder_special_outlined
                                        : (_sortByPlatform
                                            ? Icons.devices_other_outlined
                                            : (_sortByStatus
                                                ? Icons.flag_outlined
                                                : (_sortByModel
                                                    ? Icons.memory_outlined
                                                    : (_sortByType
                                                        ? Icons.category_outlined
                                                        : (_sortAsc ? Icons.sort_by_alpha : Icons.sort))))))))))))),
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
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final f in const [
                  ('', 'Any adapter'),
                  ('mock', 'mock'),
                  ('hermes', 'hermes'),
                  ('claude', 'claude'),
                  ('codex', 'codex'),
                  ('other', 'other'),
                ])
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(f.$2, style: const TextStyle(fontSize: 11)),
                    selected: _adapter == f.$1,
                    onSelected: (_) => setState(() {
                      _adapter = (_adapter == f.$1) ? '' : f.$1;
                    }),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final f in const [
                  ('', 'Any model'),
                  ('gpt', 'gpt'),
                  ('claude', 'claude'),
                  ('codex', 'codex'),
                  ('gemini', 'gemini'),
                  ('other', 'other'),
                ])
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(f.$2, style: const TextStyle(fontSize: 11)),
                    selected: _model == f.$1,
                    onSelected: (_) => setState(() {
                      _model = (_model == f.$1) ? '' : f.$1;
                    }),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                hintText: _queryRegex
                    ? (_queryCase ? 'Filter (regex · case)' : 'Filter (regex)')
                    : (_queryCase ? 'Filter (case-sensitive)' : 'Filter agents / platforms / projects'),
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
                    size: 18,
                  ),
                  onPressed: () => setState(() => _queryCase = !_queryCase),
                  onLongPress: () => setState(() => _queryRegex = !_queryRegex),
                ),
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
                            maxLines: _wrapLines ? 10 : 3,
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
