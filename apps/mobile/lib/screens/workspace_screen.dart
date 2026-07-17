import 'package:flutter/material.dart';

import '../models/connection_config.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';

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

  @override
  void initState() {
    super.initState();
    _client = MgmtClient(config: widget.config);
    _load();
  }

  Future<void> _load({String? path}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (path != null) _path = path;
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
    final type = entry['type']?.toString();
    if (type == 'dir') {
      _load(path: next);
    } else {
      _load(path: next);
    }
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
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${f['status'] ?? '?'} ${f['path'] ?? ''}',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: isFile
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      node?['content']?.toString() ?? '',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.35),
                    ),
                  )
                : ListView(
                    children: [
                      if (_path.isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.arrow_upward),
                          title: const Text('..'),
                          onTap: () => _load(path: parent ?? ''),
                        ),
                      if (entries.isEmpty && !_loading)
                        const ListTile(title: Text('Empty directory')),
                      for (final e in entries.whereType<Map>())
                        ListTile(
                          leading: Icon(
                            e['type'] == 'dir' ? Icons.folder : Icons.insert_drive_file_outlined,
                          ),
                          title: Text(e['name']?.toString() ?? ''),
                          subtitle: e['type'] == 'file'
                              ? Text('${e['size'] ?? '?'} B', style: const TextStyle(fontSize: 11))
                              : const Text('directory', style: TextStyle(fontSize: 11)),
                          onTap: () => _openEntry(e),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
