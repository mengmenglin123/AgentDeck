import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/connection_config.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';
import 'diff_screen.dart';

/// Readonly Host workspace browser (`GET /workspace`, `/workspace/git`).
/// Console-only — no write/delete; Host is source of truth.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.config});

  final ConnectionConfig config;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late final MgmtClient _client;
  String _path = '';
  Map<String, dynamic>? _node;
  Map<String, dynamic>? _git;
  String? _error;
  bool _loading = true;
  final _filterCtrl = TextEditingController();
  String _filter = '';
  /// name ascending when true; dirs always first
  bool _sortAsc = true;
  /// all | dir | file
  String _typeFilter = 'all';
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _client = MgmtClient(config: widget.config);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }


  List<Map> get _visibleEntries {
    final node = _node;
    final raw = (node?['entries'] as List?) ?? const [];
    final q = _filter.trim().toLowerCase();
    final list = <Map>[];
    for (final e in raw.whereType<Map>()) {
      final type = (e['type'] ?? '').toString().toLowerCase();
      if (_typeFilter == 'dir' && type != 'dir') continue;
      if (_typeFilter == 'file' && type == 'dir') continue;
      if (q.isNotEmpty) {
        final name = (e['name'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !type.contains(q)) continue;
      }
      list.add(e);
    }
    int rank(Map e) => e['type'] == 'dir' ? 0 : 1;
    list.sort((a, b) {
      final rd = rank(a).compareTo(rank(b));
      if (rd != 0) return rd;
      final na = (a['name'] ?? '').toString().toLowerCase();
      final nb = (b['name'] ?? '').toString().toLowerCase();
      final c = na.compareTo(nb);
      return _sortAsc ? c : -c;
    });
    return list;
  }

  List<Widget> _breadcrumbChips() {
    final parts = _path.split('/').where((e) => e.isNotEmpty).toList();
    final chips = <Widget>[
      ActionChip(
        label: const Text('/'),
        visualDensity: VisualDensity.compact,
        onPressed: _path.isEmpty ? null : () => _load(path: ''),
      ),
    ];
    var acc = '';
    for (var i = 0; i < parts.length; i++) {
      acc = acc.isEmpty ? parts[i] : (acc + '/' + parts[i]);
      final target = acc;
      final last = i == parts.length - 1;
      chips.add(const Padding(
        padding: EdgeInsets.symmetric(horizontal: 2),
        child: Icon(Icons.chevron_right, size: 16),
      ));
      chips.add(
        ActionChip(
          label: Text(parts[i]),
          visualDensity: VisualDensity.compact,
          onPressed: last ? null : () => _load(path: target),
        ),
      );
    }
    return chips;
  }

  Future<void> _load({String? path}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (path != null) {
        _path = path;
        _filter = '';
        _filterCtrl.clear();
      }
    });
    try {
      final node = await _client.workspace(path: _path);
      final git = await _client.workspaceGit();
      if (!mounted) return;
      setState(() {
        _node = node;
        _git = git;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Security.redactText(e.toString());
      });
    }
  }

  void _openEntry(Map entry) {
    final name = entry['name']?.toString() ?? '';
    if (name.isEmpty) return;
    final next = _path.isEmpty ? name : '$_path/$name';
    _load(path: next);
  }

  void _openDiff([String? path]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiffScreen(config: widget.config, initialPath: path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final node = _node;
    final isFile = node?['type'] == 'file';
    final entries = (node?['entries'] as List?) ?? const [];
    final parent = node?['parent']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isFile
              ? 'Workspace'
              : (() {
                  final vis = _visibleEntries;
                  if (entries.isEmpty) return 'Workspace';
                  if (vis.length == entries.length) {
                    return 'Workspace (${vis.length})';
                  }
                  return 'Workspace (${vis.length}/${entries.length})';
                })(),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy path',
            onPressed: () async {
              final p = _path.isEmpty ? '/' : '/$_path';
              await Clipboard.setData(ClipboardData(text: p));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied $p'), duration: const Duration(seconds: 1)),
                );
              }
            },
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: 'Copy listing',
            onPressed: () async {
              final list = <String>[];
              final p = _path.isEmpty ? '/' : '/$_path';
              list.add(p);
              for (final e in _visibleEntries) {
                final name = e['name']?.toString() ?? '';
                final typ = e['type']?.toString() ?? '';
                if (name.isEmpty) continue;
                list.add((typ == 'dir' || typ == 'directory' ? 'd ' : 'f ') + name);
              }
              if (list.length <= 1 && !isFile) {
                list.add('(empty)');
              }
              if (isFile) {
                list.add('file: ' + (_node?['name']?.toString() ?? _path));
              }
              await Clipboard.setData(ClipboardData(text: list.join('\n')));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied listing (' + (list.length - 1).toString() + ')'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            icon: const Icon(Icons.playlist_add_check_outlined),
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
            tooltip: _sortAsc ? 'Sort Z→A (dirs first)' : 'Sort A→Z (dirs first)',
            onPressed: () => setState(() => _sortAsc = !_sortAsc),
            icon: Icon(_sortAsc ? Icons.arrow_downward : Icons.arrow_upward),
          ),
          IconButton(
            tooltip: 'Copy content',
            onPressed: !isFile
                ? null
                : () async {
                    final text = _node?['content']?.toString() ?? '';
                    await Clipboard.setData(ClipboardData(text: text));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('File content copied'), duration: Duration(seconds: 1)),
                      );
                    }
                  },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Copy git summary',
            onPressed: _git == null
                ? null
                : () async {
                    final g = _git!;
                    final files = (g['files'] as List?) ?? const [];
                    final buf = StringBuffer();
                    buf.writeln('branch: ${g['branch'] ?? '—'}');
                    buf.writeln('dirty: ${g['dirty'] ?? g['is_dirty'] ?? '—'}');
                    buf.writeln('ahead: ${g['ahead'] ?? '—'} behind: ${g['behind'] ?? '—'}');
                    buf.writeln('changes: ${files.length}');
                    for (final f in files.whereType<Map>()) {
                      final path = (f['path'] ?? f['file'] ?? '').toString();
                      final status = (f['status'] ?? f['code'] ?? '').toString();
                      if (path.isEmpty) continue;
                      buf.writeln('$status $path');
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Git summary copied (${files.length} files)'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.account_tree_outlined),
          ),
          IconButton(
            tooltip: 'Git diff',
            onPressed: () => _openDiff(isFile ? _path : null),
            icon: const Icon(Icons.difference_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Material(
              color: cs.errorContainer,
              child: ListTile(
                dense: true,
                title: Text(_error!, style: TextStyle(color: cs.onErrorContainer, fontSize: 12)),
              ),
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: _breadcrumbChips()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in const [
                  ('all', 'All'),
                  ('dir', 'Dirs'),
                  ('file', 'Files'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                    selected: _typeFilter == f.$1,
                    onSelected: (_) => setState(() => _typeFilter = f.$1),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),

          ListTile(
            dense: true,
            leading: const Icon(Icons.folder_open, size: 20),
            title: Text(_path.isEmpty ? '/' : '/$_path', style: const TextStyle(fontFamily: 'monospace')),
            subtitle: Text(
              _git == null
                  ? 'readonly host tree'
                  : 'git ${_git!['branch'] ?? '?'} · ${(_git!['files'] as List?)?.length ?? 0} changes (mock)',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: TextButton(
              onPressed: () => _openDiff(),
              child: const Text('Diff'),
            ),
          ),
          if (_git != null && (_git!['files'] is List) && (_git!['files'] as List).isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final f in (_git!['files'] as List).whereType<Map>())
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${f['status'] ?? '?'} ${f['path'] ?? ''}',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                        onPressed: () => _openDiff(f['path']?.toString()),
                      ),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          if (!isFile)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _filterCtrl,
                decoration: InputDecoration(
                  hintText: 'Filter files in this folder',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _filter.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _filterCtrl.clear();
                            setState(() => _filter = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(),
              child: isFile
                ? ListView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      SelectableText(
                        node?['content']?.toString() ?? '',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.35),
                      ),
                    ],
                  )
                : ListView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (_path.isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.arrow_upward),
                          title: const Text('..'),
                          onTap: () => _load(path: parent ?? ''),
                        ),
                      if (entries.isEmpty && !_loading)
                        const ListTile(title: Text('Empty directory')),
                      if (entries.isNotEmpty &&
                          _filter.trim().isNotEmpty &&
                          _visibleEntries.isEmpty)
                        const ListTile(title: Text('No entries match filter')),
                      for (final e in _visibleEntries)
                        ListTile(
                          leading: Icon(
                            e['type'] == 'dir' ? Icons.folder : Icons.insert_drive_file_outlined,
                          ),
                          title: Text(e['name']?.toString() ?? ''),
                          subtitle: e['type'] == 'file'
                              ? Text('${e['size'] ?? '?'} B', style: const TextStyle(fontSize: 11))
                              : const Text('directory', style: TextStyle(fontSize: 11)),
                          onTap: () => _openEntry(e),
                          onLongPress: () async {
                            final name = e['name']?.toString() ?? '';
                            final p = _path.isEmpty ? name : '$_path/$name';
                            await Clipboard.setData(ClipboardData(text: p));
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Copied $p'), duration: const Duration(seconds: 1)),
                              );
                            }
                          },
                          trailing: e['type'] == 'file'
                              ? IconButton(
                                  tooltip: 'Diff',
                                  icon: const Icon(Icons.difference_outlined, size: 18),
                                  onPressed: () {
                                    final name = e['name']?.toString() ?? '';
                                    final p = _path.isEmpty ? name : '$_path/$name';
                                    _openDiff(p);
                                  },
                                )
                              : null,
                        ),
                    ],
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
