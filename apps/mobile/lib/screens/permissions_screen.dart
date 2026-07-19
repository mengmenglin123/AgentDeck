import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/chat_controller.dart';
import '../services/notification_service.dart';

/// Screen for managing agent permission requests.
/// Shows pending approvals, history, and auto-approve rules.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, required this.chat});
  final ChatController chat;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  /// Auto-approve rules: tool name → auto-approve level
  final Map<String, String> _autoApproveRules = {};

  /// Filter: 'pending', 'all', 'approved', 'denied'
  String _filter = 'pending';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chat = widget.chat;

    // Filter permission messages from transcript
    final permMessages = chat.messages.where((m) {
      if (_filter == 'pending')
        return m.role == 'permission' &&
            (m.meta['buttons'] as List? ?? []).isNotEmpty;
      if (_filter == 'approved')
        return m.role == 'permission' && m.content.contains('allow');
      if (_filter == 'denied')
        return m.role == 'permission' && m.content.contains('deny');
      return m.role == 'permission';
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _filter = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pending', child: Text('Pending')),
              const PopupMenuItem(value: 'all', child: Text('All')),
              const PopupMenuItem(value: 'approved', child: Text('Approved')),
              const PopupMenuItem(value: 'denied', child: Text('Denied')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: Column(
        children: [
          // Auto-approve rules section
          Card(
            margin: const EdgeInsets.all(8),
            child: ExpansionTile(
              title: const Text('Auto-approve rules'),
              subtitle: Text('${_autoApproveRules.length} rules configured'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tools matching these rules will be auto-approved without prompting.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _buildRuleChip('file_read', 'Read files', cs),
                          _buildRuleChip('file_write', 'Write files', cs),
                          _buildRuleChip('terminal', 'Run commands', cs),
                          _buildRuleChip('browser', 'Browse web', cs),
                          _buildRuleChip('search', 'Search', cs),
                          ActionChip(
                            label: const Text('+ Add rule'),
                            onPressed: () => _showAddRuleDialog(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Stats bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _buildStat(
                  'Pending',
                  chat.messages
                      .where(
                        (m) =>
                            m.role == 'permission' &&
                            (m.meta['buttons'] as List? ?? []).isNotEmpty,
                      )
                      .length,
                  Colors.orange,
                ),
                const SizedBox(width: 16),
                _buildStat(
                  'Approved',
                  chat.messages
                      .where(
                        (m) =>
                            m.role == 'permission' &&
                            m.content.contains('allow'),
                      )
                      .length,
                  Colors.green,
                ),
                const SizedBox(width: 16),
                _buildStat(
                  'Denied',
                  chat.messages
                      .where(
                        (m) =>
                            m.role == 'permission' &&
                            m.content.contains('deny'),
                      )
                      .length,
                  Colors.red,
                ),
              ],
            ),
          ),

          const Divider(),

          // Permission list
          Expanded(
            child: permMessages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _filter == 'pending'
                              ? Icons.check_circle_outline
                              : Icons.history,
                          size: 48,
                          color: cs.onSurfaceVariant.withOpacity(0.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _filter == 'pending'
                              ? 'No pending permissions'
                              : 'No permission history',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: permMessages.length,
                    itemBuilder: (ctx, i) {
                      final msg = permMessages[i];
                      final isPending =
                          (msg.meta['buttons'] as List? ?? []).isNotEmpty;
                      return _buildPermissionCard(msg, isPending, cs);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleChip(String tool, String label, ColorScheme cs) {
    final active = _autoApproveRules.containsKey(tool);
    return FilterChip(
      label: Text(label),
      selected: active,
      onSelected: (v) {
        setState(() {
          if (v) {
            _autoApproveRules[tool] = 'auto';
          } else {
            _autoApproveRules.remove(tool);
          }
        });
      },
      selectedColor: cs.primaryContainer,
    );
  }

  Widget _buildStat(String label, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text('$label: $count', style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildPermissionCard(dynamic msg, bool isPending, ColorScheme cs) {
    final text = msg.content?.toString() ?? '';
    final buttons =
        (msg.meta['buttons'] as List? ?? []) as List<dynamic>? ?? [];
    final toolMatch = RegExp(r'tool[=:]\s*(\w+)').firstMatch(text);
    final toolName = toolMatch?.group(1) ?? 'unknown';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isPending
                      ? Icons.pending
                      : (text.contains('allow')
                          ? Icons.check_circle
                          : Icons.cancel),
                  color: isPending
                      ? Colors.orange
                      : (text.contains('allow') ? Colors.green : Colors.red),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tool: $toolName',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isPending)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'PENDING',
                      style: TextStyle(fontSize: 10, color: Colors.orange),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: const TextStyle(fontSize: 13),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (isPending && buttons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: buttons.map<Widget>((b) {
                  final action =
                      b['data']?.toString() ?? b['text']?.toString() ?? '';
                  final isDeny = action.contains('deny');
                  return FilledButton.tonal(
                    onPressed: () {
                      widget.chat.respondPermission(action);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isDeny ? 'Permission denied' : 'Permission granted',
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isDeny ? cs.errorContainer : cs.primaryContainer,
                    ),
                    child: Text(b['text']?.toString() ?? 'action'),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAddRuleDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add auto-approve rule'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'Tool name (e.g., file_read)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final tool = ctrl.text.trim();
              if (tool.isNotEmpty) {
                setState(() => _autoApproveRules[tool] = 'auto');
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
