import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme.dart';
import '../widgets/console_widgets.dart';
import '../l10n/app_strings.dart';
import '../services/connection_controller.dart';
import '../services/session_controller.dart';
import 'connect_screen.dart';
import 'host_dashboard_screen.dart';
import 'sessions_screen.dart';
import 'settings_screen.dart';
import 'tools_hub_screen.dart';
import '../widgets/agent_scope_selector.dart';

/// Primary navigation shell after a successful Host connection.
/// Tabs: 会话 · 主机 · 工具 · 设置
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.initialIndex = 0,
    this.initialSessionRef,
  }) : assert(initialIndex >= 0 && initialIndex < 4);

  final int initialIndex;
  final String? initialSessionRef;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index;
  SessionController? _sessions;
  String? _sessionConfigKey;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final config = context.watch<ConnectionController>().saved;
    if (config == null) return;
    final key = '${config.host}:${config.mgmtPort}:${config.deviceId}';
    if (_sessions == null || _sessionConfigKey != key) {
      _sessions?.dispose();
      _sessions = SessionController(config: config)..refresh();
      _sessionConfigKey = key;
    } else {
      _sessions!.updateConfig(config);
    }
  }

  @override
  void dispose() {
    _sessions?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionController>();
    final ready = conn.isReady;
    if (!ready) {
      return const Scaffold(
        body: ConsoleLoading(label: AppStrings.connecting),
      );
    }

    final sessions = _sessions;
    if (sessions == null) {
      return const Scaffold(body: ConsoleLoading(label: AppStrings.loading));
    }

    final pages = <Widget>[
      SessionsScreen(
        embedded: true,
        initialSessionRef: widget.initialSessionRef,
      ),
      const HostDashboardScreen(),
      const ToolsHubScreen(),
      const SettingsScreen(),
    ];

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final host = conn.saved?.host ?? '—';
    final degraded = conn.healthDegraded;
    final statusColor = degraded ? AppTheme.warning : AppTheme.success;
    final statusLabel = degraded ? '心跳降级' : AppStrings.hostOnline;

    return ChangeNotifierProvider<SessionController>.value(
      value: sessions,
      child: Scaffold(
        body: Column(
          children: [
            Material(
              color: isDark
                  ? const Color(0xFF0F1011)
                  : cs.surface.withValues(alpha: 0.96),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 10, 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : cs.outlineVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.45),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                statusLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.1,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                host,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
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
                    if (sessions.projects.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      AgentScopeSelector(sessions: sessions),
                    ],
                  ],
                ),
              ),
            ),
            ),
            ),
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
      ),
    );
  }
}
