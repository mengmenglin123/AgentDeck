import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_controller.dart';
import '../services/theme_controller.dart';

/// Device-local console settings (theme, text scale, compact, dashboard refresh).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final settings = context.watch<AppSettingsController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Text('Appearance', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          ListTile(
            leading: Icon(theme.icon),
            title: const Text('Theme'),
            subtitle: Text(theme.label),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Auto'), icon: Icon(Icons.brightness_auto, size: 16)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode, size: 16)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode, size: 16)),
              ],
              selected: {theme.mode},
              onSelectionChanged: (s) => theme.setMode(s.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('Text size'),
            subtitle: Text('${(settings.textScale * 100).round()}%'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final v in const [0.85, 1.0, 1.15, 1.3])
                  ChoiceChip(
                    label: Text('${(v * 100).round()}%'),
                    selected: (settings.textScale - v).abs() < 0.01,
                    onSelected: (_) => settings.setTextScale(v),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.view_compact_alt_outlined),
            title: const Text('Compact lists'),
            subtitle: const Text('Denser session tiles and menus'),
            value: settings.compactMode,
            onChanged: settings.setCompactMode,
          ),
          const Divider(height: 28),
          Text('Console', style: Theme.of(context).textTheme.titleSmall),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Dashboard auto-refresh'),
            subtitle: Text(
              settings.dashboardRefreshSec == 0
                  ? 'Off'
                  : 'Every ${settings.dashboardRefreshSec}s',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final sec in const [0, 10, 15, 30, 60])
                  ChoiceChip(
                    label: Text(sec == 0 ? 'Off' : '${sec}s'),
                    selected: settings.dashboardRefreshSec == sec,
                    onSelected: (_) => settings.setDashboardRefreshSec(sec),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.build_circle_outlined),
            title: const Text('Show tool messages by default'),
            subtitle: const Text('Chat can still toggle tools if Host exposes them'),
            value: settings.showToolsDefault,
            onChanged: settings.setShowToolsDefault,
          ),
          const Divider(height: 28),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text(
              'HuanHermes is a remote console only. Settings stay on this device. '
              'No agent loop runs on the phone.',
            ),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }
}
