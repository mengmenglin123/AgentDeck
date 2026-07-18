import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_controller.dart';
import '../services/audit_log.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, required this.audit});

  final AuditLog audit;

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final _q = TextEditingController();
  String _query = '';
  bool _queryCase = false;
  /// all | info | warn | error
  String _level = 'all';
  bool _newestFirst = true;
  bool _sortByAction = false;
  bool _sortByLevel = false;
  bool _sortByDetail = false;
  bool _sortAsc = true;
  bool _wrapLines = false;
  bool _relativeTs = false;
  final _scroll = ScrollController();
  Timer? _timer;
  bool _autoRefresh = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _armTimer());
  }

  void _armTimer() {
    _timer?.cancel();
    if (!_autoRefresh || !mounted) return;
    final sec = context.read<AppSettingsController>().dashboardRefreshSec;
    if (sec <= 0) return;
    _timer = Timer.periodic(Duration(seconds: sec), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _q.dispose();
    super.dispose();
  }

  List<AuditEntry> _ordered(List<AuditEntry> all) {
    final items = List<AuditEntry>.from(all);
.sort((a, b) {
      if (_sortByDetail) {
        final c = a.detail.toLowerCase().compareTo(b.detail.toLowerCase());
        if (c != 0) return _sortAsc ? c : -c;
        final ca = a.action.toLowerCase().compareTo(b.action.toLowerCase());
        if (ca != 0) return _sortAsc ? ca : -ca;
      } else if (_sortByLevel) {
        final c = a.level.toLowerCase().compareTo(b.level.toLowerCase());
        if (c != 0) return _sortAsc ? c : -c;
        final ca = a.action.toLowerCase().compareTo(b.action.toLowerCase());
        if (ca != 0) return _sortAsc ? ca : -ca;
      } else if (_sortByAction) {
        final c = a.action.toLowerCase().compareTo(b.action.toLowerCase());
        if (c != 0) return _sortAsc ? c : -c;
      }
      final c = a.ts.compareTo(b.ts);
      return _newestFirst ? -c : c;
    });
    return items;
  }

  _filter(List<AuditEntry> all) {
    Iterable<AuditEntry> it = all;
    if (_level != 'all') {
      it = it.where((e) => e.level == _level);
    }
    final rawQ = _query.trim();
    final q = _queryCase ? rawQ : rawQ.toLowerCase();
    if (q.isNotEmpty) {
      it = it.where((e) {
        final hayRaw = '${e.action} ${e.detail} ${e.level}';
        final hay = _queryCase ? hayRaw : hayRaw.toLowerCase();
        return hay.contains(q);
      });
    }
    return it.toList();
  }


  String _fmtAuditTs(DateTime ts) {
    if (!_relativeTs) {
      return ts.toLocal().toIso8601String().substring(11, 19);
    }
    final d = DateTime.now().difference(ts.toLocal());
    if (d.isNegative) return ts.toLocal().toIso8601String().substring(11, 19);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 48) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final audit = widget.audit;
    final visible = _ordered(_filter(audit.entries));
    final total = audit.entries.length;
    final title = total == 0
        ? 'Audit log'
        : (visible.length == total
            ? 'Audit ($total)'
            : 'Audit (${visible.length}/$total)');
    return Scaffold(
      appBar: AppBar(
        title: Text(_autoRefresh ? '$title · auto' : title),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            onPressed: () async {
              final items = _ordered(_filter(audit.entries));
              final buf = StringBuffer();
              for (final e in items) {
                buf.writeln('${e.ts.toIso8601String()} [${e.level}] ${e.action} ${e.detail}');
              }
              await Clipboard.setData(ClipboardData(text: buf.toString()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied ${items.length} lines'), duration: const Duration(seconds: 1)),
                );
              }
            },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Copy JSON',
            onPressed: () async {
              final items = _ordered(_filter(audit.entries));
              final payload = {
                'exported_at': DateTime.now().toIso8601String(),
                'count': items.length,
                'entries': [
                  for (final e in items)
                    {
                      'ts': e.ts.toIso8601String(),
                      'level': e.level,
                      'action': e.action,
                      'detail': e.detail,
                    },
                ],
              };
              final text = const JsonEncoder.withIndent('  ').convert(payload);
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied JSON (${items.length})'), duration: const Duration(seconds: 1)),
                );
              }
            },
            icon: const Icon(Icons.data_object),
          ),
          IconButton(
            tooltip: 'Copy CSV',
            onPressed: () async {
              final items = _ordered(_filter(audit.entries));
              final buf = StringBuffer();
              buf.writeln('ts,level,action,detail');
              for (final e in items) {
                final action = e.action.replaceAll(',', ';');
                final detail = e.detail.replaceAll(',', ';').replaceAll('\n', ' ');
                buf.writeln(
                  e.ts.toIso8601String() +
                      ',' +
                      e.level +
                      ',' +
                      action +
                      ',' +
                      detail,
                );
              }
              await Clipboard.setData(ClipboardData(text: buf.toString()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied CSV (' + items.length.toString() + ')'),
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
            icon: Icon(_newestFirst ? Icons.south : Icons.north),
          ),
          IconButton(
            tooltip: _sortByDetail
                ? (_sortAsc ? 'Details Z→A' : 'Details A→Z')
                : (_sortByLevel
                    ? (_sortAsc ? 'Levels Z→A' : 'Levels A→Z')
                    : (_sortByAction
                        ? (_sortAsc ? 'Actions Z→A' : 'Actions A→Z')
                        : 'Sort by action / level / detail')),
            onPressed: () {
              setState(() {
                if (!_sortByAction && !_sortByLevel && !_sortByDetail) {
                  _sortByAction = true;
                  _sortByLevel = false;
                  _sortByDetail = false;
                  _sortAsc = true;
                } else if (_sortByAction && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByAction && !_sortAsc) {
                  _sortByAction = false;
                  _sortByLevel = true;
                  _sortByDetail = false;
                  _sortAsc = true;
                } else if (_sortByLevel && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByLevel && !_sortAsc) {
                  _sortByAction = false;
                  _sortByLevel = false;
                  _sortByDetail = true;
                  _sortAsc = true;
                } else if (_sortByDetail && _sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortByAction = false;
                  _sortByLevel = false;
                  _sortByDetail = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(_sortByDetail
                ? Icons.notes
                : (_sortByLevel
                    ? Icons.low_priority
                    : (_sortByAction ? Icons.sort_by_alpha : Icons.sort))),
          ),

          IconButton(
            tooltip: _wrapLines ? 'Clamp details' : 'Wrap details',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.horizontal_rule),
          ),
          IconButton(
            tooltip: _relativeTs ? 'Absolute timestamps' : 'Relative timestamps',
            onPressed: () => setState(() => _relativeTs = !_relativeTs),
            icon: Icon(_relativeTs ? Icons.schedule : Icons.access_time),
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


          IconButton(
            tooltip: 'Clear',
            onPressed: audit.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                hintText: _queryCase ? 'Filter (case-sensitive)' : 'Filter action / detail',
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: IconButton(
                  tooltip: _queryCase ? 'Case-sensitive on' : 'Case-insensitive',
                  icon: Icon(
                    _queryCase ? Icons.text_fields : Icons.search,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _queryCase = !_queryCase),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in const [
                  ('all', 'All'),
                  ('info', 'Info'),
                  ('warn', 'Warn'),
                  ('error', 'Error'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                    selected: _level == f.$1,
                    onSelected: (_) => setState(() => _level = f.$1),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: audit,
              builder: (context, _) {
                final items = _ordered(_filter(audit.entries));
                if (audit.entries.isEmpty) {
                  return const Center(child: Text('No audit events yet.'));
                }
                if (items.isEmpty) {
                  return const Center(child: Text('No events match filter'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                    await Future<void>.delayed(const Duration(milliseconds: 200));
                  },
                  child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                      controller: _scroll,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = items[i];
                    final color = e.level == 'error'
                        ? Colors.red
                        : e.level == 'warn'
                            ? Colors.orange
                            : null;
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.circle, size: 10, color: color ?? Colors.green),
                      title: Text(e.action),
                      subtitle: Text(
                        '${_fmtAuditTs(e.ts)}  ${e.detail}',
                        maxLines: _wrapLines ? 12 : 3,
                        overflow: _wrapLines ? TextOverflow.visible : TextOverflow.ellipsis,
                      ),
                      onLongPress: () async {
                        await Clipboard.setData(
                          ClipboardData(text: '${e.ts.toIso8601String()} [${e.level}] ${e.action} ${e.detail}'),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Entry copied'), duration: Duration(seconds: 1)),
                          );
                        }
                      },
                    );
                  },
                ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
