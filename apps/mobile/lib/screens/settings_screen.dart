import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          SwitchListTile(
            secondary: const Icon(Icons.contrast),
            title: const Text('High contrast'),
            subtitle: const Text('Stronger borders and higher contrast surfaces'),
            value: settings.highContrast,
            onChanged: settings.setHighContrast,
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
          Text('Sessions', style: Theme.of(context).textTheme.titleSmall),
          ListTile(
            leading: const Icon(Icons.sort),
            title: const Text('Default sort'),
            subtitle: Text(_sortLabel(settings.sessionSort)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final e in const [
                  ('updated', 'Updated'),
                  ('recent', 'Recent'),
                  ('title', 'Title'),
                  ('project', 'Project'),
                  ('created', 'Created'),
                ])
                  ChoiceChip(
                    label: Text(e.$2),
                    selected: settings.sessionSort == e.$1,
                    onSelected: (_) => settings.setSessionSort(e.$1),
                  ),
              ],
            ),
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
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Haptic feedback'),
            subtitle: const Text('Light buzz on pin / send / copy'),
            value: settings.hapticsEnabled,
            onChanged: settings.setHapticsEnabled,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.smartphone),
            title: const Text('Keep screen on'),
            subtitle: const Text('Device-local preference while using the console'),
            value: settings.keepScreenOn,
            onChanged: settings.setKeepScreenOn,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.font_download_outlined),
            title: const Text('Monospace chat'),
            subtitle: const Text('Use mono font for message bodies'),
            value: settings.monoChat,
            onChanged: settings.setMonoChat,
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('Chat text size'),
            subtitle: Text('Body scale · ${settings.chatFontScale.toStringAsFixed(2)}x'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final s in const [0.9, 1.0, 1.15, 1.3])
                  ChoiceChip(
                    label: Text('${s}x'),
                    selected: (settings.chatFontScale - s).abs() < 0.001,
                    onSelected: (_) => settings.setChatFontScale(s),
                  ),
              ],
            ),
          ),
          const Divider(height: 28),
          Text('Device data', style: Theme.of(context).textTheme.titleSmall),
          ListTile(
            leading: const Icon(Icons.ios_share_outlined),
            title: const Text('Copy local prefs'),
            subtitle: const Text('Theme + console prefs only · no tokens / host secrets'),
            trailing: const Icon(Icons.copy_all_outlined),
            onTap: () async {
              final text = [
                'huanhermes.local_prefs.v1',
                'theme: ${theme.mode.name}',
                'text_scale: ${settings.textScale}',
                'chat_font_scale: ${settings.chatFontScale}',
                'compact_mode: ${settings.compactMode}',
                'high_contrast: ${settings.highContrast}',
                'session_sort: ${settings.sessionSort}',
                'dashboard_refresh_sec: ${settings.dashboardRefreshSec}',
                'show_tools_default: ${settings.showToolsDefault}',
                'haptics: ${settings.hapticsEnabled}',
                'keep_screen_on: ${settings.keepScreenOn}',
                'mono_chat: ${settings.monoChat}',
              ].join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Local prefs copied (no tokens)'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
          const Divider(height: 28),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text(
              'HuanHermes is a remote console only. Settings stay on this device. '
              'No agent loop runs on the phone. Multi-host profiles live on Connect.',
            ),
            isThreeLine: true,
          ),
          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('App version'),
            subtitle: const Text('0.1.38+38 · console only · protocol Mock/self-host'),
          ),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Privacy notes'),
            subtitle: const Text(
              'Tokens stay in secure storage. Pairing URI / exports never include tokens. '
              'Pins, notes, drafts, recents, audit are device-local.',
            ),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }

  static String _sortLabel(String k) {
    switch (k) {
      case 'title':
        return 'By title A–Z (pins still first)';
      case 'project':
        return 'By project then title';
      case 'created':
        return 'By created time (newest first)';
      case 'recent':
        return 'By recently opened on this device (pins still first)';
      default:
        return 'By last updated (newest first)';
    }
  }
}
