import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/app_settings_controller.dart';
import '../models/session_info.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';
import 'chat_screen.dart';

/// Readonly Host activity feed (`GET /activity`).
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({
    super.key,
    required this.config,
    this.sessions = const [],
  });

  final ConnectionConfig config;
  /// Optional known sessions for open-chat jump.
  final List<SessionInfo> sessions;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late final MgmtClient _mgmt = MgmtClient(config: widget.config);
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];
  String _query = '';
  String _kind = '';
  bool _wrapLines = false;
  bool _newestFirst = true;
  bool _sortByKind = false;
  bool _sortAsc = true;
  Timer? _timer;
  bool _autoRefresh = false;
  final _scroll = ScrollController();
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _armTimer());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _timer?.cancel();
    _q.dispose();
    super.dispose();
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _mgmt.listActivity(limit: 80);
      final raw = data['events'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      setState(() {
        _events = list;
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

  IconData _icon(String kind) {
    if (kind.contains('session')) return Icons.forum_outlined;
    if (kind.contains('chat') || kind.contains('message')) return Icons.chat_bubble_outline;
    if (kind.contains('host')) return Icons.dns_outlined;
    if (kind.contains('cron')) return Icons.schedule;
    return Icons.bolt_outlined;
  }

  String? _sessionRef(Map<String, dynamic> e) {
    for (final k in const ['session_key', 'sessionKey', 'session_id', 'sessionId', 'id']) {
      final v = e[k]?.toString().trim();
      if (v != null && v.isNotEmpty && (k.contains('session') || v.contains(':'))) {
        return v;
      }
    }
    // summary may embed session key/id
    final summary = (e['summary'] ?? '').toString();
    final m = RegExp(r'(huan:[^\s]+|sess-[a-zA-Z0-9_-]+|[a-f0-9]{8,})').firstMatch(summary);
    return m?.group(1);
  }

  SessionInfo? _resolveSession(String ref) {
    for (final s in widget.sessions) {
      if (s.sessionKey == ref || s.id == ref) return s;
      if (s.sessionKey.endsWith(ref) || s.id.endsWith(ref)) return s;
    }
    return null;
  }

  Future<void> _openSession(Map<String, dynamic> e) async {
    final ref = _sessionRef(e);
    if (ref == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No session reference on this event')),
      );
      return;
    }
    final hit = _resolveSession(ref);
    if (hit == null) {
      await Clipboard.setData(ClipboardData(text: ref));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session not in list — copied ref: $ref')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(config: widget.config, session: hit),
      ),
    );
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = _events.where((e) {
      final kind = (e['kind'] ?? e['type'] ?? 'event').toString().toLowerCase();
      if (_kind.isNotEmpty) {
        if (_kind == 'other') {
          final known = kind.contains('session') ||
              kind.contains('chat') ||
              kind.contains('message') ||
              kind.contains('host') ||
              kind.contains('cron');
          if (known) return false;
        } else if (!kind.contains(_kind)) {
          return false;
        }
      }
      if (q.isEmpty) return true;
      final hay =
          '${e['kind']} ${e['type']} ${e['summary']} ${e['message']} ${e['session_key']} ${e['session_id']}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();
    int tsOf(Map<String, dynamic> e) {
      final v = e['ts'] ?? e['time'] ?? e['timestamp'];
      if (v is num) return (v * 1000).round();
      final p = DateTime.tryParse(v?.toString() ?? '');
      return p?.millisecondsSinceEpoch ?? 0;
    }
    list.sort((a, b) {
      if (_sortByKind) {
        final ka = (a['kind'] ?? a['type'] ?? '').toString().toLowerCase();
        final kb = (b['kind'] ?? b['type'] ?? '').toString().toLowerCase();
        final ck = ka.compareTo(kb);
        if (ck != 0) return _sortAsc ? ck : -ck;
      }
      final c = tsOf(a).compareTo(tsOf(b));
      return _newestFirst ? -c : c;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          () {
            final base = items.isEmpty
                ? 'Host activity'
                : (_events.isEmpty || items.length == _events.length
                    ? 'Host activity (${items.length})'
                    : 'Host activity (${items.length}/${_events.length})');
            return _autoRefresh ? '$base · auto' : base;
          }(),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            onPressed: items.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    for (final e in items) {
                      final ts = e['ts'] ?? e['time'] ?? '';
                      final kind = e['type'] ?? e['kind'] ?? 'event';
                      final msg = e['message'] ?? e['summary'] ?? e['content'] ?? e;
                      final sk = e['session_key'] ?? e['session_id'] ?? '';
                      buf.writeln('[$ts] $kind  $msg  session=$sk');
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied ${items.length} events'), duration: const Duration(seconds: 1)),
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
                    buf.writeln('ts,kind,session,message');
                    for (final e in items) {
                      final ts = '${e['ts'] ?? e['time'] ?? ''}'.replaceAll(',', ';');
                      final kind = '${e['type'] ?? e['kind'] ?? 'event'}'.replaceAll(',', ';');
                      final sk = '${e['session_key'] ?? e['session_id'] ?? ''}'.replaceAll(',', ';');
                      final msg = '${e['message'] ?? e['summary'] ?? e['content'] ?? ''}'
                          .replaceAll(',', ';')
                          .replaceAll('\n', ' ');
                      buf.writeln('$ts,$kind,$sk,$msg');
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
            tooltip: _newestFirst ? 'Oldest first' : 'Newest first',
            onPressed: () => setState(() => _newestFirst = !_newestFirst),
            icon: Icon(_newestFirst ? Icons.arrow_downward : Icons.arrow_upward),
          ),
          IconButton(
            tooltip: _sortByKind
                ? (_sortAsc ? 'Kinds Z→A' : 'Kinds A→Z')
                : 'Sort by kind',
            onPressed: () {
              setState(() {
                if (!_sortByKind) {
                  _sortByKind = true;
                  _sortAsc = true;
                } else if (_sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortByKind = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(_sortByKind ? Icons.sort_by_alpha : Icons.category_outlined),
          ),

          IconButton(
            tooltip: _wrapLines ? 'Clamp details' : 'Wrap details',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
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
                  ('', 'All'),
                  ('session', 'Session'),
                  ('chat', 'Chat'),
                  ('host', 'Host'),
                  ('cron', 'Cron'),
                  ('other', 'Other'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                    selected: _kind == f.$1,
                    onSelected: (_) => setState(() => _kind = f.$1),
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
                hintText: 'Filter kind / summary / session',
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
            child: items.isEmpty && !_loading
                ? Center(
                    child: Text(
                      _events.isEmpty
                          ? 'No activity yet (Host may not expose /activity)'
                          : 'No events match filter',
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      controller: _scroll,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final e = items[i];
                      final kind = (e['kind'] ?? 'event').toString();
                      final summary = (e['summary'] ?? '').toString();
                      final ref = _sessionRef(e);
                      final resolvable = ref != null && _resolveSession(ref) != null;
                      return ListTile(
                        leading: Icon(_icon(kind)),
                        title: Text(
                          summary.isEmpty ? kind : summary,
                          maxLines: _wrapLines ? 8 : 2,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                        ),
                        subtitle: Text(
                          [
                            kind,
                            _fmtTs(e['ts']),
                            if (ref != null) ref,
                          ].join(' · '),
                        ),
                        dense: true,
                        trailing: ref == null
                            ? null
                            : Icon(
                                resolvable ? Icons.chat_outlined : Icons.copy_all_outlined,
                                size: 18,
                              ),
                        onTap: ref == null ? null : () => _openSession(e),
                        onLongPress: () async {
                          final text = '${e['kind']} ${e['summary']} ${e['session_key'] ?? e['session_id'] ?? ''}'.trim();
                          await Clipboard.setData(ClipboardData(text: text));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Event copied'), duration: Duration(seconds: 1)),
                            );
                          }
                        },
                      );
                    },
                  )),
          ),
        ],
      ),
    );
  }
}
