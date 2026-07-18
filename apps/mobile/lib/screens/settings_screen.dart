import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_controller.dart';
import '../services/theme_controller.dart';

/// Device-local console settings (theme, text scale, compact, dashboard refresh).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _scroll = ScrollController();
  bool _wrapLines = false;
  String _prefQuery = '';
  bool _prefCase = false;
  bool _prefRegex = false;
  final _prefFilterCtrl = TextEditingController();

  @override
  void dispose() {
    _prefFilterCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _matchPref(String title, [String subtitle = '']) {
    final raw = _prefQuery.trim();
    if (raw.isEmpty) return true;
    final hayRaw = '$title $subtitle';
    if (_prefRegex) {
      try {
        final re = RegExp(raw, caseSensitive: _prefCase);
        return re.hasMatch(hayRaw);
      } catch (_) {
        return false;
      }
    }
    if (_prefCase) {
      return title.contains(raw) || subtitle.contains(raw);
    }
    final q = raw.toLowerCase();
    return title.toLowerCase().contains(q) || subtitle.toLowerCase().contains(q);
  }

  Widget _sub(String text, {bool three = false}) {
    return Text(
      text,
      maxLines: _wrapLines ? (three ? 12 : 6) : (three ? 3 : 2),
      overflow: TextOverflow.ellipsis,
      softWrap: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final settings = context.watch<AppSettingsController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            tooltip: 'Jump to top',
            onPressed: () {
              if (!_scroll.hasClients) return;
              _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
            },
            icon: const Icon(Icons.vertical_align_top),
          ),
          IconButton(
            tooltip: 'Jump to end',
            onPressed: () {
              if (!_scroll.hasClients) return;
              _scroll.animateTo(
                _scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            },
            icon: const Icon(Icons.vertical_align_bottom),
          ),
          IconButton(
            tooltip: _wrapLines ? 'Clamp details' : 'Wrap details',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
          ),

        ],
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          TextField(
            controller: _prefFilterCtrl,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: IconButton(
                tooltip: _prefRegex
                    ? (_prefCase
                        ? 'Regex · case on (long-press: plain filter)'
                        : 'Regex · case off (long-press: plain filter)')
                    : (_prefCase
                        ? 'Case-sensitive (long-press: regex)'
                        : 'Case-insensitive (long-press: regex)'),
                icon: Icon(
                  _prefRegex
                      ? Icons.code
                      : (_prefCase ? Icons.text_fields : Icons.search),
                  size: 18,
                ),
                onPressed: () => setState(() => _prefCase = !_prefCase),
                onLongPress: () => setState(() => _prefRegex = !_prefRegex),
              ),
              hintText: _prefRegex
                  ? (_prefCase ? 'Filter settings (regex · case)' : 'Filter settings (regex)')
                  : (_prefCase ? 'Filter settings (case-sensitive)' : 'Filter settings'),
              border: const OutlineInputBorder(),
              suffixIcon: _prefQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _prefFilterCtrl.clear();
                        setState(() => _prefQuery = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _prefQuery = v),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: const Text('Wrap', style: TextStyle(fontSize: 11)),
                    selected: _wrapLines,
                    onSelected: (v) => setState(() => _wrapLines = v),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: const Text('Regex', style: TextStyle(fontSize: 11)),
                    selected: _prefRegex,
                    onSelected: (v) => setState(() => _prefRegex = v),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: const Text('Case', style: TextStyle(fontSize: 11)),
                    selected: _prefCase,
                    onSelected: (v) => setState(() => _prefCase = v),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_matchPref('Appearance', 'theme contrast text size compact'))
            Text('Appearance', style: Theme.of(context).textTheme.titleSmall),
          if (_matchPref('Appearance', 'theme contrast text size compact'))
            const SizedBox(height: 4),
          if (_matchPref('Theme', theme.label))
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
          if (_matchPref('High contrast', 'borders contrast'))
          SwitchListTile(
            secondary: const Icon(Icons.contrast),
            title: const Text('High contrast'),
            subtitle: _sub('Stronger borders and higher contrast surfaces'),
            value: settings.highContrast,
            onChanged: settings.setHighContrast,
          ),
          if (_matchPref('Text size', 'percent'))
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
          if (_matchPref('Compact lists', 'dense'))
          SwitchListTile(
            secondary: const Icon(Icons.view_compact_alt_outlined),
            title: const Text('Compact lists'),
            subtitle: _sub('Denser session tiles and menus'),
            value: settings.compactMode,
            onChanged: settings.setCompactMode,
          ),
          const Divider(height: 28),
          if (_matchPref('Sessions', 'sort'))
          Text('Sessions', style: Theme.of(context).textTheme.titleSmall),
          if (_matchPref('Default sort', 'session sort'))
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
                  ('model', 'Model'),
                  ('key', 'Key'),
                  ('platform', 'Platform'),
                  ('agent', 'Agent'),
                  ('mode', 'Mode'),
                  ('workdir', 'Workdir'),
                  ('running', 'Running'),
                  ('live', 'Live'),
                  ('last', 'Last msg'),
                  ('pinned', 'Pinned'),
                  ('note', 'Note'),
                  ('archived', 'Archived'),
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
          if (_matchPref('Console', 'tools haptic'))
          Text('Console', style: Theme.of(context).textTheme.titleSmall),
          if (_matchPref('Dashboard auto-refresh', 'seconds'))
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
          if (_matchPref('Show tool messages by default', 'tools'))
          if (_matchPref('Haptic feedback', 'buzz'))
          SwitchListTile(
            secondary: const Icon(Icons.build_circle_outlined),
            title: const Text('Show tool messages by default'),
            subtitle: _sub('Chat can still toggle tools if Host exposes them'),
            value: settings.showToolsDefault,
            onChanged: settings.setShowToolsDefault,
          ),
          if (_matchPref('Keep screen on', 'awake'))
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Haptic feedback'),
            subtitle: _sub('Light buzz on pin / send / copy'),
            value: settings.hapticsEnabled,
            onChanged: settings.setHapticsEnabled,
          ),
          if (_matchPref('Monospace chat', 'mono'))
          SwitchListTile(
            secondary: const Icon(Icons.smartphone),
            title: const Text('Keep screen on'),
            subtitle: _sub('Device-local preference while using the console'),
            value: settings.keepScreenOn,
            onChanged: settings.setKeepScreenOn,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.font_download_outlined),
            title: const Text('Monospace chat'),
            subtitle: _sub('Use mono font for message bodies'),
            value: settings.monoChat,
            onChanged: settings.setMonoChat,
          ),
          if (_matchPref('Auto-reconnect Bridge', 'reconnect'))
          SwitchListTile(
            secondary: const Icon(Icons.wifi_protected_setup),
            title: const Text('Auto-reconnect Bridge'),
            subtitle: _sub('Retry when chat WS drops · device-local'),
            value: settings.autoReconnect,
            onChanged: settings.setAutoReconnect,
          ),
          if (_matchPref('Reconnect attempts', 'max reconnect'))
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('Reconnect attempts'),
            subtitle: Text('Max ${settings.maxReconnectAttempts} · silent backoff'),
          ),
          if (_matchPref('Reconnect attempts', 'max reconnect'))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final n in const [1, 3, 5, 8, 10])
                  ChoiceChip(
                    label: Text('$n'),
                    selected: settings.maxReconnectAttempts == n,
                    onSelected: settings.autoReconnect
                        ? (_) => settings.setMaxReconnectAttempts(n)
                        : null,
                  ),
              ],
            ),
          ),
          if (_matchPref('Chat text size', 'body scale'))
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
          if (_matchPref('Terminal text size', 'term scale'))
          ListTile(
            leading: const Icon(Icons.terminal),
            title: const Text('Terminal text size'),
            subtitle: Text('Mono scale · ${settings.terminalFontScale.toStringAsFixed(2)}x'),
          ),
          if (_matchPref('Terminal text size', 'term scale'))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final s in const [0.85, 1.0, 1.15, 1.3])
                  ChoiceChip(
                    label: Text('${s}x'),
                    selected: (settings.terminalFontScale - s).abs() < 0.001,
                    onSelected: (_) => settings.setTerminalFontScale(s),
                  ),
              ],
            ),
          ),
          const Divider(height: 28),
          if (_matchPref('Device data', 'prefs reset'))
          Text('Device data', style: Theme.of(context).textTheme.titleSmall),
          if (_matchPref('Copy local prefs', 'export'))
          ListTile(
            leading: const Icon(Icons.ios_share_outlined),
            title: const Text('Copy local prefs'),
            subtitle: _sub('Theme + console prefs only · no tokens / host secrets'),
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
                'auto_reconnect: ${settings.autoReconnect}',
                'max_reconnect_attempts: ${settings.maxReconnectAttempts}',
                'terminal_font_scale: ${settings.terminalFontScale}',
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
          if (_matchPref('Reset console prefs', 'defaults'))
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Reset console prefs'),
            subtitle: _sub('Defaults for theme-adjacent console options · no host tokens'),
            trailing: const Icon(Icons.restore_outlined),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Reset console prefs?'),
                  content: const Text(
                    'Restores local console defaults (scale, compact, refresh, haptics, mono chat, etc.). Host profiles and tokens are not touched.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              await settings.resetConsolePrefs();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Console prefs reset to defaults'), duration: Duration(seconds: 1)),
              );
            },
          ),

          const Divider(height: 28),
          if (_matchPref('About', 'console only'))
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: _sub(
              'HuanHermes is a remote console only. Settings stay on this device. '
              'No agent loop runs on the phone. Multi-host profiles live on Connect.',
              three: true,
            ),
            isThreeLine: true,
          ),
          if (_matchPref('App version', 'version'))
          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('App version'),
            subtitle: _sub('0.1.139+139 · console only · protocol Mock/self-host'),
            trailing: IconButton(
              tooltip: 'Copy about',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () async {
                const text =
                    'HuanHermes App 0.1.139+139\nconsole only · protocol Mock/self-host\nNo agent loop on device · tokens never in about text';
                await Clipboard.setData(const ClipboardData(text: text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('About copied'), duration: Duration(seconds: 1)),
                  );
                }
              },
            ),
          ),
          if (_matchPref('Privacy notes', 'tokens'))
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Privacy notes'),
            subtitle: _sub(
              'Tokens stay in secure storage. Pairing URI / exports never include tokens. '
              'Pins, notes, drafts, recents, audit are device-local.',
              three: true,
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
      case 'model':
        return 'By model then title';
      case 'key':
        return 'By session key then title';
      case 'platform':
        return 'By platform then title';
      case 'agent':
        return 'By agent type then title';
      case 'mode':
        return 'By mode then title';
      case 'workdir':
        return 'By workdir then title';
      case 'running':
        return 'Running first (then title)';
      case 'live':
        return 'Live first (then title)';
      case 'last':
        return 'By last user message then title';
      case 'pinned':
        return 'Pinned first (then title; respects direction)';
      case 'note':
        return 'By local session note then title';
      case 'archived':
        return 'Archived first (then title; respects direction)';
      case 'recent':
        return 'By recently opened on this device (pins still first)';
      default:
        return 'By last updated (newest first)';
    }
  }
}
