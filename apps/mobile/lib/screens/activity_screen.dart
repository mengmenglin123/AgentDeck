import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/app_settings_controller.dart';
import '../models/session_info.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';
import '../utils/catalog_ui.dart';
import '../utils/query_match.dart';
import 'chat_screen.dart';
import '../l10n/app_strings.dart';

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
  bool _queryCase = false;
  bool _queryRegex = false;
  String _kind = '';
  String _level = '';
  String _source = '';
  bool _wrapLines = false;
  bool _newestFirst = true;
  bool _sortByKind = false;
  bool _sortBySummary = false;
  bool _sortBySession = false;
  bool _sortBySource = false;
  bool _sortById = false;
  bool _sortByLevel = false;
  bool _sortByType = false;
  bool _sortByChannel = false;
  bool _sortByTs = false;
  bool _sortByPriority = false;
  bool _sortAsc = true;
  bool _relativeTs = false;
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
    _timer = CatalogUi.armAutoRefresh(
      context: context,
      current: _timer,
      enabled: _autoRefresh,
      isBusy: () => _loading,
      onTick: _load,
    );
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
    DateTime? dt;
    if (v is num) {
      final n = v.toDouble();
      final ms = n > 1e12 ? n.round() : (n * 1000).round();
      dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    } else {
      dt = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
    }
    if (dt == null) return v?.toString() ?? '—';
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

  IconData _icon(String kind) {
    if (kind.contains('session')) return Icons.forum_outlined;
    if (kind.contains('chat') || kind.contains('message'))
      return Icons.chat_bubble_outline;
    if (kind.contains('host')) return Icons.dns_outlined;
    if (kind.contains('cron')) return Icons.schedule;
    return Icons.bolt_outlined;
  }

  String? _sessionRef(Map<String, dynamic> e) {
    for (final k in const [
      'session_key',
      'sessionKey',
      'session_id',
      'sessionId',
      'id',
    ]) {
      final v = e[k]?.toString().trim();
      if (v != null &&
          v.isNotEmpty &&
          (k.contains('session') || v.contains(':'))) {
        return v;
      }
    }
    // summary may embed session key/id
    final summary = (e['summary'] ?? '').toString();
    final m = RegExp(
      r'(huan:[^\s]+|sess-[a-zA-Z0-9_-]+|[a-f0-9]{8,})',
    ).firstMatch(summary);
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
        const SnackBar(content: Text('该事件没有会话引用')),
      );
      return;
    }
    final hit = _resolveSession(ref);
    if (hit == null) {
      await Clipboard.setData(ClipboardData(text: ref));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('会话不在列表 — 已复制引用：$ref')),
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
    final rawQ = _query.trim();
    final list = _events.where((e) {
      final kind = (e['kind'] ?? e['type'] ?? 'event').toString().toLowerCase();
      if (_kind.isNotEmpty) {
        if (_kind == 'other') {
          final known =
              kind.contains('session') ||
              kind.contains('chat') ||
              kind.contains('message') ||
              kind.contains('host') ||
              kind.contains('cron');
          if (known) return false;
        } else if (!kind.contains(_kind)) {
          return false;
        }
      }
      if (_level.isNotEmpty) {
        final lv = (e['level'] ?? e['severity'] ?? e['priority'] ?? '')
            .toString()
            .toLowerCase();
        if (!lv.contains(_level.toLowerCase())) return false;
      }
      if (_source.isNotEmpty) {
        final src =
            (e['source'] ?? e['origin'] ?? e['channel'] ?? e['provider'] ?? '')
                .toString()
                .toLowerCase();
        if (_source == 'other') {
          final known =
              src.contains('mock') ||
              src.contains('bridge') ||
              src.contains('session') ||
              src.contains('terminal') ||
              src.contains('hermes') ||
              src.contains('host');
          if (known) return false;
        } else if (!src.contains(_source.toLowerCase())) {
          return false;
        }
      }
      if (rawQ.isEmpty) return true;
      final hayRaw =
          '${e['kind']} ${e['type']} ${e['summary']} ${e['message']} ${e['session_key']} ${e['session_id']} ${e['source']} ${e['level']}';
      return QueryMatch.matches(
        hayRaw,
        rawQ,
        caseSensitive: _queryCase,
        regex: _queryRegex,
      );
    }).toList();
    int tsOf(Map<String, dynamic> e) {
      final v = e['ts'] ?? e['time'] ?? e['timestamp'];
      if (v is num) return (v * 1000).round();
      final p = DateTime.tryParse(v?.toString() ?? '');
      return p?.millisecondsSinceEpoch ?? 0;
    }

    list.sort((a, b) {
      if (_sortByPriority) {
        final pa = (a['priority'] ?? '').toString().toLowerCase();
        final pb = (b['priority'] ?? '').toString().toLowerCase();
        final c = pa.compareTo(pb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByTs) {
        final c = tsOf(a).compareTo(tsOf(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByChannel) {
        final ca =
            (a['channel'] ?? a['platform'] ?? a['origin'] ?? a['source'] ?? '')
                .toString()
                .toLowerCase();
        final cb =
            (b['channel'] ?? b['platform'] ?? b['origin'] ?? b['source'] ?? '')
                .toString()
                .toLowerCase();
        final cs = ca.compareTo(cb);
        if (cs != 0) return _sortAsc ? cs : -cs;
      } else if (_sortByType) {
        final ta = (a['type'] ?? a['event_type'] ?? a['content'] ?? '')
            .toString()
            .toLowerCase();
        final tb = (b['type'] ?? b['event_type'] ?? b['content'] ?? '')
            .toString()
            .toLowerCase();
        final cs = ta.compareTo(tb);
        if (cs != 0) return _sortAsc ? cs : -cs;
      } else if (_sortByLevel) {
        final la = (a['level'] ?? a['severity'] ?? a['priority'] ?? '')
            .toString()
            .toLowerCase();
        final lb = (b['level'] ?? b['severity'] ?? b['priority'] ?? '')
            .toString()
            .toLowerCase();
        final cs = la.compareTo(lb);
        if (cs != 0) return _sortAsc ? cs : -cs;
      } else if (_sortById) {
        final ia = (a['id'] ?? a['event_id'] ?? a['uuid'] ?? '')
            .toString()
            .toLowerCase();
        final ib = (b['id'] ?? b['event_id'] ?? b['uuid'] ?? '')
            .toString()
            .toLowerCase();
        final cs = ia.compareTo(ib);
        if (cs != 0) return _sortAsc ? cs : -cs;
      } else if (_sortBySource) {
        final sa =
            (a['source'] ?? a['origin'] ?? a['channel'] ?? a['provider'] ?? '')
                .toString()
                .toLowerCase();
        final sb =
            (b['source'] ?? b['origin'] ?? b['channel'] ?? b['provider'] ?? '')
                .toString()
                .toLowerCase();
        final cs = sa.compareTo(sb);
        if (cs != 0) return _sortAsc ? cs : -cs;
      } else if (_sortBySession) {
        final sa = (a['session_key'] ?? a['session_id'] ?? a['session'] ?? '')
            .toString()
            .toLowerCase();
        final sb = (b['session_key'] ?? b['session_id'] ?? b['session'] ?? '')
            .toString()
            .toLowerCase();
        final cs = sa.compareTo(sb);
        if (cs != 0) return _sortAsc ? cs : -cs;
      } else if (_sortBySummary) {
        final sa =
            (a['summary'] ?? a['message'] ?? a['detail'] ?? a['title'] ?? '')
                .toString()
                .toLowerCase();
        final sb =
            (b['summary'] ?? b['message'] ?? b['detail'] ?? b['title'] ?? '')
                .toString()
                .toLowerCase();
        final cs = sa.compareTo(sb);
        if (cs != 0) return _sortAsc ? cs : -cs;
      } else if (_sortByKind) {
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
        title: Text(() {
          final base = items.isEmpty
              ? '主机活动'
              : (_events.isEmpty || items.length == _events.length
                    ? 'Host activity (${items.length})'
                    : 'Host activity (${items.length}/${_events.length})');
          return _autoRefresh ? '$base · auto' : base;
        }()),
        actions: [
          IconButton(
            tooltip: '复制全部',
            onPressed: items.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    for (final e in items) {
                      final ts = e['ts'] ?? e['time'] ?? '';
                      final kind = e['type'] ?? e['kind'] ?? 'event';
                      final msg =
                          e['message'] ?? e['summary'] ?? e['content'] ?? e;
                      final sk = e['session_key'] ?? e['session_id'] ?? '';
                      buf.writeln('[$ts] $kind  $msg  session=$sk');
                    }
                    await Clipboard.setData(
                      ClipboardData(text: buf.toString()),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已复制 ${items.length} events'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: '复制 CSV',
            onPressed: items.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    buf.writeln('ts,kind,session,message');
                    for (final e in items) {
                      final ts = '${e['ts'] ?? e['time'] ?? ''}'.replaceAll(
                        ',',
                        ';',
                      );
                      final kind = '${e['type'] ?? e['kind'] ?? 'event'}'
                          .replaceAll(',', ';');
                      final sk = '${e['session_key'] ?? e['session_id'] ?? ''}'
                          .replaceAll(',', ';');
                      final msg =
                          '${e['message'] ?? e['summary'] ?? e['content'] ?? ''}'
                              .replaceAll(',', ';')
                              .replaceAll('\n', ' ');
                      buf.writeln('$ts,$kind,$sk,$msg');
                    }
                    await Clipboard.setData(
                      ClipboardData(text: buf.toString()),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已复制 CSV（${items.length}）'),
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
            icon: Icon(
              _newestFirst ? Icons.arrow_downward : Icons.arrow_upward,
            ),
          ),
          IconButton(
            tooltip: _relativeTs
                ? '绝对时间戳'
                : '相对时间戳',
            onPressed: () => setState(() => _relativeTs = !_relativeTs),
            icon: Icon(_relativeTs ? Icons.schedule : Icons.access_time),
          ),
          IconButton(
            tooltip: _sortByPriority
                ? (_sortAsc ? 'Priority Z→A' : 'Priority A→Z')
                : (_sortByTs
                      ? (_sortAsc ? 'Time old→new' : 'Time new→old')
                      : (_sortByChannel
                            ? (_sortAsc ? 'Channel Z→A' : 'Channel A→Z')
                            : (_sortByType
                                  ? (_sortAsc ? '类型 Z→A' : '类型 A→Z')
                                  : (_sortByLevel
                                        ? (_sortAsc ? '级别 Z→A' : '级别 A→Z')
                                        : (_sortById
                                              ? (_sortAsc ? 'ID Z→A' : 'ID A→Z')
                                              : (_sortBySource
                                                    ? (_sortAsc
                                                          ? '来源 Z→A'
                                                          : '来源 A→Z')
                                                    : (_sortBySession
                                                          ? (_sortAsc
                                                                ? '会话 Z→A'
                                                                : '会话 A→Z')
                                                          : (_sortBySummary
                                                                ? (_sortAsc
                                                                      ? '摘要 Z→A'
                                                                      : '摘要 A→Z')
                                                                : (_sortByKind
                                                                      ? (_sortAsc
                                                                            ? 'Kinds Z→A'
                                                                            : 'Kinds A→Z')
                                                                      : 'Sort by kind / summary / session / source / id / level / type / channel / time / priority'))))))))),
            onPressed: () {
              setState(() {
                if (!_sortByKind &&
                    !_sortBySummary &&
                    !_sortBySession &&
                    !_sortBySource &&
                    !_sortById &&
                    !_sortByLevel &&
                    !_sortByType &&
                    !_sortByChannel &&
                    !_sortByTs) {
                  _sortByKind = true;
                  _sortBySummary = false;
                  _sortBySession = false;
                  _sortBySource = false;
                  _sortById = false;
                  _sortByLevel = false;
                  _sortByType = false;
                  _sortByChannel = false;
                  _sortByTs = false;
                  _sortByPriority = false;
                  _sortAsc = true;
                } else if (_sortByKind && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByKind && !_sortAsc) {
                  _sortByKind = false;
                  _sortBySummary = true;
                  _sortBySession = false;
                  _sortBySource = false;
                  _sortById = false;
                  _sortByLevel = false;
                  _sortByType = false;
                  _sortByChannel = false;
                  _sortByTs = false;
                  _sortByPriority = false;
                  _sortAsc = true;
                } else if (_sortBySummary && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortBySummary && !_sortAsc) {
                  _sortByKind = false;
                  _sortBySummary = false;
                  _sortBySession = true;
                  _sortBySource = false;
                  _sortById = false;
                  _sortByLevel = false;
                  _sortByType = false;
                  _sortByChannel = false;
                  _sortByTs = false;
                  _sortByPriority = false;
                  _sortAsc = true;
                } else if (_sortBySession && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortBySession && !_sortAsc) {
                  _sortByKind = false;
                  _sortBySummary = false;
                  _sortBySession = false;
                  _sortBySource = true;
                  _sortById = false;
                  _sortByLevel = false;
                  _sortByType = false;
                  _sortByChannel = false;
                  _sortByTs = false;
                  _sortByPriority = false;
                  _sortAsc = true;
                } else if (_sortBySource && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortBySource && !_sortAsc) {
                  _sortByKind = false;
                  _sortBySummary = false;
                  _sortBySession = false;
                  _sortBySource = false;
                  _sortById = true;
                  _sortByLevel = false;
                  _sortByType = false;
                  _sortByChannel = false;
                  _sortByTs = false;
                  _sortByPriority = false;
                  _sortAsc = true;
                } else if (_sortById && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortById && !_sortAsc) {
                  _sortByKind = false;
                  _sortBySummary = false;
                  _sortBySession = false;
                  _sortBySource = false;
                  _sortById = false;
                  _sortByLevel = true;
                  _sortByType = false;
                  _sortByChannel = false;
                  _sortByTs = false;
                  _sortByPriority = false;
                  _sortAsc = true;
                } else if (_sortByLevel && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByLevel && !_sortAsc) {
                  _sortByKind = false;
                  _sortBySummary = false;
                  _sortBySession = false;
                  _sortBySource = false;
                  _sortById = false;
                  _sortByLevel = false;
                  _sortByType = true;
                  _sortByChannel = false;
                  _sortByTs = false;
                  _sortByPriority = false;
                  _sortAsc = true;
                } else if (_sortByType && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByType && !_sortAsc) {
                  _sortByKind = false;
                  _sortBySummary = false;
                  _sortBySession = false;
                  _sortBySource = false;
                  _sortById = false;
                  _sortByLevel = false;
                  _sortByType = false;
                  _sortByChannel = true;
                  _sortByTs = false;
                  _sortByPriority = false;
                  _sortAsc = true;
                } else if (_sortByChannel && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByChannel && !_sortAsc) {
                  _sortByKind = false;
                  _sortBySummary = false;
                  _sortBySession = false;
                  _sortBySource = false;
                  _sortById = false;
                  _sortByLevel = false;
                  _sortByType = false;
                  _sortByChannel = false;
                  _sortByTs = true;
                  _sortByPriority = false;
                  _sortAsc = false; // new first
                } else if (_sortByTs && !_sortAsc) {
                  _sortAsc = true;
                } else if (_sortByTs && _sortAsc) {
                  _sortByKind = false;
                  _sortBySummary = false;
                  _sortBySession = false;
                  _sortBySource = false;
                  _sortById = false;
                  _sortByLevel = false;
                  _sortByType = false;
                  _sortByChannel = false;
                  _sortByTs = false;
                  _sortByPriority = true;
                  _sortAsc = true;
                } else if (_sortByPriority && _sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortByKind = false;
                  _sortBySummary = false;
                  _sortBySession = false;
                  _sortBySource = false;
                  _sortById = false;
                  _sortByLevel = false;
                  _sortByType = false;
                  _sortByChannel = false;
                  _sortByTs = false;
                  _sortByPriority = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(
              _sortByPriority
                  ? Icons.low_priority
                  : (_sortByTs
                        ? Icons.schedule
                        : (_sortByChannel
                              ? Icons.cell_tower
                              : (_sortByType
                                    ? Icons.label_outline
                                    : (_sortByLevel
                                          ? Icons.low_priority
                                          : (_sortById
                                                ? Icons.tag
                                                : (_sortBySource
                                                      ? Icons.source_outlined
                                                      : (_sortBySession
                                                            ? Icons
                                                                  .vpn_key_outlined
                                                            : (_sortBySummary
                                                                  ? Icons.notes
                                                                  : (_sortByKind
                                                                        ? Icons
                                                                              .category_outlined
                                                                        : Icons
                                                                              .sort))))))))),
            ),
          ),

          IconButton(
            tooltip: _wrapLines ? '截断详情' : '换行详情',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
          ),

          IconButton(
            tooltip: _autoRefresh ? '暂停刷新' : '自动刷新',
            onPressed: () {
              setState(() => _autoRefresh = !_autoRefresh);
              _armTimer();
            },
            icon: Icon(
              _autoRefresh
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
            ),
          ),
          IconButton(
            tooltip: '回到顶部',
            onPressed: () {
              if (!_scroll.hasClients) return;
              _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            },
            icon: const Icon(Icons.vertical_align_top),
          ),
          IconButton(
            tooltip: '跳到底部',
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
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in const [
                  ('', '任意级别'),
                  ('info', 'info'),
                  ('warn', 'warn'),
                  ('error', 'error'),
                  ('debug', 'debug'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 11)),
                    selected: _level == f.$1,
                    onSelected: (_) => setState(() => _level = f.$1),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in const [
                  ('', '任意来源'),
                  ('mock-host', 'mock-host'),
                  ('bridge', 'bridge'),
                  ('session', 'session'),
                  ('terminal', 'terminal'),
                  ('hermes', 'hermes'),
                  ('other', 'other'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 11)),
                    selected: _source == f.$1,
                    onSelected: (_) => setState(() => _source = f.$1),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: Text('换行', style: const TextStyle(fontSize: 11)),
                  selected: _wrapLines,
                  onSelected: (v) => setState(() => _wrapLines = v),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: Text(AppStrings.regex, style: const TextStyle(fontSize: 11)),
                  selected: _queryRegex,
                  onSelected: (v) => setState(() => _queryRegex = v),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: Text(AppStrings.matchCase, style: const TextStyle(fontSize: 11)),
                  selected: _queryCase,
                  onSelected: (v) => setState(() => _queryCase = v),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text('自动', style: TextStyle(fontSize: 11)),
                  selected: _autoRefresh,
                  onSelected: (v) => setState(() => _autoRefresh = v),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text(AppStrings.newestFirst, style: TextStyle(fontSize: 11)),
                  selected: _newestFirst,
                  onSelected: (v) => setState(() => _newestFirst = v),
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
                    ? (_queryCase ? '筛选（正则 · 大小写）' : '筛选（正则）')
                    : (_queryCase
                          ? '筛选（区分大小写）'
                          : '筛选类型 / 摘要 / 会话'),
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: IconButton(
                  tooltip: _queryRegex
                      ? (_queryCase
                            ? '正则 · 大小写 开（长按恢复普通筛选）'
                            : '正则 · 大小写 关（长按恢复普通筛选）')
                      : (_queryCase
                            ? '区分大小写（长按切换正则）'
                            : '不区分大小写（长按切换正则）'),
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
            child: items.isEmpty && !_loading
                ? Center(
                    child: Text(
                      _events.isEmpty
                          ? '暂无活动（主机可能未暴露 /activity）'
                          : '没有匹配的事件',
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
                        final resolvable =
                            ref != null && _resolveSession(ref) != null;
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
                              if ((e['level'] ?? '').toString().isNotEmpty)
                                (e['level']).toString(),
                              if ((e['source'] ?? '').toString().isNotEmpty)
                                (e['source']).toString(),
                              _fmtTs(e['ts']),
                              if (ref != null) ref,
                            ].join(' · '),
                          ),
                          dense: true,
                          trailing: ref == null
                              ? null
                              : Icon(
                                  resolvable
                                      ? Icons.chat_outlined
                                      : Icons.copy_all_outlined,
                                  size: 18,
                                ),
                          onTap: ref == null ? null : () => _openSession(e),
                          onLongPress: () async {
                            final text =
                                '${e['kind']} ${e['summary']} ${e['session_key'] ?? e['session_id'] ?? ''}'
                                    .trim();
                            await Clipboard.setData(ClipboardData(text: text));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('事件已复制'),
                                  duration: Duration(seconds: 1),
                                ),
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
