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

  @override
  void initState() {
    super.initState();
    _client = MgmtClient(config: widget.config);
    _load();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
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
        title: const Text('Workspace'),
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
                          entries.whereType<Map>().where((e) {
                                final q = _filter.trim().toLowerCase();
                                final name = (e['name'] ?? '').toString().toLowerCase();
                                final type = (e['type'] ?? '').toString().toLowerCase();
                                return name.contains(q) || type.contains(q);
                              }).isEmpty)
                        const ListTile(title: Text('No entries match filter')),
                      for (final e in entries.whereType<Map>().where((e) {
                        final q = _filter.trim().toLowerCase();
                        if (q.isEmpty) return true;
                        final name = (e['name'] ?? '').toString().toLowerCase();
                        final type = (e['type'] ?? '').toString().toLowerCase();
                        return name.contains(q) || type.contains(q);
                      }))
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
