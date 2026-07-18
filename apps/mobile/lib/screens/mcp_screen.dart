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
  String _status = '';
  bool _wrapLines = false;
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
    final q = _query.trim().toLowerCase();
    final list = servers.where((s) {
      final st = (s['status'] ?? '').toString().toLowerCase();
      if (_status.isNotEmpty) {
        if (_status == 'unknown') {
          if (st.isNotEmpty && st != 'unknown' && st != '—') return false;
        } else if (!st.contains(_status)) {
          return false;
        }
      }
      if (q.isEmpty) return true;
      final tools = s['tools'] is List ? (s['tools'] as List).join(' ') : '';
      final hay = '${s['name']} ${s['description']} ${s['status']} $tools'.toLowerCase();
      return hay.contains(q);
    }).toList();
    list.sort((a, b) {
      if (_sortByStatus) {
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
                      if (s is Map) {
                        final name = (s['name'] ?? s['id'] ?? 'mcp').toString();
                        final desc = (s['description'] ?? s['url'] ?? s['command'] ?? '').toString();
                        buf.writeln('## $name');
                        if (desc.isNotEmpty) buf.writeln(desc);
                        buf.writeln('$s');
                        buf.writeln();
                      } else {
                        buf.writeln('$s');
                      }
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied ${items.length} MCP entries'), duration: const Duration(seconds: 1)),
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
                      if (s is Map) {
                        final name = (s['name'] ?? s['id'] ?? 'mcp').toString().replaceAll(',', ';');
                        final status = (s['status'] ?? s['state'] ?? '').toString().replaceAll(',', ';');
                        final desc = (s['description'] ?? s['url'] ?? s['command'] ?? '')
                            .toString()
                            .replaceAll(',', ';')
                            .replaceAll('\n', ' ');
                        buf.writeln('$name,$status,$desc');
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
            tooltip: _sortByStatus
                ? (_sortAsc ? 'Status Z→A' : 'Status A→Z')
                : (_sortAsc ? 'Name Z→A' : 'Name A→Z'),
            onPressed: () {
              setState(() {
                if (!_sortByStatus && _sortAsc) {
                  _sortAsc = false;
                } else if (!_sortByStatus && !_sortAsc) {
                  _sortByStatus = true;
                  _sortAsc = true;
                } else if (_sortByStatus && _sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortByStatus = false;
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(_sortByStatus
                ? Icons.health_and_safety_outlined
                : (_sortAsc ? Icons.sort_by_alpha : Icons.sort)),
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
                          label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                          selected: _status == f.$1,
                          onSelected: (_) => setState(() => _status = f.$1),
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
                      hintText: 'Filter name / tools / status',
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
                                    ? (s['tools'] as List).map((e) => e.toString()).join(', ')
                                    : '';
                                final sub = [
                                  if (s['description'] != null) s['description'].toString(),
                                  if (s['status'] != null) 'status: ${s['status']}',
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
                                        await Clipboard.setData(ClipboardData(text: '$name\n$sub'));
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
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
                            )),
                ),
              ],
            ),
    );
  }
}
