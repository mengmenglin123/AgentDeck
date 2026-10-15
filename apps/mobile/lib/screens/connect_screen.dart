import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../models/discovered_agent.dart';
import '../services/connection_controller.dart';
import '../utils/security.dart';
import 'ssh_discovery_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _bridgePort;
  late final TextEditingController _mgmtPort;
  late final TextEditingController _bridgeToken;
  late final TextEditingController _mgmtToken;
  bool _obscureBridge = true;
  bool _obscureMgmt = true;
  bool _wrapLines = false;
  bool _sortAsc = true;

  /// name | host | updated | port | note
  String _sortMode = 'name';
  String _tlsFilter = 'all'; // all | tls | plain
  String _profileQuery = '';
  bool _queryCase = false;
  bool _queryRegex = false;
  final _profileFilterCtrl = TextEditingController();
  final _scroll = ScrollController();
  bool _useTls = false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    final c = context.read<ConnectionController>();
    final d = c.draft;
    _name = TextEditingController(text: c.draftProfileName);
    _host = TextEditingController(text: d.host);
    _bridgePort = TextEditingController(text: '${d.bridgePort}');
    _mgmtPort = TextEditingController(text: '${d.mgmtPort}');
    _bridgeToken = TextEditingController(text: d.bridgeToken);
    _mgmtToken = TextEditingController(text: d.mgmtToken);
    _useTls = d.useTls;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _name.dispose();
    _host.dispose();
    _bridgePort.dispose();
    _mgmtPort.dispose();
    _bridgeToken.dispose();
    _mgmtToken.dispose();
    _profileFilterCtrl.dispose();
    super.dispose();
  }

  void _syncControllersFrom(ConnectionController c) {
    final d = c.draft;
    _name.text = c.draftProfileName;
    _host.text = d.host;
    _bridgePort.text = '${d.bridgePort}';
    _mgmtPort.text = '${d.mgmtPort}';
    _bridgeToken.text = d.bridgeToken;
    _mgmtToken.text = d.mgmtToken;
    _useTls = d.useTls;
  }

  static String _fpHex(String seed) {
    final bytes = utf8.encode(seed);
    var state = 2166136261;
    for (final b in bytes) {
      state = (state ^ b) * 16777619;
      state &= 0xFFFFFFFF;
    }
    var s2 = state;
    final parts = <String>[];
    for (var i = 0; i < 4; i++) {
      s2 = (1103515245 * s2 + 12345) & 0x7FFFFFFF;
      parts.add((s2 & 0xFFFF).toRadixString(16).padLeft(4, '0'));
    }
    return parts.join();
  }

  ConnectionConfig _readForm(ConnectionConfig base) {
    return base.copyWith(
      host: _host.text.trim(),
      bridgePort: int.tryParse(_bridgePort.text.trim()) ?? base.bridgePort,
      mgmtPort: int.tryParse(_mgmtPort.text.trim()) ?? base.mgmtPort,
      bridgeToken: _bridgeToken.text.trim(),
      mgmtToken: _mgmtToken.text.trim(),
      useTls: _useTls,
    );
  }

  Future<void> _onConnect() async {
    final controller = context.read<ConnectionController>();
    controller.updateDraftProfileName(_name.text);
    controller.updateDraft(_readForm(controller.draft));
    final ok = await controller.testAndSave();
    if (!mounted) return;
    if (!ok) {
      final err = Security.redactText(
        controller.lastError ?? '连接失败',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _discoverAgentsOverSsh() async {
    final result = await Navigator.of(context).push<SshDiscoveryResult>(
      MaterialPageRoute(
        builder: (_) => SshDiscoveryScreen(initialHost: _host.text.trim()),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _host.text = result.host;
      _bridgePort.text = '${result.bridgePort}';
      _mgmtPort.text = '${result.mgmtPort}';
      if (result.bridgeToken != null) _bridgeToken.text = result.bridgeToken!;
      if (result.mgmtToken != null) _mgmtToken.text = result.mgmtToken!;
      if (_name.text.trim().isEmpty || _name.text == 'Default') {
        _name.text = 'SSH ${result.host}';
      }
    });
    final labels = result.agents.map((agent) => agent.label).join('、');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          labels.isEmpty
              ? '已应用 SSH 主机地址；未发现支持的 Agent'
              : result.bridgeToken == null
                  ? '已发现并映射：$labels。请填写 Host 令牌后连接。'
                  : '已发现并映射：$labels，Host 令牌已安全回填。',
        ),
      ),
    );
  }

  Future<void> _importPairing() async {
    final ctrl = TextEditingController();
    // Prefill from clipboard when it looks like a public pairing URI (no camera).
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final t = clip?.text?.trim() ?? '';
      if (t.contains('huanhermes://') || t.contains('bridge=')) {
        ctrl.text = t;
      }
    } catch (_) {}
    if (!mounted) {
      ctrl.dispose();
      return;
    }
    final pasted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入配对 URI'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '粘贴公开 URI 或扫描二维码。可用时自动预填剪贴板。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'huanhermes://connect?host=…&bridge=…&mgmt=…&tls=0',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog first
              final scanned = await _scanQrCode();
              if (scanned != null && scanned.isNotEmpty && mounted) {
                ctrl.text = scanned;
                // Re-process
                final overlay = ConnectionConfig.tryParsePairingUri(scanned);
                if (overlay != null) {
                  final controller = context.read<ConnectionController>();
                  final merged = _readForm(
                    controller.draft,
                  ).mergePairing(overlay);
                  controller.updateDraft(merged);
                  _syncControllersFrom(controller);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('二维码导入成功'),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('无法解析二维码')),
                  );
                }
              }
              ctrl.dispose();
              return;
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('扫描二维码'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final clip = await Clipboard.getData(Clipboard.kTextPlain);
                final t = clip?.text?.trim() ?? '';
                if (t.isNotEmpty) ctrl.text = t;
              } catch (_) {}
            },
            child: const Text('粘贴剪贴板'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (pasted == null || pasted.isEmpty || !mounted) return;
    final overlay = ConnectionConfig.tryParsePairingUri(pasted);
    if (overlay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法解析配对 URI')),
      );
      return;
    }
    final controller = context.read<ConnectionController>();
    final merged = _readForm(controller.draft).mergePairing(overlay);
    controller.updateDraft(merged);
    _syncControllersFrom(controller);
    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          overlay.hasTokens
              ? '主机字段 + 令牌已导入（连接前请检查）'
              : '主机字段已填写 — 请继续输入令牌，然后测试并连接',
        ),
      ),
    );
  }

  /// Open camera to scan a QR code containing a pairing URI.
  /// Returns the scanned string, or null if cancelled.
  Future<String?> _scanQrCode() async {
    String? result;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('扫描二维码'),
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          body: MobileScanner(
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final value = barcodes.first.rawValue;
                if (value != null && value.isNotEmpty) {
                  result = value;
                  Navigator.pop(ctx);
                }
              }
            },
          ),
        ),
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ConnectionController>();
    final phase = controller.phase;
    final busy = phase == ConnectionPhase.testing;
    final warnTls = Security.shouldWarnPlaintext(_host.text.trim(), _useTls);

    return Scaffold(
      appBar: AppBar(
        title: const Text('连接服务器'),
        actions: [
          IconButton(
            tooltip: 'SSH 自动发现 Agent',
            onPressed: busy ? null : _discoverAgentsOverSsh,
            icon: const Icon(Icons.radar_outlined),
          ),
          IconButton(
            tooltip: '导入配对 URI',
            onPressed: busy ? null : _importPairing,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: '新建配置',
            onPressed: busy
                ? null
                : () async {
                    await controller.startNewProfile();
                    _syncControllersFrom(controller);
                    setState(() {});
                  },
            icon: const Icon(Icons.add),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) async {
              if (v == 'wrap') {
                setState(() => _wrapLines = !_wrapLines);
                return;
              }
              if (v == 'sort_cycle') {
                setState(() {
                  if (_sortMode == 'name' && _sortAsc) {
                    _sortAsc = false;
                  } else if (_sortMode == 'name' && !_sortAsc) {
                    _sortMode = 'host';
                    _sortAsc = true;
                  } else if (_sortMode == 'host' && _sortAsc) {
                    _sortAsc = false;
                  } else if (_sortMode == 'host' && !_sortAsc) {
                    _sortMode = 'updated';
                    _sortAsc = false;
                  } else if (_sortMode == 'updated' && !_sortAsc) {
                    _sortAsc = true;
                  } else if (_sortMode == 'updated' && _sortAsc) {
                    _sortMode = 'port';
                    _sortAsc = false;
                  } else if (_sortMode == 'port' && !_sortAsc) {
                    _sortAsc = true;
                  } else if (_sortMode == 'port' && _sortAsc) {
                    _sortMode = 'note';
                    _sortAsc = true;
                  } else if (_sortMode == 'note' && _sortAsc) {
                    _sortAsc = false;
                  } else if (_sortMode == 'note' && !_sortAsc) {
                    _sortMode = 'bridgePort';
                    _sortAsc = false;
                  } else if (_sortMode == 'bridgePort' && !_sortAsc) {
                    _sortAsc = true;
                  } else if (_sortMode == 'bridgePort' && _sortAsc) {
                    _sortMode = 'tls';
                    _sortAsc = true;
                  } else if (_sortMode == 'tls' && _sortAsc) {
                    _sortAsc = false;
                  } else if (_sortMode == 'tls' && !_sortAsc) {
                    _sortMode = 'platform';
                    _sortAsc = true;
                  } else if (_sortMode == 'platform' && _sortAsc) {
                    _sortAsc = false;
                  } else if (_sortMode == 'platform' && !_sortAsc) {
                    _sortMode = 'id';
                    _sortAsc = true;
                  } else if (_sortMode == 'id' && _sortAsc) {
                    _sortAsc = false;
                  } else if (_sortMode == 'id' && !_sortAsc) {
                    _sortMode = 'deviceId';
                    _sortAsc = true;
                  } else if (_sortMode == 'deviceId' && _sortAsc) {
                    _sortAsc = false;
                  } else {
                    _sortMode = 'name';
                    _sortAsc = true;
                  }
                });
                return;
              }
              if (v == 'top') {
                if (!_scroll.hasClients) return;
                _scroll.animateTo(0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut);
                return;
              }
              if (v == 'bottom') {
                if (!_scroll.hasClients) return;
                _scroll.animateTo(_scroll.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut);
                return;
              }
              if (v == 'copy_public') {
                final host = _host.text.trim();
                if (host.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('请先输入主机地址'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                  return;
                }
                final bridge = int.tryParse(_bridgePort.text.trim()) ?? 19810;
                final mgmt = int.tryParse(_mgmtPort.text.trim()) ?? 19820;
                final cfg = ConnectionConfig(
                  host: host,
                  bridgePort: bridge,
                  mgmtPort: mgmt,
                  bridgeToken: '',
                  mgmtToken: '',
                  useTls: _useTls,
                );
                await Clipboard.setData(
                  ClipboardData(text: cfg.toPublicSummary()),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制公开摘要（不含令牌）'),
                    duration: Duration(seconds: 1),
                  ),
                );
                return;
              }
              if (v == 'copy_fp') {
                final host = _host.text.trim();
                if (host.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('请先输入主机地址'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                  return;
                }
                final bridge = int.tryParse(_bridgePort.text.trim()) ?? 19810;
                final mgmt = int.tryParse(_mgmtPort.text.trim()) ?? 19820;
                final cfg = ConnectionConfig(
                  host: host,
                  bridgePort: bridge,
                  mgmtPort: mgmt,
                );
                final hex = _fpHex(cfg.toPairingUri());
                await Clipboard.setData(ClipboardData(text: hex));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('指纹 $hex'),
                    duration: const Duration(seconds: 1),
                  ),
                );
                return;
              }
              if (v == 'copy_profiles') {
                if (controller.profiles.isEmpty) return;
                final list =
                    controller.profiles.map((p) => p.toPublicJson()).toList();
                final text = const JsonEncoder.withIndent('  ').convert({
                  'huanhermes.profiles_public.v1': true,
                  'count': list.length,
                  'profiles': list,
                });
                await Clipboard.setData(ClipboardData(text: text));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已复制 ${list.length} 个公开配置'),
                    duration: const Duration(seconds: 1),
                  ),
                );
                return;
              }
              if (v == 'copy_csv') {
                if (controller.profiles.isEmpty) return;
                final buf = StringBuffer();
                buf.writeln(
                    'id,name,host,bridge_port,mgmt_port,use_tls,note');
                for (final p in controller.profiles) {
                  final id = p.id.replaceAll('"', '""');
                  final name = p.name.replaceAll('"', '""');
                  final host = p.config.host.replaceAll('"', '""');
                  final note = (p.note ?? '').replaceAll('"', '""');
                  buf.writeln(
                      '"$id","$name","$host",${p.config.bridgePort},${p.config.mgmtPort},${p.config.useTls},"$note"');
                }
                await Clipboard.setData(ClipboardData(text: buf.toString()));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '已复制配置 CSV (${controller.profiles.length})'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'copy_public',
                child: Text('复制公开信息'),
              ),
              PopupMenuItem(
                value: 'copy_fp',
                child: Text('复制指纹'),
              ),
              PopupMenuItem(
                value: 'copy_profiles',
                enabled: controller.profiles.isNotEmpty,
                child: Text('复制配置（不含令牌）'),
              ),
              PopupMenuItem(
                value: 'copy_csv',
                enabled: controller.profiles.isNotEmpty,
                child: Text('复制配置 CSV'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'wrap',
                child: Text(_wrapLines ? '截断健康文本' : '换行显示健康文本'),
              ),
              PopupMenuItem(
                value: 'sort_cycle',
                child: Text('切换排序'),
              ),
              const PopupMenuItem(
                value: 'top',
                child: Text('回到顶部'),
              ),
              const PopupMenuItem(
                value: 'bottom',
                child: Text('跳到底部'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          controller: _scroll,
          padding: EdgeInsets.zero,
          children: [
            // ── Modern hero (Linear-inspired, theme-aware) ──
            Builder(
              builder: (context) {
                final cs = Theme.of(context).colorScheme;
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F1011) : cs.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : cs.outlineVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: [
                                  cs.primary,
                                  cs.primary.withValues(alpha: 0.72),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: cs.primary.withValues(alpha: 0.28),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.hub_rounded,
                              size: 26,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'HuanHermes',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '连接 Host 控制台',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '纯控制台 · 代理在服务器运行 · 密钥本地安全存储',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _HeroPill(
                            icon: Icons.forum_outlined,
                            label: '会话',
                            color: cs.primary,
                          ),
                          _HeroPill(
                            icon: Icons.terminal,
                            label: '终端',
                            color: const Color(0xFF10B981),
                          ),
                          _HeroPill(
                            icon: Icons.extension_outlined,
                            label: '技能',
                            color: const Color(0xFFF59E0B),
                          ),
                          _HeroPill(
                            icon: Icons.schedule,
                            label: '定时',
                            color: const Color(0xFFA78BFA),
                          ),
                          _HeroPill(
                            icon: Icons.hub_outlined,
                            label: 'MCP',
                            color: const Color(0xFF2DD4BF),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'HuanHermes 是纯控制台工具 — 代理在服务器运行，密钥保存在本机安全存储。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _ConnectionStatusBanner(
                controller: controller, wrapLines: _wrapLines),
            if (controller.profiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '已保存的主机',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final f in [
                    ('all', '全部'),
                    ('tls', 'TLS'),
                    ('plain', '明文'),
                  ])
                    FilterChip(
                      label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                      selected: _tlsFilter == f.$1,
                      onSelected: (_) => setState(() => _tlsFilter = f.$1),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  FilterChip(
                    label: const Text('换行', style: TextStyle(fontSize: 11)),
                    selected: _wrapLines,
                    onSelected: (v) => setState(() => _wrapLines = v),
                    visualDensity: VisualDensity.compact,
                  ),
                  FilterChip(
                    label: const Text('正则', style: TextStyle(fontSize: 11)),
                    selected: _queryRegex,
                    onSelected: (v) => setState(() => _queryRegex = v),
                    visualDensity: VisualDensity.compact,
                  ),
                  FilterChip(
                    label: const Text('大小写', style: TextStyle(fontSize: 11)),
                    selected: _queryCase,
                    onSelected: (v) => setState(() => _queryCase = v),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _profileFilterCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText: _queryRegex
                      ? (_queryCase
                          ? '搜索配置（正则 · 大小写）'
                          : '搜索配置（正则）')
                      : (_queryCase
                          ? '搜索配置（区分大小写）'
                          : '搜索配置名称/主机/备注'),
                  prefixIcon: IconButton(
                    tooltip: _queryRegex
                        ? (_queryCase
                            ? '正则 · 大小写开（长按：普通搜索）'
                            : '正则 · 大小写关（长按：普通搜索）')
                        : (_queryCase
                            ? '区分大小写（长按：正则）'
                            : '不区分大小写（长按：正则）'),
                    icon: Icon(
                      _queryRegex
                          ? Icons.code
                          : (_queryCase ? Icons.text_fields : Icons.search),
                      size: 18,
                    ),
                    onPressed: () => setState(() => _queryCase = !_queryCase),
                    onLongPress: () =>
                        setState(() => _queryRegex = !_queryRegex),
                  ),
                  suffixIcon: _profileQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _profileFilterCtrl.clear();
                            setState(() => _profileQuery = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _profileQuery = v),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (List.of(controller.profiles).where((p) {
                  if (_tlsFilter == 'tls' && !p.config.useTls) return false;
                  if (_tlsFilter == 'plain' && p.config.useTls) return false;
                  final rawQ = _profileQuery.trim();
                  if (rawQ.isEmpty) return true;
                  final hayRaw =
                      '${p.name} ${p.config.host} ${p.config.bridgePort} ${p.config.mgmtPort} ${p.note ?? ''}';
                  if (_queryRegex) {
                    try {
                      return RegExp(
                        rawQ,
                        caseSensitive: _queryCase,
                      ).hasMatch(hayRaw);
                    } catch (_) {
                      return false;
                    }
                  }
                  final q = _queryCase ? rawQ : rawQ.toLowerCase();
                  final hay = _queryCase ? hayRaw : hayRaw.toLowerCase();
                  return hay.contains(q);
                }).toList()
                      ..sort((a, b) {
                        int c;
                        if (_sortMode == 'host') {
                          c = a.config.host.toLowerCase().compareTo(
                                b.config.host.toLowerCase(),
                              );
                          if (c == 0) {
                            c = a.name.toLowerCase().compareTo(
                                  b.name.toLowerCase(),
                                );
                          }
                        } else if (_sortMode == 'updated') {
                          c = a.updatedAt.compareTo(b.updatedAt);
                          if (c == 0) {
                            c = a.name.toLowerCase().compareTo(
                                  b.name.toLowerCase(),
                                );
                          }
                        } else if (_sortMode == 'port') {
                          c = a.config.mgmtPort.compareTo(b.config.mgmtPort);
                          if (c == 0) {
                            c = a.config.bridgePort.compareTo(
                              b.config.bridgePort,
                            );
                          }
                          if (c == 0) {
                            c = a.name.toLowerCase().compareTo(
                                  b.name.toLowerCase(),
                                );
                          }
                        } else if (_sortMode == 'note') {
                          c = (a.note ?? '').toLowerCase().compareTo(
                                (b.note ?? '').toLowerCase(),
                              );
                          if (c == 0) {
                            c = a.name.toLowerCase().compareTo(
                                  b.name.toLowerCase(),
                                );
                          }
                        } else if (_sortMode == 'bridgePort') {
                          c = a.config.bridgePort.compareTo(
                            b.config.bridgePort,
                          );
                          if (c == 0) {
                            c = a.config.mgmtPort.compareTo(
                              b.config.mgmtPort,
                            );
                          }
                          if (c == 0) {
                            c = a.name.toLowerCase().compareTo(
                                  b.name.toLowerCase(),
                                );
                          }
                        } else if (_sortMode == 'tls') {
                          final ta = a.config.useTls ? 1 : 0;
                          final tb = b.config.useTls ? 1 : 0;
                          c = ta.compareTo(tb);
                          if (c == 0) {
                            c = a.name.toLowerCase().compareTo(
                                  b.name.toLowerCase(),
                                );
                          }
                        } else if (_sortMode == 'platform') {
                          c = a.config.platformName.toLowerCase().compareTo(
                                b.config.platformName.toLowerCase(),
                              );
                          if (c == 0) {
                            c = a.name.toLowerCase().compareTo(
                                  b.name.toLowerCase(),
                                );
                          }
                        } else if (_sortMode == 'id') {
                          c = a.id.toLowerCase().compareTo(
                                b.id.toLowerCase(),
                              );
                          if (c == 0) {
                            c = a.name.toLowerCase().compareTo(
                                  b.name.toLowerCase(),
                                );
                          }
                        } else if (_sortMode == 'deviceId') {
                          c = a.config.deviceId.toLowerCase().compareTo(
                                b.config.deviceId.toLowerCase(),
                              );
                          if (c == 0) {
                            c = a.name.toLowerCase().compareTo(
                                  b.name.toLowerCase(),
                                );
                          }
                        } else {
                          c = a.name.toLowerCase().compareTo(
                                b.name.toLowerCase(),
                              );
                        }
                        return _sortAsc ? c : -c;
                      }))
                    .map((p) {
                  final selected = p.id == controller.activeProfileId;
                  return FilterChip(
                    label: Text(
                      p.name,
                      maxLines: _wrapLines ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: selected,
                    onSelected: busy
                        ? null
                        : (_) async {
                            await controller.selectProfile(p.id);
                            _syncControllersFrom(controller);
                            setState(() {});
                          },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 短路径：名称 + 主机 + 双令牌
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: '配置名称',
                      hintText: '家庭 / 公司 / 测试',
                    ),
                    enabled: !busy,
                    onChanged: controller.updateDraftProfileName,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _host,
                    decoration: const InputDecoration(
                      labelText: '主机地址',
                      hintText: 'IP 或域名',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                    textInputAction: TextInputAction.next,
                    enabled: !busy,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bridgeToken,
                    obscureText: _obscureBridge,
                    decoration: InputDecoration(
                      labelText: '桥接令牌',
                      prefixIcon: const Icon(Icons.key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureBridge
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () => setState(
                          () => _obscureBridge = !_obscureBridge,
                        ),
                      ),
                    ),
                    enabled: !busy,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _mgmtToken,
                    obscureText: _obscureMgmt,
                    decoration: InputDecoration(
                      labelText: '管理令牌',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureMgmt
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () =>
                            setState(() => _obscureMgmt = !_obscureMgmt),
                      ),
                    ),
                    enabled: !busy,
                  ),
                  const SizedBox(height: 8),
                  // 高级选项折叠：端口 / TLS
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: busy
                          ? null
                          : () => setState(
                                () => _showAdvanced = !_showAdvanced,
                              ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              _showAdvanced
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 22,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _showAdvanced ? '收起高级选项' : '高级选项（端口 / TLS）',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${_bridgePort.text}:${_mgmtPort.text}${_useTls ? ' · TLS' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_showAdvanced) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _bridgePort,
                            decoration: const InputDecoration(
                              labelText: '桥接端口',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            enabled: !busy,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _mgmtPort,
                            decoration: const InputDecoration(
                              labelText: '管理端口',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            enabled: !busy,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('使用 TLS (wss / https)'),
                      subtitle: const Text('公网环境推荐开启'),
                      value: _useTls,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => _useTls = v),
                    ),
                    if (warnTls)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFF59E0B), size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '明文连接到非本地主机：流量未加密。建议 TLS 反向代理。',
                                style: TextStyle(fontSize: 12.5, height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: busy ? null : _onConnect,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.bolt_rounded),
                  label: Text(
                    busy ? '连接中…' : '测试并连接',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ),
            ),
            if (controller.profiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('删除此配置？'),
                            content: const Text(
                              '此配置的令牌将从设备中移除。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('删除'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          await controller.deleteActiveProfile();
                          _syncControllersFrom(controller);
                          setState(() {});
                        }
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除配置'),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '参见 docs/guides/connect-real-host.md — 仅在 App 中填写令牌；'
              '不要更改 Host 频道/提供商配置。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatusBanner extends StatelessWidget {
  const _ConnectionStatusBanner(
      {required this.controller, this.wrapLines = false});

  final ConnectionController controller;
  final bool wrapLines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final phase = controller.phase;
    Color color;
    IconData icon;
    String title;
    String subtitle;
    switch (phase) {
      case ConnectionPhase.ready:
        if (controller.healthDegraded) {
          color = const Color(0xFFF59E0B);
          icon = Icons.warning_amber_rounded;
          title = '已连接 · 健康状态异常';
          subtitle = controller.lastHealthError ?? '上次 /status 探测失败';
        } else {
          color = const Color(0xFF10B981);
          icon = Icons.check_circle_outline;
          title = '已连接 · 就绪';
          final ok = controller.lastHealthOkAt;
          subtitle = ok == null
              ? '主机配置已激活'
              : '上次健康检查正常 ${ok.toLocal().toIso8601String().substring(11, 19)}';
        }
      case ConnectionPhase.testing:
        color = const Color(0xFFF59E0B);
        icon = Icons.hourglass_top;
        title = '正在测试连接…';
        subtitle = '正在探测管理端口和桥接端口';
      case ConnectionPhase.error:
        color = cs.error;
        icon = Icons.error_outline;
        title = '连接错误';
        subtitle = controller.lastError ?? '请检查主机地址 / 端口 / 令牌';
      case ConnectionPhase.idle:
        color = cs.onSurfaceVariant;
        icon = Icons.link_off;
        title = '未连接';
        subtitle = '填写配置信息并测试保存';
    }
    final lat = controller.lastTestLatencyMs;
    if (lat != null && phase != ConnectionPhase.testing) {
      subtitle = '$subtitle · 上次测试 ${lat} ms';
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: wrapLines ? 8 : 3,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : color.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? cs.onSurface : cs.onSurface,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
