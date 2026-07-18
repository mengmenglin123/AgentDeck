import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/app_settings_controller.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key, required this.config});
  final ConnectionConfig config;

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> skills = [];
  final _q = TextEditingController();
  String _query = '';
  bool _queryCase = false;
  bool _queryRegex = false;
  String _source = '';
  bool _wrapLines = false;
  bool _sortBySource = false;
  bool _sortByDesc = false;
  bool _sortById = false;
  bool _sortByTags = false;
  bool _sortByPath = false;
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
      loading = true;
      error = null;
    });
    try {
      final list = await MgmtClient(config: widget.config).listSkills();
      setState(() {
        skills = list;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = Security.redactText(e.toString());
        loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final rawQ = _query.trim();
    final q = _queryCase ? rawQ : rawQ.toLowerCase();
    final list = skills.where((s) {
      final src = (s['source'] ?? '').toString().toLowerCase();
      if (_source.isNotEmpty) {
        if (_source == 'other') {
          final known = src.contains('builtin') ||
              src.contains('built-in') ||
              src.contains('user') ||
              src.contains('project') ||
              src.contains('plugin') ||
              src.contains('host');
          if (known) return false;
        } else if (!src.contains(_source)) {
          return false;
        }
      }
      if (rawQ.isEmpty) return true;
      final tags = s['tags'] is List
          ? (s['tags'] as List).join(' ')
          : (s['tags'] ?? s['labels'] ?? '');
      final hayRaw =
          '${s['name']} ${s['description']} ${s['source']} ${s['id']} ${s['path']} $tags';
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
      String tagsOf(Map x) {
        final t = x['tags'] ?? x['labels'] ?? x['categories'];
        if (t is List) return t.map((e) => '$e').join(' ').toLowerCase();
        return (t ?? '').toString().toLowerCase();
      }
      if (_sortByPath) {
        final pa = (a['path'] ?? a['file'] ?? a['slug'] ?? '').toString().toLowerCase();
        final pb = (b['path'] ?? b['file'] ?? b['slug'] ?? '').toString().toLowerCase();
        final c = pa.compareTo(pb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByTags) {
        final c = tagsOf(a).compareTo(tagsOf(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortById) {
        final ia = (a['id'] ?? a['slug'] ?? a['name'] ?? '').toString().toLowerCase();
        final ib = (b['id'] ?? b['slug'] ?? b['name'] ?? '').toString().toLowerCase();
        final c = ia.compareTo(ib);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByDesc) {
        final da = (a['description'] ?? a['summary'] ?? '').toString().toLowerCase();
        final db = (b['description'] ?? b['summary'] ?? '').toString().toLowerCase();
        final c = da.compareTo(db);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortBySource) {
        final sa = (a['source'] ?? '').toString().toLowerCase();
        final sb = (b['source'] ?? '').toString().toLowerCase();
        final c = sa.compareTo(sb);
        if (c != 0) return _sortAsc ? c : -c;
      }
      final na = (a['name'] ?? a['id'] ?? '').toString().toLowerCase();
      final nb = (b['name'] ?? b['id'] ?? '').toString().toLowerCase();
      final c = na.compareTo(nb);
      return _sortAsc ? c : -c;
    });
    return list;
  }

  void _armTimer() {
    _timer?.cancel();
    if (!_autoRefresh || !mounted) return;
    final sec = context.read<AppSettingsController>().dashboardRefreshSec;
    if (sec <= 0) return;
    _timer = Timer.periodic(Duration(seconds: sec), (_) {
      if (!mounted || loading) return;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          items.isEmpty
              ? 'Skills (readonly)'
              : (items.length == skills.length
                  ? 'Skills (${items.length})'
                  : 'Skills (${items.length}/${skills.length})'),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            onPressed: items.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    for (final s in items) {
                      if (s is Map) {
                        final name = (s['name'] ?? s['id'] ?? 'skill').toString();
                        final desc = (s['description'] ?? s['summary'] ?? '').toString();
                        buf.writeln('## $name');
                        if (desc.isNotEmpty) buf.writeln(desc);
                        buf.writeln();
                      } else {
                        buf.writeln('$s');
                      }
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied ${items.length} skills'), duration: const Duration(seconds: 1)),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Copy CSV',
            onPressed: items.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    buf.writeln('name,source,description');
                    for (final s in items) {
                      if (s is Map) {
                        final name = (s['name'] ?? s['id'] ?? 'skill').toString().replaceAll(',', ';');
                        final source = (s['source'] ?? '').toString().replaceAll(',', ';');
                        final desc = (s['description'] ?? s['summary'] ?? '')
                            .toString()
                            .replaceAll(',', ';')
                            .replaceAll('\n', ' ');
                        buf.writeln('$name,$source,$desc');
                      } else {
                        buf.writeln('${'$s'.replaceAll(',', ';')},,');
                      }
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied CSV (${items.length})'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: _sortByPath
                ? (_sortAsc ? 'Path Z→A' : 'Path A→Z')
                : (_sortByTags
                    ? (_sortAsc ? 'Tags Z→A' : 'Tags A→Z')
                    : (_sortById
                        ? (_sortAsc ? 'Id Z→A' : 'Id A→Z')
                        : (_sortByDesc
                            ? (_sortAsc ? 'Description Z→A' : 'Description A→Z')
                            : (_sortBySource
                                ? (_sortAsc ? 'Source Z→A' : 'Source A→Z')
                                : (_sortAsc ? 'Name Z→A' : 'Name A→Z'))))),
            onPressed: () {
              setState(() {
                if (!_sortBySource && !_sortByDesc && !_sortById && !_sortByTags && !_sortByPath && _sortAsc) {
                  _sortAsc = false;
                } else if (!_sortBySource && !_sortByDesc && !_sortById && !_sortByTags && !_sortByPath && !_sortAsc) {
                  _sortBySource = true;
                  _sortByDesc = false;
                  _sortById = false;
                  _sortByTags = false;
                  _sortByPath = false;
                  _sortAsc = true;
                } else if (_sortBySource && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortBySource && !_sortAsc) {
                  _sortBySource = false;
                  _sortByDesc = true;
                  _sortById = false;
                  _sortByTags = false;
                  _sortByPath = false;
                  _sortAsc = true;
                } else if (_sortByDesc && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByDesc && !_sortAsc) {
                  _sortBySource = false;
                  _sortByDesc = false;
                  _sortById = true;
                  _sortByTags = false;
                  _sortByPath = false;
                  _sortAsc = true;
                } else if (_sortById && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortById && !_sortAsc) {
                  _sortBySource = false;
                  _sortByDesc = false;
                  _sortById = false;
                  _sortByTags = true;
                  _sortByPath = false;
                  _sortAsc = true;
                } else if (_sortByTags && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByTags && !_sortAsc) {
                  _sortBySource = false;
                  _sortByDesc = false;
                  _sortById = false;
                  _sortByTags = false;
                  _sortByPath = true;
                  _sortAsc = true;
                } else if (_sortByPath && _sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortBySource = false;
                  _sortByDesc = false;
                  _sortById = false;
                  _sortByTags = false;
                  _sortByPath = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(_sortByPath
                ? Icons.folder_open
                : (_sortByTags
                    ? Icons.sell_outlined
                    : (_sortById
                        ? Icons.tag
                        : (_sortByDesc
                            ? Icons.notes
                            : (_sortBySource
                                ? Icons.source_outlined
                                : (_sortAsc ? Icons.sort_by_alpha : Icons.sort)))))),
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


          IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final f in const [
                            ('', 'All'),
                            ('builtin', 'Builtin'),
                            ('user', 'User'),
                            ('project', 'Project'),
                            ('plugin', 'Plugin'),
                            ('host', 'Host'),
                            ('other', 'Other'),
                          ])
                            FilterChip(
                              label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                              selected: _source == f.$1,
                              onSelected: (_) => setState(() => _source = f.$1),
                              visualDensity: VisualDensity.compact,
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
                              : (_queryCase ? 'Filter (case-sensitive)' : 'Filter name / description / source'),
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
                    Expanded(
                      child: skills.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Host has no GET /skills (or empty).\nMock Host returns sample skills.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : items.isEmpty
                              ? const Center(child: Text('No skills match filter'))
                              : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      controller: _scroll,
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (context, i) {
                                    final s = items[i];
                                    final name = (s['name'] ?? 'skill').toString();
                                    final desc = (s['description'] ?? '').toString();
                                    final source = (s['source'] ?? '').toString();
                                    return ListTile(
                                      leading: const Icon(Icons.extension),
                                      title: Text(name),
                                      subtitle: Text(
                                        [if (desc.isNotEmpty) desc, if (source.isNotEmpty) source].join('\n'),
                                        maxLines: _wrapLines ? 8 : 2,
                                        overflow: TextOverflow.ellipsis,
                                        softWrap: true,
                                      ),
                                      isThreeLine: desc.isNotEmpty && source.isNotEmpty,
                                      trailing: IconButton(
                                        tooltip: 'Copy',
                                        icon: const Icon(Icons.copy, size: 18),
                                        onPressed: () async {
                                          await Clipboard.setData(
                                            ClipboardData(text: '$name\n$desc\n$source'.trim()),
                                          );
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Skill copied'),
                                                duration: Duration(seconds: 1),
                                              ),
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
