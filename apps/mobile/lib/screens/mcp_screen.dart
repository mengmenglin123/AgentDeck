import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/app_settings_controller.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';

/// Readonly MCP server catalog from Host `GET /mcp`.
class McpScreen extends StatefulWidget {
  const McpScreen({super.key, required this.config});
  final ConnectionConfig config;

  @override
  State<McpScreen> createState() => _McpScreenState();
}

class _McpScreenState extends State<McpScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> servers = [];
  final _q = TextEditingController();
  String _query = '';
  bool _queryCase = false;
  bool _queryRegex = false;
  String _status = '';
  String _enabled = '';
  String _transportFilter = ''; // empty=all | stdio | sse | http | ws | other
  String _kind = ''; // empty=all | inprocess | stdio | sse | http | other
  bool _wrapLines = false;
  bool _sortByStatus = false;
  bool _sortByTools = false;
  bool _sortByEndpoint = false;
  bool _sortByTransport = false;
  bool _sortById = false;
  bool _sortByDesc = false;
  bool _sortByCommand = false;
  bool _sortByKind = false;
  bool _sortByName = false;
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
      final data = await MgmtClient(config: widget.config).listMcp();
      final raw = data['servers'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      setState(() {
        servers = list;
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
    final list = servers.where((s) {
      final st = (s['status'] ?? '').toString().toLowerCase();
      if (_status.isNotEmpty) {
        if (_status == 'unknown') {
          if (st.isNotEmpty && st != 'unknown' && st != '—') return false;
        } else if (!st.contains(_status)) {
          return false;
        }
      }
      if (_enabled.isNotEmpty) {
        final en = s['enabled'];
        final bool? isOn = en is bool
            ? en
            : (en == null
                  ? null
                  : ('$en'.toLowerCase() == 'true' ||
                        '$en' == '1' ||
                        '$en'.toLowerCase() == 'yes'));
        if (_enabled == 'on' && isOn != true) return false;
        if (_enabled == 'off' && isOn != false) return false;
        if (_enabled == 'unknown' && isOn != null) return false;
      }
      if (_transportFilter.isNotEmpty) {
        final tr =
            (s['transport'] ??
                    s['type'] ??
                    s['protocol'] ??
                    s['url'] ??
                    s['command'] ??
                    '')
                .toString()
                .toLowerCase();
        if (_transportFilter == 'other') {
          final known =
              tr.contains('stdio') ||
              tr.contains('sse') ||
              tr.contains('http') ||
              tr.contains('ws') ||
              tr.contains('websocket');
          if (known) return false;
        } else if (!tr.contains(_transportFilter)) {
          return false;
        }
      }
      if (_kind.isNotEmpty) {
        final kd = (s['kind'] ?? s['type'] ?? s['category'] ?? '')
            .toString()
            .toLowerCase();
        if (_kind == 'other') {
          final known =
              kd.contains('inprocess') ||
              kd.contains('stdio') ||
              kd.contains('sse') ||
              kd.contains('http') ||
              kd.contains('ws');
          if (known) return false;
        } else if (!kd.contains(_kind)) {
          return false;
        }
      }
      if (rawQ.isEmpty) return true;
      final tools = s['tools'] is List ? (s['tools'] as List).join(' ') : '';
      final hayRaw =
          '${s['name']} ${s['description']} ${s['status']} ${s['kind']} ${s['note']} ${s['transport']} ${s['url']} ${s['command']} ${s['enabled']} $tools';
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
      String endpointOf(Map x) =>
          (x['url'] ??
                  x['command'] ??
                  x['transport'] ??
                  x['endpoint'] ??
                  x['description'] ??
                  '')
              .toString()
              .toLowerCase();
      if (_sortByName) {
        final na = (a['name'] ?? a['id'] ?? '').toString().toLowerCase();
        final nb = (b['name'] ?? b['id'] ?? '').toString().toLowerCase();
        final c = na.compareTo(nb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByKind) {
        final ka = (a['kind'] ?? a['type'] ?? a['category'] ?? '')
            .toString()
            .toLowerCase();
        final kb = (b['kind'] ?? b['type'] ?? b['category'] ?? '')
            .toString()
            .toLowerCase();
        final c = ka.compareTo(kb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByCommand) {
        final ca = (a['command'] ?? a['cmd'] ?? a['args'] ?? a['url'] ?? '')
            .toString()
            .toLowerCase();
        final cb = (b['command'] ?? b['cmd'] ?? b['args'] ?? b['url'] ?? '')
            .toString()
            .toLowerCase();
        final c = ca.compareTo(cb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByDesc) {
        final da = (a['description'] ?? a['summary'] ?? a['note'] ?? '')
            .toString()
            .toLowerCase();
        final db = (b['description'] ?? b['summary'] ?? b['note'] ?? '')
            .toString()
            .toLowerCase();
        final c = da.compareTo(db);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortById) {
        final ia = (a['id'] ?? a['server_id'] ?? a['name'] ?? '')
            .toString()
            .toLowerCase();
        final ib = (b['id'] ?? b['server_id'] ?? b['name'] ?? '')
            .toString()
            .toLowerCase();
        final c = ia.compareTo(ib);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByTransport) {
        final ta = (a['transport'] ?? a['type'] ?? a['kind'] ?? '')
            .toString()
            .toLowerCase();
        final tb = (b['transport'] ?? b['type'] ?? b['kind'] ?? '')
            .toString()
            .toLowerCase();
        final c = ta.compareTo(tb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByEndpoint) {
        final c = endpointOf(a).compareTo(endpointOf(b));
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByTools) {
        final ta = a['tools'] is List ? (a['tools'] as List).length : 0;
        final tb = b['tools'] is List ? (b['tools'] as List).length : 0;
        final c = ta.compareTo(tb);
        if (c != 0) return _sortAsc ? c : -c;
      } else if (_sortByStatus) {
        final sa = (a['status'] ?? a['state'] ?? '').toString().toLowerCase();
        final sb = (b['status'] ?? b['state'] ?? '').toString().toLowerCase();
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
    final cs = Theme.of(context).colorScheme;
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          items.isEmpty
              ? 'MCP (readonly)'
              : (items.length == servers.length
                    ? 'MCP (${items.length})'
                    : 'MCP (${items.length}/${servers.length})'),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            onPressed: items.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    for (final s in items) {
                      final name = (s['name'] ?? s['id'] ?? 'mcp').toString();
                      final desc =
                          (s['description'] ?? s['url'] ?? s['command'] ?? '')
                              .toString();
                      buf.writeln('## $name');
                      if (desc.isNotEmpty) buf.writeln(desc);
                      buf.writeln('$s');
                      buf.writeln();
                    }
                    await Clipboard.setData(
                      ClipboardData(text: buf.toString()),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied ${items.length} MCP entries'),
                          duration: const Duration(seconds: 1),
                        ),
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
                    buf.writeln('name,status,description');
                    for (final s in items) {
                      final name = (s['name'] ?? s['id'] ?? 'mcp')
                          .toString()
                          .replaceAll(',', ';');
                      final status = (s['status'] ?? s['state'] ?? '')
                          .toString()
                          .replaceAll(',', ';');
                      final desc =
                          (s['description'] ?? s['url'] ?? s['command'] ?? '')
                              .toString()
                              .replaceAll(',', ';')
                              .replaceAll('\n', ' ');
                      buf.writeln('$name,$status,$desc');
                    }
                    await Clipboard.setData(
                      ClipboardData(text: buf.toString()),
                    );
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
            tooltip: _sortByName
                ? (_sortAsc ? 'Name Z→A' : 'Name A→Z')
                : (_sortByKind
                      ? (_sortAsc ? 'Kind Z→A' : 'Kind A→Z')
                      : (_sortByCommand
                            ? (_sortAsc ? 'Command Z→A' : 'Command A→Z')
                            : (_sortByDesc
                                  ? (_sortAsc
                                        ? 'Description Z→A'
                                        : 'Description A→Z')
                                  : (_sortById
                                        ? (_sortAsc ? 'Id Z→A' : 'Id A→Z')
                                        : (_sortByTransport
                                              ? (_sortAsc
                                                    ? 'Transport Z→A'
                                                    : 'Transport A→Z')
                                              : (_sortByEndpoint
                                                    ? (_sortAsc
                                                          ? 'Endpoint Z→A'
                                                          : 'Endpoint A→Z')
                                                    : (_sortByTools
                                                          ? (_sortAsc
                                                                ? 'Tools many→few'
                                                                : 'Tools few→many')
                                                          : (_sortByStatus
                                                                ? (_sortAsc
                                                                      ? 'Status Z→A'
                                                                      : 'Status A→Z')
                                                                : (_sortAsc
                                                                      ? 'Name Z→A'
                                                                      : 'Name A→Z'))))))))),
            onPressed: () {
              setState(() {
                if (!_sortByStatus &&
                    !_sortByTools &&
                    !_sortByEndpoint &&
                    !_sortByTransport &&
                    !_sortById &&
                    !_sortByDesc &&
                    !_sortByCommand &&
                    !_sortByKind &&
                    !_sortByName &&
                    _sortAsc) {
                  _sortAsc = false;
                } else if (!_sortByStatus &&
                    !_sortByTools &&
                    !_sortByEndpoint &&
                    !_sortByTransport &&
                    !_sortById &&
                    !_sortByDesc &&
                    !_sortByCommand &&
                    !_sortByKind &&
                    !_sortByName &&
                    !_sortAsc) {
                  _sortByStatus = true;
                  _sortByTools = false;
                  _sortByEndpoint = false;
                  _sortByTransport = false;
                  _sortById = false;
                  _sortByDesc = false;
                  _sortByCommand = false;
                  _sortByKind = false;
                  _sortByName = false;
                  _sortAsc = true;
                } else if (_sortByStatus && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByStatus && !_sortAsc) {
                  _sortByStatus = false;
                  _sortByTools = true;
                  _sortByEndpoint = false;
                  _sortByTransport = false;
                  _sortById = false;
                  _sortByDesc = false;
                  _sortByCommand = false;
                  _sortByKind = false;
                  _sortByName = false;
                  _sortAsc = false; // many first
                } else if (_sortByTools && !_sortAsc) {
                  _sortAsc = true;
                } else if (_sortByTools && _sortAsc) {
                  _sortByStatus = false;
                  _sortByTools = false;
                  _sortByEndpoint = true;
                  _sortByTransport = false;
                  _sortById = false;
                  _sortByDesc = false;
                  _sortByCommand = false;
                  _sortByKind = false;
                  _sortByName = false;
                  _sortAsc = true;
                } else if (_sortByEndpoint && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByEndpoint && !_sortAsc) {
                  _sortByStatus = false;
                  _sortByTools = false;
                  _sortByEndpoint = false;
                  _sortByTransport = true;
                  _sortById = false;
                  _sortByDesc = false;
                  _sortByCommand = false;
                  _sortByKind = false;
                  _sortByName = false;
                  _sortAsc = true;
                } else if (_sortByTransport && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByTransport && !_sortAsc) {
                  _sortByStatus = false;
                  _sortByTools = false;
                  _sortByEndpoint = false;
                  _sortByTransport = false;
                  _sortById = true;
                  _sortByDesc = false;
                  _sortByCommand = false;
                  _sortByKind = false;
                  _sortByName = false;
                  _sortAsc = true;
                } else if (_sortById && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortById && !_sortAsc) {
                  _sortByStatus = false;
                  _sortByTools = false;
                  _sortByEndpoint = false;
                  _sortByTransport = false;
                  _sortById = false;
                  _sortByDesc = true;
                  _sortByCommand = false;
                  _sortByKind = false;
                  _sortByName = false;
                  _sortAsc = true;
                } else if (_sortByDesc && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByDesc && !_sortAsc) {
                  _sortByStatus = false;
                  _sortByTools = false;
                  _sortByEndpoint = false;
                  _sortByTransport = false;
                  _sortById = false;
                  _sortByDesc = false;
                  _sortByCommand = true;
                  _sortByKind = false;
                  _sortByName = false;
                  _sortAsc = true;
                } else if (_sortByCommand && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByCommand && !_sortAsc) {
                  _sortByStatus = false;
                  _sortByTools = false;
                  _sortByEndpoint = false;
                  _sortByTransport = false;
                  _sortById = false;
                  _sortByDesc = false;
                  _sortByCommand = false;
                  _sortByKind = true;
                  _sortByName = false;
                  _sortAsc = true;
                } else if (_sortByKind && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortByKind && !_sortAsc) {
                  _sortByStatus = false;
                  _sortByTools = false;
                  _sortByEndpoint = false;
                  _sortByTransport = false;
                  _sortById = false;
                  _sortByDesc = false;
                  _sortByCommand = false;
                  _sortByKind = false;
                  _sortByName = true;
                  _sortAsc = true;
                } else if (_sortByName && _sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortByStatus = false;
                  _sortByTools = false;
                  _sortByEndpoint = false;
                  _sortByTransport = false;
                  _sortById = false;
                  _sortByDesc = false;
                  _sortByCommand = false;
                  _sortByKind = false;
                  _sortByName = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(
              _sortByName
                  ? Icons.sort_by_alpha
                  : (_sortByKind
                        ? Icons.category_outlined
                        : (_sortByCommand
                              ? Icons.terminal
                              : (_sortByDesc
                                    ? Icons.notes
                                    : (_sortById
                                          ? Icons.tag
                                          : (_sortByTransport
                                                ? Icons.swap_horiz
                                                : (_sortByEndpoint
                                                      ? Icons.link
                                                      : (_sortByTools
                                                            ? Icons
                                                                  .build_outlined
                                                            : (_sortByStatus
                                                                  ? Icons
                                                                        .health_and_safety_outlined
                                                                  : (_sortAsc
                                                                        ? Icons
                                                                              .sort_by_alpha
                                                                        : Icons
                                                                              .sort))))))))),
            ),
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
              _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
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
            icon: Icon(
              _autoRefresh
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
            ),
          ),

          IconButton(
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(
                    'Catalog only — App does not start MCP servers. Host owns tools.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final f in const [
                        ('', 'All'),
                        ('ok', 'Ok'),
                        ('connected', 'Connected'),
                        ('error', 'Error'),
                        ('disabled', 'Disabled'),
                        ('unknown', 'Unknown'),
                      ])
                        FilterChip(
                          label: Text(
                            f.$2,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: _status == f.$1,
                          onSelected: (_) => setState(() => _status = f.$1),
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
                        ('', 'Any enabled'),
                        ('on', 'enabled'),
                        ('off', 'disabled'),
                        ('unknown', 'enabled?'),
                      ])
                        FilterChip(
                          label: Text(
                            f.$2,
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: _enabled == f.$1,
                          onSelected: (_) => setState(() => _enabled = f.$1),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final f in const [
                        ('', 'All transports'),
                        ('stdio', 'stdio'),
                        ('sse', 'SSE'),
                        ('http', 'HTTP'),
                        ('ws', 'WS'),
                        ('other', 'Other'),
                      ])
                        FilterChip(
                          label: Text(
                            f.$2,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: _transportFilter == f.$1,
                          onSelected: (_) =>
                              setState(() => _transportFilter = f.$1),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final f in const [
                        ('', 'Any kind'),
                        ('inprocess', 'inprocess'),
                        ('stdio', 'stdio'),
                        ('sse', 'sse'),
                        ('http', 'http'),
                        ('other', 'other'),
                      ])
                        FilterChip(
                          label: Text(
                            f.$2,
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: _kind == f.$1,
                          onSelected: (_) => setState(() => _kind = f.$1),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text(
                          'Wrap',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: _wrapLines,
                        onSelected: (v) => setState(() => _wrapLines = v),
                        visualDensity: VisualDensity.compact,
                      ),
                      FilterChip(
                        label: const Text(
                          'Regex',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: _queryRegex,
                        onSelected: (v) => setState(() => _queryRegex = v),
                        visualDensity: VisualDensity.compact,
                      ),
                      FilterChip(
                        label: const Text(
                          'Case',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: _queryCase,
                        onSelected: (v) => setState(() => _queryCase = v),
                        visualDensity: VisualDensity.compact,
                      ),
                      FilterChip(
                        label: const Text(
                          'Auto',
                          style: TextStyle(fontSize: 11),
                        ),
                        selected: _autoRefresh,
                        onSelected: (v) {
                          setState(() => _autoRefresh = v);
                          _armTimer();
                        },
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
                          ? (_queryCase
                                ? 'Filter (regex · case)'
                                : 'Filter (regex)')
                          : (_queryCase
                                ? 'Filter (case-sensitive)'
                                : 'Filter name / tools / status'),
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
                        onPressed: () =>
                            setState(() => _queryCase = !_queryCase),
                        onLongPress: () =>
                            setState(() => _queryRegex = !_queryRegex),
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
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(error!, style: TextStyle(color: cs.error)),
                  ),
                Expanded(
                  child: servers.isEmpty && error == null
                      ? const Center(child: Text('No MCP servers reported'))
                      : items.isEmpty
                      ? const Center(child: Text('No servers match filter'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                            itemCount: items.length,
                            itemBuilder: (context, i) {
                              final s = items[i];
                              final name = s['name']?.toString() ?? 'unnamed';
                              final tools = s['tools'] is List
                                  ? (s['tools'] as List)
                                        .map((e) => e.toString())
                                        .join(', ')
                                  : '';
                              final sub = [
                                if (s['description'] != null)
                                  s['description'].toString(),
                                if (s['kind'] != null) 'kind: ${s['kind']}',
                                if (s['status'] != null)
                                  'status: ${s['status']}',
                                if (s['enabled'] != null)
                                  'enabled: ${s['enabled']}',
                                if (s['note'] != null) 'note: ${s['note']}',
                                if (tools.isNotEmpty) 'tools: $tools',
                              ].where((e) => e.isNotEmpty).join('\n');
                              return Card(
                                child: ListTile(
                                  leading: const Icon(Icons.hub_outlined),
                                  title: Text(name),
                                  subtitle: Text(
                                    sub,
                                    maxLines: _wrapLines ? 8 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: true,
                                  ),
                                  isThreeLine: true,
                                  trailing: IconButton(
                                    tooltip: 'Copy',
                                    icon: const Icon(Icons.copy, size: 18),
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: '$name\n$sub'),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('MCP entry copied'),
                                            duration: Duration(seconds: 1),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
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
