import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/connection_config.dart';
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
  final _q = TextEditingController();

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
    if (q.isEmpty) return _events;
    return _events.where((e) {
      final hay = '${e['kind']} ${e['summary']} ${e['session_key']} ${e['session_id']}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host activity'),
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
                        title: Text(summary.isEmpty ? kind : summary),
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
