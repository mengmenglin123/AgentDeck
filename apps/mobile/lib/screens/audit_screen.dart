import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/audit_log.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, required this.audit});

  final AuditLog audit;

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final _q = TextEditingController();
  String _query = '';
  /// all | info | warn | error
  String _level = 'all';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<AuditEntry> _filter(List<AuditEntry> all) {
    Iterable<AuditEntry> it = all;
    if (_level != 'all') {
      it = it.where((e) => e.level == _level);
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      it = it.where((e) {
        final hay = '${e.action} ${e.detail} ${e.level}'.toLowerCase();
        return hay.contains(q);
      });
    }
    return it.toList();
  }

  @override
  Widget build(BuildContext context) {
    final audit = widget.audit;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit log'),
        actions: [
          IconButton(
            tooltip: 'Copy visible',
            onPressed: () async {
              final items = _filter(audit.entries.reversed.toList());
              final buf = StringBuffer();
              for (final e in items) {
                buf.writeln('${e.ts.toIso8601String()} [${e.level}] ${e.action} ${e.detail}');
              }
              await Clipboard.setData(ClipboardData(text: buf.toString()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied ${items.length} lines'), duration: const Duration(seconds: 1)),
                );
              }
            },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Copy JSON',
            onPressed: () async {
              final items = _filter(audit.entries.reversed.toList());
              final payload = {
                'exported_at': DateTime.now().toIso8601String(),
                'count': items.length,
                'entries': [
                  for (final e in items)
                    {
                      'ts': e.ts.toIso8601String(),
                      'level': e.level,
                      'action': e.action,
                      'detail': e.detail,
                    },
                ],
              };
              final text = const JsonEncoder.withIndent('  ').convert(payload);
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied JSON (${items.length})'), duration: const Duration(seconds: 1)),
                );
              }
            },
            icon: const Icon(Icons.data_object),
          ),
          IconButton(
            tooltip: 'Clear',
            onPressed: audit.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                hintText: 'Filter action / detail',
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search, size: 20),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in const [
                  ('all', 'All'),
                  ('info', 'Info'),
                  ('warn', 'Warn'),
                  ('error', 'Error'),
                ])
                  FilterChip(
                    label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                    selected: _level == f.$1,
                    onSelected: (_) => setState(() => _level = f.$1),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: audit,
              builder: (context, _) {
                final items = _filter(audit.entries.reversed.toList());
                if (audit.entries.isEmpty) {
                  return const Center(child: Text('No audit events yet.'));
                }
                if (items.isEmpty) {
                  return const Center(child: Text('No events match filter'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                    await Future<void>.delayed(const Duration(milliseconds: 200));
                  },
                  child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = items[i];
                    final color = e.level == 'error'
                        ? Colors.red
                        : e.level == 'warn'
                            ? Colors.orange
                            : null;
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.circle, size: 10, color: color ?? Colors.green),
                      title: Text(e.action),
                      subtitle: Text(
                        '${e.ts.toIso8601String().substring(11, 19)}  ${e.detail}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onLongPress: () async {
                        await Clipboard.setData(
                          ClipboardData(text: '${e.ts.toIso8601String()} [${e.level}] ${e.action} ${e.detail}'),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Entry copied'), duration: Duration(seconds: 1)),
                          );
                        }
                      },
                    );
                  },
                ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
