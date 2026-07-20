import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../models/session_info.dart';
import '../services/connection_controller.dart';
import '../widgets/console_widgets.dart';
import 'activity_screen.dart';
import 'agents_screen.dart';
import 'cron_screen.dart';
import 'diff_screen.dart';
import 'logs_screen.dart';
import 'mcp_screen.dart';
import 'memory_screen.dart';
import 'pairing_screen.dart';
import 'skills_screen.dart';
import 'status_screen.dart';
import 'terminal_screen.dart';
import 'workspace_screen.dart';

/// Discoverable hub for Host directory / console tools.
class ToolsHubScreen extends StatelessWidget {
  const ToolsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionController>();
    final cfg = conn.saved;
    final cs = Theme.of(context).colorScheme;

    final tools = <({
      IconData icon,
      String label,
      String subtitle,
      Color color,
      VoidCallback? onTap,
    })>[
      (
        icon: Icons.terminal,
        label: AppStrings.toolTerminal,
        subtitle: '远程终端通道',
        color: const Color(0xFF0EA5E9),
        onTap: cfg == null
            ? null
            : () {
                final session = SessionInfo(
                  id: 'term-adhoc',
                  sessionKey: 'adhoc',
                  title: '终端',
                  project: 'console',
                );
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        TerminalScreen(config: cfg, session: session),
                  ),
                );
              },
      ),
      (
        icon: Icons.folder_open_outlined,
        label: AppStrings.toolWorkspace,
        subtitle: '只读工作区与 Git',
        color: const Color(0xFFF59E0B),
        onTap: cfg == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WorkspaceScreen(config: cfg),
                  ),
                ),
      ),
      (
        icon: Icons.auto_awesome_outlined,
        label: AppStrings.toolSkills,
        subtitle: '技能目录',
        color: const Color(0xFF8B5CF6),
        onTap: cfg == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => SkillsScreen(config: cfg)),
                ),
      ),
      (
        icon: Icons.extension_outlined,
        label: AppStrings.toolMcp,
        subtitle: 'MCP 目录',
        color: const Color(0xFF14B8A6),
        onTap: cfg == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => McpScreen(config: cfg)),
                ),
      ),
      (
        icon: Icons.schedule_outlined,
        label: AppStrings.toolCron,
        subtitle: '定时任务',
        color: const Color(0xFFEF4444),
        onTap: cfg == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => CronScreen(config: cfg)),
                ),
      ),
      (
        icon: Icons.psychology_outlined,
        label: AppStrings.toolMemory,
        subtitle: '主机记忆',
        color: const Color(0xFFEC4899),
        onTap: cfg == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => MemoryScreen(config: cfg)),
                ),
      ),
      (
        icon: Icons.smart_toy_outlined,
        label: AppStrings.toolAgents,
        subtitle: 'Agents 目录',
        color: const Color(0xFF6366F1),
        onTap: cfg == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => AgentsScreen(config: cfg)),
                ),
      ),
      (
        icon: Icons.receipt_long_outlined,
        label: AppStrings.toolLogs,
        subtitle: '主机日志',
        color: const Color(0xFF64748B),
        onTap: cfg == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => LogsScreen(config: cfg)),
                ),
      ),
      (
        icon: Icons.timeline_outlined,
        label: AppStrings.toolActivity,
        subtitle: '活动事件流',
        color: const Color(0xFF22C55E),
        onTap: cfg == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ActivityScreen(config: cfg),
                  ),
                ),
      ),
      (
        icon: Icons.difference_outlined,
        label: AppStrings.toolDiff,
        subtitle: 'Git diff 可视化',
        color: const Color(0xFFA855F7),
        onTap: cfg == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => DiffScreen(config: cfg)),
                ),
      ),
      (
        icon: Icons.qr_code_2_outlined,
        label: AppStrings.toolPairing,
        subtitle: '配对 URI / 指纹',
        color: const Color(0xFF06B6D4),
        onTap: cfg == null
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PairingScreen(config: cfg)),
                ),
      ),
      (
        icon: Icons.health_and_safety_outlined,
        label: AppStrings.toolStatus,
        subtitle: '连接健康',
        color: cs.primary,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StatusScreen()),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.toolsTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                AppStrings.toolsSubtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ),
      ),
      body: cfg == null
          ? const ConsoleEmptyState(
              icon: Icons.link_off,
              title: '尚未连接 Host',
              subtitle: '请先完成连接测试',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 900
                    ? 4
                    : constraints.maxWidth >= 600
                        ? 3
                        : 2;
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: tools.length,
                  itemBuilder: (context, i) {
                    final t = tools[i];
                    return ConsoleToolTile(
                      icon: t.icon,
                      label: t.label,
                      subtitle: t.subtitle,
                      color: t.color,
                      onTap: t.onTap,
                    );
                  },
                );
              },
            ),
    );
  }
}
