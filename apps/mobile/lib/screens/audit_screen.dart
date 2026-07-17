import 'package:flutter/material.dart';

import '../services/audit_log.dart';

class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key, required this.audit});

  final AuditLog audit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit log'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            onPressed: audit.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: audit,
        builder: (context, _) {
          final items = audit.entries.reversed.toList();
          if (items.isEmpty) {
            return const Center(child: Text('No audit events yet.'));
          }
          return ListView.separated(
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
              );
            },
          );
        },
      ),
    );
  }
}
