import 'package:flutter/material.dart';

import '../models/connection_config.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';

/// Readonly unified diff viewer (`GET /workspace/diff`).
class DiffScreen extends StatefulWidget {
  const DiffScreen({super.key, required this.config, this.initialPath});

  final ConnectionConfig config;
  final String? initialPath;

  @override
  State<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends State<DiffScreen> {
  late final MgmtClient _mgmt = MgmtClient(config: widget.config);
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _files = [];
  String? _path;
  String _diff = '';

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _mgmt.workspaceDiff();
      final raw = data['files'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      setState(() {
        _files = list;
        _loading = false;
      });
      final target = _path ?? (list.isNotEmpty ? list.first['path']?.toString() : null);
      if (target != null && target.isNotEmpty) {
        await _loadPath(target);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = Security.redactText(e.toString());
      });
    }
  }

  Future<void> _loadPath(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _path = path;
    });
    try {
      final data = await _mgmt.workspaceDiff(path: path);
      setState(() {
        _diff = (data['diff'] ?? '').toString();
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
        title: Text(_path == null ? 'Git diff' : 'Diff · $_path'),
        actions: [
          IconButton(onPressed: _loading ? null : _loadIndex, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_files.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                itemCount: _files.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final p = (_files[i]['path'] ?? '').toString();
                  final selected = p == _path;
                  return ChoiceChip(
                    label: Text(p, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) => _loadPath(p),
                  );
                },
              ),
            ),
          Expanded(
            child: _diff.isEmpty
                ? const Center(child: Text('No diff'))
                : Container(
                    width: double.infinity,
                    color: Colors.black,
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: _DiffText(diff: _diff),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DiffText extends StatelessWidget {
  const _DiffText({required this.diff});
  final String diff;

  @override
  Widget build(BuildContext context) {
    final lines = diff.replaceAll('\r\n', '\n').split('\n');
    return SelectableText.rich(
      TextSpan(
        children: [
          for (final line in lines)
            TextSpan(
              text: '$line\n',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.35,
                color: line.startsWith('+') && !line.startsWith('+++')
                    ? const Color(0xFF81C784)
                    : line.startsWith('-') && !line.startsWith('---')
                        ? const Color(0xFFE57373)
                        : line.startsWith('@@')
                            ? const Color(0xFF64B5F6)
                            : const Color(0xFFB0BEC5),
              ),
            ),
        ],
      ),
    );
  }
}
