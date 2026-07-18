import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/app_settings_controller.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';

/// Readonly Host memory catalog (`GET /memory`) — Host is source of truth.
/// Inspired by remote-console memory browsers; not a local agent memory engine.
class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key, required this.config});

  final ConnectionConfig config;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  late final MgmtClient _mgmt = MgmtClient(config: widget.config);
  bool _loading = true;
  String? _error;
  String _scope = 'all';
  String _type = 'all';
  String _q = '';
  bool _wrapLines = false;
  bool _queryCase = false;
  bool _queryRegex = false;
  bool _sortByTitle = false;
  bool _sortByType = false;
  bool _sortByContent = false;
  bool _sortByConfidence = false;
  bool _sortByScope = false;
  bool _sortById = false;
  bool _sortAsc = true;
  bool _relativeTs = false;
  bool _newestFirst = true;
  final _scroll = ScrollController();
  Timer? _timer;
  bool _autoRefresh = false;
  List<Map<String, dynamic>> _items = [];
  final _search = TextEditingController();

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
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _visible {
    final rawQ = _search.text.trim();
    final q = _queryCase ? rawQ : rawQ.toLowerCase();
    final list = _items.where((m) {
      if (_type != 'all') {
        final t = (m['type'] ?? '').toString().toLowerCase();
        if (_type == 'other') {
          final known = t.contains('note') ||
              t.contains('fact') ||
              t.contains('pref') ||
              t.contains('rule') ||
              t.contains('snippet') ||
              t.contains('doc');
          if (known) return false;
        } else if (!t.contains(_type)) {
          return false;
        }
      }
      if (rawQ.isEmpty) return true;
      final hayRaw = '${m['title']} ${m['id']} ${m['content']} ${m['scope']} ${m['type']}';
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
    int tsOf(Map<String, dynamic> m) {
      final v = m['updated_at'] ?? m['created_at'] ?? m['ts'] ?? m['time'];
      if (v is num) {
        final n = v.toDouble();
        return n > 1e12 ? n.round() : (n * 1000).round();
      }
      final p = DateTime.tryParse(v?.toString() ?? '');
      return p?.millisecondsSinceEpoch ?? 0;
    }
    list.sort((a, b) {
      double confOf(Map x) {
        final v = x['confidence'] ?? x['score'] ?? x['weight'];
        if (v is num) return v.toDouble();
        return double.tryParse(v?.toString() ?? '') ?? -1;
      }
      if (_sortById) {
        final ia = (a['id'] ?? a['memory_id'] ?? a['uuid'] ?? a['key'] ?? '').toString().toLowerCase();
        final ib = (b['id'] ?? b['memory_id'] ?? b['uuid'] ?? b['key'] ?? '').toString().toLowerCase();
        final c = ia.compareTo(ib);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByScope) {
        final sa = (a['scope'] ?? '').toString().toLowerCase();
        final sb = (b['scope'] ?? '').toString().toLowerCase();
        final c = sa.compareTo(sb);
        if (c != 0) return _sortAsc ? c : -c;
        final na = (a['title'] ?? a['id'] ?? '').toString().toLowerCase();
        final nb = (b['title'] ?? b['id'] ?? '').toString().toLowerCase();
        final cn = na.compareTo(nb);
        if (cn != 0) return _sortAsc ? cn : -cn;
      } else if (_sortByConfidence) {
        final c = confOf(a).compareTo(confOf(b));
        if (c != 0) return _sortAsc ? c : -c;
        final na = (a['title'] ?? a['id'] ?? '').toString().toLowerCase();
        final nb = (b['title'] ?? b['id'] ?? '').toString().toLowerCase();
        final cn = na.compareTo(nb);
        if (cn != 0) return _sortAsc ? cn : -cn;
      } else if (_sortByContent) {
        final ca = (a['content'] ?? a['text'] ?? a['body'] ?? '').toString().toLowerCase();
        final cb = (b['content'] ?? b['text'] ?? b['body'] ?? '').toString().toLowerCase();
        final c = ca.compareTo(cb);
        if (c != 0) return _sortAsc ? c : -c;
        final na = (a['title'] ?? a['id'] ?? '').toString().toLowerCase();
        final nb = (b['title'] ?? b['id'] ?? '').toString().toLowerCase();
        final cn = na.compareTo(nb);
        if (cn != 0) return _sortAsc ? cn : -cn;
      } else if (_sortByType) {
        final ta = (a['type'] ?? '').toString().toLowerCase();
        final tb = (b['type'] ?? '').toString().toLowerCase();
        final c = ta.compareTo(tb);
        if (c != 0) return _sortAsc ? c : -c;
        final na = (a['title'] ?? a['id'] ?? '').toString().toLowerCase();
        final nb = (b['title'] ?? b['id'] ?? '').toString().toLowerCase();
        final cn = na.compareTo(nb);
        if (cn != 0) return _sortAsc ? cn : -cn;
      } else if (_sortByTitle) {
        final ta = (a['title'] ?? a['id'] ?? '').toString().toLowerCase();
        final tb = (b['title'] ?? b['id'] ?? '').toString().toLowerCase();
        final c = ta.compareTo(tb);
        return _sortAsc ? c : -c;
      }
      final c = tsOf(a).compareTo(tsOf(b));
      return _newestFirst ? -c : c;
    });
    return list;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _mgmt.listMemory(
        scope: _scope == 'all' ? null : _scope,
        q: _q.isEmpty ? null : _q,
      );
      final raw = data['memories'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = Security.redactText(e.toString());
      });
    }
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


  String _fmtMemTs(Map m) {
    final v = m['updated_at'] ?? m['created_at'] ?? m['ts'] ?? m['time'];
    DateTime? dt;
    if (v is num) {
      final n = v.toDouble();
      final ms = n > 1e12 ? n.round() : (n * 1000).round();
      dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    } else {
      dt = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
    }
    if (dt == null) return '';
    if (!_relativeTs) {
      return dt.toIso8601String().replaceFirst('T', ' ').substring(0, 19);
    }
    final d = DateTime.now().difference(dt);
    if (d.isNegative) {
      return dt.toIso8601String().replaceFirst('T', ' ').substring(0, 19);
    }
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 48) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _visible.isEmpty
              ? 'Host memory'
              : (_visible.length == _items.length
                  ? 'Host memory (${_visible.length})'
                  : 'Host memory (${_visible.length}/${_items.length})'),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            onPressed: _visible.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    for (final m in _visible) {
                      final title = (m['title'] ?? m['id'] ?? 'memory').toString();
                      final content = (m['content'] ?? '').toString();
                      final scope = (m['scope'] ?? '').toString();
                      final type = (m['type'] ?? '').toString();
                      buf.writeln('## $title');
                      buf.writeln('scope: $scope · type: $type');
                      buf.writeln(content);
                      buf.writeln();
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied ${_visible.length} memories'), duration: const Duration(seconds: 1)),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Copy CSV',
            onPressed: _visible.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    buf.writeln('id,title,scope,type,content');
                    for (final m in _visible) {
                      final id = (m['id'] ?? '').toString().replaceAll(',', ';');
                      final title = (m['title'] ?? '').toString().replaceAll(',', ';');
                      final scope = (m['scope'] ?? '').toString().replaceAll(',', ';');
                      final type = (m['type'] ?? '').toString().replaceAll(',', ';');
                      final content = (m['content'] ?? '')
                          .toString()
                          .replaceAll(',', ';')
                          .replaceAll('\n', ' ');
                      buf.writeln('$id,$title,$scope,$type,$content');
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied CSV (${_visible.length})'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: _newestFirst ? 'Oldest first' : 'Newest first',
            onPressed: () => setState(() => _newestFirst = !_newestFirst),
            icon: Icon(_newestFirst ? Icons.arrow_downward : Icons.arrow_upward),
          ),
          IconButton(
            tooltip: _relativeTs ? 'Absolute timestamps' : 'Relative timestamps',
            onPressed: () => setState(() => _relativeTs = !_relativeTs),
            icon: Icon(_relativeTs ? Icons.schedule : Icons.access_time),
          ),
          IconButton(
            tooltip: _sortById
                ? (_sortAsc ? 'Id Z→A' : 'Id A→Z')
                : (_sortByScope
                    ? (_sortAsc ? 'Scope Z→A' : 'Scope A→Z')
                    : (_sortByConfidence
                        ? (_sortAsc ? 'Confidence high→low' : 'Confidence low→high')
                        : (_sortByContent
                            ? (_sortAsc ? 'Content Z→A' : 'Content A→Z')
                            : (_sortByType
                                ? (_sortAsc ? 'Types Z→A' : 'Types A→Z')
                                : (_sortByTitle
                                    ? (_sortAsc ? 'Titles Z→A' : 'Titles A→Z')
                                    : 'Sort by title / type / content / confidence / scope / id'))))),
            onPressed: () {
              setState(() {
                if (!_sortByTitle && !_sortByType && !_sortByContent && !_sortByConfidence && !_sortByScope && !_sortById) {
                  _sortByTitle = true;
                  _sortByType = false;
                  _sortByContent = false;
                  _sortByConfidence = false;
                  _sortByScope = false;
                  _sortById = false;
                  _sortAsc = true;
                } else if (_sortByTitle && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByTitle && !_sortAsc) {
                  _sortByTitle = false;
                  _sortByType = true;
                  _sortByContent = false;
                  _sortByConfidence = false;
                  _sortByScope = false;
                  _sortById = false;
                  _sortAsc = true;
                } else if (_sortByType && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByType && !_sortAsc) {
                  _sortByTitle = false;
                  _sortByType = false;
                  _sortByContent = true;
                  _sortByConfidence = false;
                  _sortByScope = false;
                  _sortById = false;
                  _sortAsc = true;
                } else if (_sortByContent && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByContent && !_sortAsc) {
                  _sortByTitle = false;
                  _sortByType = false;
                  _sortByContent = false;
                  _sortByConfidence = true;
                  _sortByScope = false;
                  _sortById = false;
                  _sortAsc = false; // high first by default
                } else if (_sortByConfidence && !_sortAsc) {
                  _sortAsc = true;
                } else if (_sortByConfidence && _sortAsc) {
                  _sortByTitle = false;
                  _sortByType = false;
                  _sortByContent = false;
                  _sortByConfidence = false;
                  _sortByScope = true;
                  _sortById = false;
                  _sortAsc = true;
                } else if (_sortByScope && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByScope && !_sortAsc) {
                  _sortByTitle = false;
                  _sortByType = false;
                  _sortByContent = false;
                  _sortByConfidence = false;
                  _sortByScope = false;
                  _sortById = true;
                  _sortAsc = true;
                } else if (_sortById && _sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortByTitle = false;
                  _sortByType = false;
                  _sortByContent = false;
                  _sortByConfidence = false;
                  _sortByScope = false;
                  _sortById = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(_sortById
                ? Icons.tag
                : (_sortByScope
                    ? Icons.folder_outlined
                    : (_sortByConfidence
                        ? Icons.speed
                        : (_sortByContent
                            ? Icons.article_outlined
                            : (_sortByType
                                ? Icons.category_outlined
                                : (_sortByTitle ? Icons.sort_by_alpha : Icons.sort)))))),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in const [
                  ('all', 'All'),
                  ('global', 'Global'),
                  ('project', 'Project'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                    selected: _scope == f.$1,
                    onSelected: (_) {
                      setState(() => _scope = f.$1);
                      _load();
                    },
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in const [
                  ('all', 'All types'),
                  ('note', 'Note'),
                  ('fact', 'Fact'),
                  ('pref', 'Pref'),
                  ('rule', 'Rule'),
                  ('snippet', 'Snippet'),
                  ('doc', 'Doc'),
                  ('other', 'Other'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                    selected: _type == f.$1,
                    onSelected: (_) => setState(() => _type = f.$1),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: _queryRegex
                    ? (_queryCase ? 'Search (regex · case)' : 'Search (regex)')
                    : (_queryCase ? 'Search (case-sensitive)' : 'Search title/content'),
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: IconButton(
                  tooltip: _queryRegex
                      ? (_queryCase
                          ? 'Regex · case on (long-press: plain search)'
                          : 'Regex · case off (long-press: plain search)')
                      : (_queryCase
                          ? 'Case-sensitive (long-press: regex)'
                          : 'Case-insensitive (long-press: regex)'),
                  icon: Icon(
                    _queryRegex
                        ? Icons.code
                        : (_queryCase ? Icons.text_fields : Icons.search),
                    size: 20,
                  ),
                  onPressed: () => setState(() => _queryCase = !_queryCase),
                  onLongPress: () => setState(() => _queryRegex = !_queryRegex),
                ),
                suffixIcon: _search.text.isEmpty
                    ? IconButton(
                        icon: const Icon(Icons.manage_search),
                        tooltip: 'Search host',
                        onPressed: () {
                          setState(() => _q = _search.text.trim());
                          _load();
                        },
                      )
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() {
                            _q = '';
                          });
                          _load();
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) {
                setState(() => _q = v.trim());
                _load();
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _items.isEmpty && !_loading
                ? const Center(child: Text('No memories (Host may not expose /memory)'))
                : _visible.isEmpty && !_loading
                    ? const Center(child: Text('No memories match filter'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _visible.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final m = _visible[i];
                        final title = (m['title'] ?? m['id'] ?? 'memory').toString();
                        final content = (m['content'] ?? '').toString();
                        final scope = (m['scope'] ?? '').toString();
                        final type = (m['type'] ?? '').toString();
                        final conf = (m['confidence'] ?? '').toString();
                        final full = '# $title\n\nscope: $scope\ntype: $type\nconfidence: $conf\n\n$content';
                        return ListTile(
                          leading: Icon(
                            scope == 'project' ? Icons.folder_special_outlined : Icons.psychology_outlined,
                          ),
                          title: Text(title),
                          subtitle: Text(
                            '[$scope/$type${conf.isNotEmpty ? ' · $conf' : ''}${_fmtMemTs(m).isNotEmpty ? ' · ${_fmtMemTs(m)}' : ''}]\n'
                            '${_wrapLines ? content : (content.length > 160 ? '${content.substring(0, 160)}…' : content)}',
                            maxLines: _wrapLines ? 12 : 4,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'Copy',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: full));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Memory copied'), duration: Duration(seconds: 1)),
                                );
                              }
                            },
                          ),
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => Padding(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                                child: SingleChildScrollView(
                                  child: SelectableText(full),
                                ),
                              ),
                            );
                          },
                          onLongPress: () async {
                            await Clipboard.setData(ClipboardData(text: full));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Memory copied'), duration: Duration(seconds: 1)),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
