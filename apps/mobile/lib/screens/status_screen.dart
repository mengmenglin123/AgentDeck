import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/connection_controller.dart';

/// Post-connect landing (P0-7). Sessions/chat land in P0-8.
class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ConnectionController>();
    final cfg = c.saved!;
    final status = c.lastStatus ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Host connected'),
        actions: [
          IconButton(
            tooltip: 'Disconnect',
            onPressed: () => c.disconnect(),
            icon: const Icon(Icons.link_off),
          ),
          IconButton(
            tooltip: 'Clear saved profile',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear saved profile?'),
                  content: const Text(
                    'Removes host settings and tokens from secure storage.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await c.disconnect(clearStorage: true);
              }
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.dns_outlined),
            title: Text(cfg.host),
            subtitle: Text(
              'Mgmt ${cfg.mgmtBaseUrl}
Bridge ${cfg.bridgeWsUrlRedacted}',
            ),
            isThreeLine: true,
          ),
          const Divider(),
          Text('Management /status', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (status.isEmpty)
            const Text('No status payload (re-test from Connect).')
          else
            ...status.entries.map(
              (e) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(e.key),
                subtitle: Text('${e.value}'),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Next: P0-8 session list + chat streaming.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => c.disconnect(),
            icon: const Icon(Icons.edit),
            label: const Text('Edit connection'),
          ),
        ],
      ),
    );
  }
}
