import 'package:flutter/material.dart';

import '../models/connection_config.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP (readonly)'),
        actions: [
          IconButton(
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Catalog only — App does not start MCP servers. Host owns tools.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (error != null)
                  Text(error!, style: TextStyle(color: cs.error)),
                if (servers.isEmpty && error == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: Text('No MCP servers reported')),
                  ),
                for (final s in servers)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.hub_outlined),
                      title: Text(s['name']?.toString() ?? 'unnamed'),
                      subtitle: Text(
                        [
                          if (s['description'] != null) s['description'].toString(),
                          if (s['status'] != null) 'status: ${s['status']}',
                          if (s['tools'] is List)
                            'tools: ${(s['tools'] as List).join(', ')}',
                        ].where((e) => e.isNotEmpty).join('\n'),
                      ),
                      isThreeLine: true,
                    ),
                  ),
              ],
            ),
    );
  }
}
