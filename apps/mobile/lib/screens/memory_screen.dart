import 'package:flutter/material.dart';

import '../models/connection_config.dart';
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
  String _q = '';
  List<Map<String, dynamic>> _items = [];
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host memory'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _scope,
                    decoration: const InputDecoration(
                      labelText: 'Scope',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('all')),
                      DropdownMenuItem(value: 'global', child: Text('global')),
                      DropdownMenuItem(value: 'project', child: Text('project')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _scope = v);
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search title/content',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () {
                          setState(() => _q = _search.text.trim());
                          _load();
                        },
                      ),
                    ),
                    onSubmitted: (v) {
                      setState(() => _q = v.trim());
                      _load();
                    },
                  ),
                ),
              ],
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
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final m = _items[i];
                      final title = (m['title'] ?? m['id'] ?? 'memory').toString();
                      final content = (m['content'] ?? '').toString();
                      final scope = (m['scope'] ?? '').toString();
                      final type = (m['type'] ?? '').toString();
                      final conf = (m['confidence'] ?? '').toString();
                      return ListTile(
                        leading: Icon(
                          scope == 'project' ? Icons.folder_special_outlined : Icons.psychology_outlined,
                        ),
                        title: Text(title),
                        subtitle: Text(
                          '[$scope/$type${conf.isNotEmpty ? ' · $conf' : ''}]\n'
                          '${content.length > 160 ? '${content.substring(0, 160)}…' : content}',
                        ),
                        isThreeLine: true,
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  '# $title\n\nscope: $scope\ntype: $type\nconfidence: $conf\n\n$content',
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
