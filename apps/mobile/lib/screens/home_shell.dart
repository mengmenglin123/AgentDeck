import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../services/connection_controller.dart';
import 'connect_screen.dart';
import 'host_dashboard_screen.dart';
import 'sessions_screen.dart';
import 'settings_screen.dart';
import 'tools_hub_screen.dart';

/// Primary navigation shell after a successful Host connection.
/// Tabs: 会话 · 主机 · 工具 · 设置
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionController>();
    final ready = conn.isReady;
    if (!ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final pages = <Widget>[
      const SessionsScreen(embedded: true),
      const HostDashboardScreen(),
      const ToolsHubScreen(),
      const SettingsScreen(),
    ];

    final cs = Theme.of(context).colorScheme;
    final host = conn.saved?.host ?? '—';
    final degraded = conn.healthDegraded;
    final statusColor = degraded ? Colors.orange : const Color(0xFF22C55E);
    final statusLabel = degraded ? '心跳降级' : AppStrings.hostOnline;

    return Scaffold(
      body: Column(
        children: [
          // LiveAgent-style connection strip (compact)
          Material(
            color: cs.surfaceContainerHighest.withOpacity(0.55),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withOpacity(0.45),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ConnectScreen(),
                          ),
                        );
                      },
                      child: const Text(AppStrings.switchConnection),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withOpacity(0.45)),
          Expanded(
            child: IndexedStack(index: _index, children: pages),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: AppStrings.tabSessions,
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: AppStrings.tabHost,
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: AppStrings.tabTools,
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: AppStrings.tabSettings,
          ),
        ],
      ),
    );
  }
}
