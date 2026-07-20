import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/connection_controller.dart';
import '../utils/security.dart';

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
            tooltip: '复制公开信息',
            onPressed: () async {
              final host = _host.text.trim();
              if (host.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('请先输入主机地址'),
                    duration: const Duration(seconds: 1),
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
                SnackBar(
                  content: const Text('已复制公开摘要（不含令牌）'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            tooltip: '复制指纹',
            onPressed: () async {
              final host = _host.text.trim();
              if (host.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('请先输入主机地址'),
                    duration: const Duration(seconds: 1),
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
            },
            icon: const Icon(Icons.fingerprint),
          ),
          IconButton(
            tooltip: '复制配置（不含令牌）',
            onPressed: controller.profiles.isEmpty
                ? null
                : () async {
                    final list = controller.profiles
                        .map((p) => p.toPublicJson())
                        .toList();
                    final text = const JsonEncoder.withIndent('  ').convert({
                      'huanhermes.profiles_public.v1': true,
                      'count': list.length,
                      'profiles': list,
                    });
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '已复制 ${list.length} 个公开配置',
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            tooltip: '复制配置 CSV',
            onPressed: controller.profiles.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    buf.writeln(
                      'id,name,host,bridge_port,mgmt_port,use_tls,note',
                    );
                    for (final p in controller.profiles) {
                      final id = p.id.replaceAll('"', '""');
                      final name = p.name.replaceAll('"', '""');
                      final host = p.config.host.replaceAll('"', '""');
                      final note = (p.note ?? '').replaceAll('"', '""');
                      buf.writeln(
                        '"$id","$name","$host",${p.config.bridgePort},${p.config.mgmtPort},${p.config.useTls},"$note"',
                      );
                    }
                    await Clipboard.setData(
                      ClipboardData(text: buf.toString()),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '已复制配置 CSV (${controller.profiles.length})',
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: _wrapLines ? '截断健康文本' : '换行显示健康文本',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
          ),
          IconButton(
            tooltip: _sortMode == 'deviceId'
                ? (_sortAsc ? '设备ID Z→A' : '设备ID A→Z')
                : (_sortMode == 'id'
                    ? (_sortAsc ? 'ID Z→A' : 'ID A→Z')
                    : (_sortMode == 'platform'
                        ? (_sortAsc ? '平台 Z→A' : '平台 A→Z')
                        : (_sortMode == 'tls'
                            ? (_sortAsc ? 'TLS优先' : '明文优先')
                            : (_sortMode == 'bridgePort'
                                ? (_sortAsc
                                    ? '桥接端口 高→低'
                                    : '桥接端口 低→高')
                                : (_sortMode == 'note'
                                    ? (_sortAsc ? '备注 Z→A' : '备注 A→Z')
                                    : (_sortMode == 'port'
                                        ? (_sortAsc
                                            ? '管理端口 高→低'
                                            : '管理端口 低→高')
                                        : (_sortMode == 'host'
                                            ? (_sortAsc
                                                ? '主机 Z→A'
                                                : '主机 A→Z')
                                            : (_sortMode == 'updated'
                                                ? (_sortAsc
                                                    ? '更新 新→旧'
                                                    : '更新 旧→新')
                                                : (_sortAsc
                                                    ? '名称 Z→A'
                                                    : '名称 A→Z'))))))))),
            onPressed: () {
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
                  _sortAsc = false; // new first
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
            },
            icon: Icon(
              _sortMode == 'deviceId'
                  ? Icons.phonelink_setup
                  : (_sortMode == 'id'
                      ? Icons.tag
                      : (_sortMode == 'platform'
                          ? Icons.devices_other_outlined
                          : (_sortMode == 'tls'
                              ? Icons.lock_outline
                              : (_sortMode == 'bridgePort'
                                  ? Icons.cable
                                  : (_sortMode == 'note'
                                      ? Icons.sticky_note_2_outlined
                                      : (_sortMode == 'port'
                                          ? Icons.numbers
                                          : (_sortMode == 'host'
                                              ? Icons.dns_outlined
                                              : (_sortMode == 'updated'
                                                  ? Icons.schedule
                                                  : (_sortAsc
                                                      ? Icons.sort_by_alpha
                                                      : Icons.sort))))))))),
            ),
          ),
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
        ],
      ),
      body: SafeArea(
        child: ListView(
          controller: _scroll,
          padding: EdgeInsets.zero,
          children: [
            // ── Hero Section with Gradient Background ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF4A90E2), Color(0xFF357ABD), Color(0xFF2A5F9E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.15),
                      boxShadow: [BoxShadow(color: const Color(0xFF4A90E2).withOpacity(0.4), blurRadius: 30, spreadRadius: 5)],
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.2)),
                      child: const Icon(Icons.hub_outlined, size: 48, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('HuanHermes', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Text('连接到服务器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.9))),
                  const SizedBox(height: 6),
                  Text('输入服务器信息以开始使用', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7))),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                    child: Text('纯控制台工具 · 代理运行在服务器上', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.85))),
                  ),
                ],
              ),
            ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Feature Cards ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('功能特色', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _FeatureCard(icon: Icons.chat_bubble_outline, label: '会话管理', color: const Color(0xFF4A90E2)),
                  const SizedBox(width: 12),
                  _FeatureCard(icon: Icons.terminal, label: '终端控制', color: const Color(0xFF7CB342)),
                  const SizedBox(width: 12),
                  _FeatureCard(icon: Icons.extension_outlined, label: '技能商店', color: const Color(0xFFFF8A65)),
                  const SizedBox(width: 12),
                  _FeatureCard(icon: Icons.schedule, label: '定时任务', color: const Color(0xFFAB47BC)),
                  const SizedBox(width: 12),
                  _FeatureCard(icon: Icons.hub_outlined, label: 'MCP 集成', color: const Color(0xFF26A69A)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Connection status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ConnectionStatusBanner(controller: controller, wrapLines: _wrapLines),
            ),
            if (controller.profiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '已保存的主机',
                style: Theme.of(context).textTheme.titleSmall,
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
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: '配置名称',
                      hintText: '家庭 / 公司 / 测试',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    enabled: !busy,
                    onChanged: controller.updateDraftProfileName,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _host,
                    decoration: InputDecoration(
                      labelText: '主机地址',
                      hintText: '127.0.0.1 或 your.domain',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                    enabled: !busy,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _bridgePort,
                          decoration: InputDecoration(
                            labelText: '桥接端口',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          enabled: !busy,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _mgmtPort,
                          decoration: InputDecoration(
                            labelText: '管理端口',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          enabled: !busy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('使用 TLS (wss / https)'),
                    subtitle: const Text('公网环境推荐使用'),
                    value: _useTls,
                    onChanged: busy
                        ? null
                        : (v) {
                            setState(() => _useTls = v);
                          },
                  ),
                  if (warnTls)
                    Card(
                      color: Colors.orange.shade50,
                      child: const ListTile(
                        leading: Icon(Icons.warning_amber, color: Colors.orange),
                        title: Text('明文连接到非本地主机'),
                        subtitle: Text(
                          '流量未加密。建议使用 TLS 反向代理，或在服务器上启用 TLS。令牌仍保存在本地。',
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bridgeToken,
                    obscureText: _obscureBridge,
                    decoration: InputDecoration(
                      labelText: '桥接令牌',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureBridge ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () =>
                            setState(() => _obscureBridge = !_obscureBridge),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureMgmt ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _obscureMgmt = !_obscureMgmt),
                      ),
                    ),
                    enabled: !busy,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primary.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: FilledButton.icon(
                  onPressed: busy ? null : _onConnect,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.link),
                  label: Text(
                    busy ? '连接中…' : '测试并连接',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
          color = Colors.orange;
          icon = Icons.warning_amber_rounded;
          title = '已连接 · 健康状态异常';
          subtitle = controller.lastHealthError ?? '上次 /status 探测失败';
        } else {
          color = Colors.green;
          icon = Icons.check_circle_outline;
          title = '已连接 · 就绪';
          final ok = controller.lastHealthOkAt;
          subtitle = ok == null
              ? '主机配置已激活'
              : '上次健康检查正常 ${ok.toLocal().toIso8601String().substring(11, 19)}';
        }
      case ConnectionPhase.testing:
        color = Colors.amber.shade800;
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
      subtitle = subtitle + ' · last test ' + lat.toString() + ' ms';
    }
    return Card(
      color: color.withOpacity(0.12),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w600, color: color),
        ),
        subtitle: Text(
          subtitle,
          maxLines: wrapLines ? 8 : 3,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
