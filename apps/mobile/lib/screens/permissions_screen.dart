import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/catalog_ui.dart';
import '../utils/query_match.dart';

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
  /// 自动批准规则: tool name → auto-approve level
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
        title: const Text('权限'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _filter = v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pending', child: Text('待处理')),
              const PopupMenuItem(value: 'all', child: Text('全部')),
              const PopupMenuItem(value: 'approved', child: Text('已批准')),
              const PopupMenuItem(value: 'denied', child: Text('已拒绝')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: Column(
        children: [
          // 自动批准规则 section
          Card(
            margin: const EdgeInsets.all(8),
            child: ExpansionTile(
              title: const Text('自动批准规则'),
              subtitle: Text('已配置 ${_autoApproveRules.length} 条规则'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '匹配这些规则的工具将自动批准，不再提示。',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _buildRuleChip('file_read', '读文件', cs),
                          _buildRuleChip('file_write', '写文件', cs),
                          _buildRuleChip('terminal', '终端命令', cs),
                          _buildRuleChip('browser', '浏览网页', cs),
                          _buildRuleChip('search', '搜索', cs),
                          ActionChip(
                            label: const Text('+ 添加规则'),
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
                  '待处理',
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
                  '已批准',
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
                  '已拒绝',
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
                              ? '暂无待处理权限'
                              : '暂无权限历史',
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
    final toolName = toolMatch?.group(1) ?? '未知';

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
                    '工具：$toolName',
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
                      '待处理',
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
                            isDeny ? '权限已拒绝' : '权限已授予',
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isDeny ? cs.errorContainer : cs.primaryContainer,
                    ),
                    child: Text(b['text']?.toString() ?? '操作'),
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
        title: const Text('添加自动批准规则'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: '工具名（如 file_read）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final tool = ctrl.text.trim();
              if (tool.isNotEmpty) {
                setState(() => _autoApproveRules[tool] = 'auto');
              }
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}
