import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_controller.dart';
import '../services/theme_controller.dart';
import '../services/connection_controller.dart';
import '../l10n/app_strings.dart';

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
    return title.toLowerCase().contains(q) ||
        subtitle.toLowerCase().contains(q);
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
        title: const Text('设置'),
        actions: [
          IconButton(
            tooltip: '回到顶部',
            onPressed: () {
              if (!_scroll.hasClients) return;
              _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            },
            icon: const Icon(Icons.vertical_align_top),
          ),
          IconButton(
            tooltip: '跳到底部',
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
            tooltip: _wrapLines ? '截断详情' : '换行详情',
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
                        ? '正则 · 大小写 开（长按恢复普通筛选）'
                        : '正则 · 大小写 关（长按恢复普通筛选）')
                    : (_prefCase
                        ? '区分大小写（长按切换正则）'
                        : '不区分大小写（长按切换正则）'),
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
                  ? (_prefCase
                      ? '筛选设置（正则 · 大小写）'
                      : '筛选设置（正则）')
                  : (_prefCase
                      ? '筛选设置（区分大小写）'
                      : '筛选设置'),
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
                    label: const Text('换行', style: TextStyle(fontSize: 11)),
                    selected: _wrapLines,
                    onSelected: (v) => setState(() => _wrapLines = v),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: const Text(AppStrings.regex, style: TextStyle(fontSize: 11)),
                    selected: _prefRegex,
                    onSelected: (v) => setState(() => _prefRegex = v),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: const Text(AppStrings.matchCase, style: TextStyle(fontSize: 11)),
                    selected: _prefCase,
                    onSelected: (v) => setState(() => _prefCase = v),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_matchPref('外观', 'theme contrast text size compact'))
            Text('外观', style: Theme.of(context).textTheme.titleSmall),
          if (_matchPref('外观', 'theme contrast text size compact'))
            const SizedBox(height: 4),
          if (_matchPref('主题', theme.label))
            ListTile(
              leading: Icon(theme.icon),
              title: const Text('主题'),
              subtitle: Text(theme.label),
              trailing: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('自动'),
                    icon: Icon(Icons.brightness_auto, size: 16),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('浅色'),
                    icon: Icon(Icons.light_mode, size: 16),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('深色'),
                    icon: Icon(Icons.dark_mode, size: 16),
                  ),
                ],
                selected: {theme.mode},
                onSelectionChanged: (s) => theme.setMode(s.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ),
          if (_matchPref('高对比度', 'borders contrast'))
            SwitchListTile(
              secondary: const Icon(Icons.contrast),
              title: const Text('高对比度'),
              subtitle: _sub('更强描边与更高对比表面'),
              value: settings.highContrast,
              onChanged: settings.setHighContrast,
            ),
          if (_matchPref('文字大小', 'percent'))
            ListTile(
              leading: const Icon(Icons.format_size),
              title: const Text('文字大小'),
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
          if (_matchPref('紧凑列表', 'dense'))
            SwitchListTile(
              secondary: const Icon(Icons.view_compact_alt_outlined),
              title: const Text('紧凑列表'),
              subtitle: _sub('更紧凑的会话列表与菜单'),
              value: settings.compactMode,
              onChanged: settings.setCompactMode,
            ),
          const Divider(height: 28),
          if (_matchPref(AppStrings.sessionsLabel, 'sort'))
            Text(AppStrings.sessionsLabel, style: Theme.of(context).textTheme.titleSmall),
          if (_matchPref('默认排序', 'session sort'))
            ListTile(
              leading: const Icon(Icons.sort),
              title: const Text('默认排序'),
              subtitle: Text(_sortLabel(settings.sessionSort)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final e in const [
                  ('updated', '更新时间'),
                  ('recent', '最近'),
                  ('title', AppStrings.sortByTitle),
                  ('project', AppStrings.sortByProject),
                  ('created', '创建时间'),
                  ('model', '模型'),
                  ('key', '键'),
                  ('platform', '平台'),
                  ('agent', '代理'),
                  ('mode', '模式'),
                  ('workdir', '工作目录'),
                  ('running', '运行中'),
                  ('live', '实时'),
                  ('last', '最近消息'),
                  ('pinned', '置顶'),
                  ('note', '备注'),
                  ('archived', '已归档'),
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
          if (_matchPref(AppStrings.consoleLabel, 'tools haptic'))
            Text(AppStrings.consoleLabel, style: Theme.of(context).textTheme.titleSmall),
          if (_matchPref('仪表盘自动刷新', 'seconds'))
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('仪表盘自动刷新'),
              subtitle: Text(
                settings.dashboardRefreshSec == 0
                    ? 'Off'
                    : '每 ${settings.dashboardRefreshSec} 秒',
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final sec in const [0, 10, 15, 30, 60])
                  ChoiceChip(
                    label: Text(sec == 0 ? '关' : '${sec}s'),
                    selected: settings.dashboardRefreshSec == sec,
                    onSelected: (_) => settings.setDashboardRefreshSec(sec),
                  ),
              ],
            ),
          ),
          if (_matchPref('默认显示工具消息', 'tools'))
            if (_matchPref('触感反馈', 'buzz'))
              SwitchListTile(
                secondary: const Icon(Icons.build_circle_outlined),
                title: const Text('默认显示工具消息'),
                subtitle: _sub(
                  '默认折叠工具块；聊天页可随时切换显示',
                ),
                value: settings.showToolsDefault,
                onChanged: settings.setShowToolsDefault,
              ),
          if (_matchPref('保持屏幕常亮', 'awake'))
            SwitchListTile(
              secondary: const Icon(Icons.vibration),
              title: const Text('触感反馈'),
              subtitle: _sub('置顶/发送/复制时轻微震动'),
              value: settings.hapticsEnabled,
              onChanged: settings.setHapticsEnabled,
            ),
          if (_matchPref('等宽聊天字体', 'mono'))
            SwitchListTile(
              secondary: const Icon(Icons.smartphone),
              title: const Text('保持屏幕常亮'),
              subtitle: _sub('使用控制台时的本机偏好'),
              value: settings.keepScreenOn,
              onChanged: settings.setKeepScreenOn,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.font_download_outlined),
            title: const Text('等宽聊天字体'),
            subtitle: _sub('消息正文使用等宽字体'),
            value: settings.monoChat,
            onChanged: settings.setMonoChat,
          ),
          if (_matchPref('自动重连 Bridge', 'reconnect'))
            SwitchListTile(
              secondary: const Icon(Icons.wifi_protected_setup),
              title: const Text('自动重连 Bridge'),
              subtitle: _sub('聊天 WS 断开时重试 · 仅本机'),
              value: settings.autoReconnect,
              onChanged: settings.setAutoReconnect,
            ),
          if (_matchPref('重连次数', 'max reconnect'))
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('重连次数'),
              subtitle: Text(
                '最多 ${settings.maxReconnectAttempts} 次 · 静默退避',
              ),
            ),
          if (_matchPref('重连次数', 'max reconnect'))
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
          if (_matchPref('聊天字号', 'body scale'))
            ListTile(
              leading: const Icon(Icons.format_size),
              title: const Text('聊天字号'),
              subtitle: Text(
                '正文字号 · ${settings.chatFontScale.toStringAsFixed(2)}x',
              ),
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
          if (_matchPref('终端字号', 'term scale'))
            ListTile(
              leading: const Icon(Icons.terminal),
              title: const Text('终端字号'),
              subtitle: Text(
                '等宽缩放 · ${settings.terminalFontScale.toStringAsFixed(2)}x',
              ),
            ),
          if (_matchPref('终端字号', 'term scale'))
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
          if (_matchPref('设备数据', 'prefs reset'))
            Text('设备数据', style: Theme.of(context).textTheme.titleSmall),
          if (_matchPref('复制本机偏好', 'export'))
            ListTile(
              leading: const Icon(Icons.ios_share_outlined),
              title: const Text('复制本机偏好'),
              subtitle: _sub(
                '仅主题与控制台偏好 · 无令牌/主机密钥',
              ),
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
                      content: Text('本机偏好已复制（不含令牌）'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
            ),
          if (_matchPref('重置控制台偏好', 'defaults'))
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('重置控制台偏好'),
              subtitle: _sub(
                '仅主题相关控制台选项 · 不含主机令牌',
              ),
              trailing: const Icon(Icons.restore_outlined),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('重置控制台偏好?'),
                    content: const Text(
                      'Restores local console defaults (scale, compact, refresh, haptics, mono chat, etc.). Host profiles and tokens are not touched.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('重置'),
                      ),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                await settings.resetConsolePrefs();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('控制台偏好已恢复默认'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          const Divider(height: 28),
          if (_matchPref('About', 'console only') || _matchPref('关于', '控制台'))
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于'),
              subtitle: _sub(
                'HuanHermes 只是远程控制台。设置保存在本机。'
                '手机上不跑 agent loop。多主机配置在连接页。',
                three: true,
              ),
              isThreeLine: true,
            ),
          if (_matchPref('应用版本', 'version'))
            ListTile(
              leading: const Icon(Icons.tag),
              title: const Text('应用版本'),
              subtitle: _sub(
                '0.1.192+192 · ${context.watch<ConnectionController>().isRealHermes ? '真 Hermes' : 'Mock'} 主机',
              ),
              trailing: IconButton(
                tooltip: '复制关于',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () async {
                  const text =
                      'HuanHermes App 0.1.192+192\n控制台 · Mock 或真 Hermes 主机\n设备上无 agent loop · 关于文本不含令牌';
                  await Clipboard.setData(const ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('关于已复制'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
              ),
            ),
          if (_matchPref('隐私说明', 'tokens'))
            ListTile(
              leading: const Icon(Icons.policy_outlined),
              title: const Text('隐私说明'),
              subtitle: _sub(
                '令牌保存在安全存储。配对 URI / 导出从不包含令牌。'
                '置顶、备注、草稿、最近与审计均为本机数据。',
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
        return '按标题 A–Z（置顶仍优先）';
      case 'project':
        return '按项目再按标题';
      case 'created':
        return '按创建时间（最新优先）';
      case 'model':
        return '按模型再按标题';
      case 'key':
        return '按会话 key 再按标题';
      case 'platform':
        return '按平台再按标题';
      case 'agent':
        return '按代理类型再按标题';
      case 'mode':
        return '按模式再按标题';
      case 'workdir':
        return '按工作目录再按标题';
      case 'running':
        return '运行中优先（再按标题）';
      case 'live':
        return '实时优先（再按标题）';
      case 'last':
        return '按最后用户消息再按标题';
      case 'pinned':
        return '置顶优先（再按标题；尊重方向）';
      case 'note':
        return '按本机会话备注再按标题';
      case 'archived':
        return '归档优先（再按标题；尊重方向）';
      case 'recent':
        return '按本机最近打开（置顶仍优先）';
      default:
        return '按最近更新（最新优先）';
    }
  }
}
