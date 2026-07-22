import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/connection_config.dart';
import '../services/app_settings_controller.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';
import '../utils/catalog_ui.dart';
import '../utils/query_match.dart';
import '../widgets/connection_fingerprint.dart';
import '../l10n/app_strings.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, required this.config});
  final ConnectionConfig config;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic> data = {};
  Timer? _timer;
  bool _wrapLines = false;
  String _payloadQuery = '';
  bool _payloadCase = false;
  bool _payloadRegex = false;
  bool _payloadSortAsc = true;
  bool _payloadSorted = false;
  final _payloadFilterCtrl = TextEditingController();
  bool _autoRefresh = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _armTimer());
  }

  @override
  void dispose() {
    _payloadFilterCtrl.dispose();
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _armTimer() {
    _timer = CatalogUi.armAutoRefresh(
      context: context,
      current: _timer,
      enabled: _autoRefresh,
      isBusy: () => loading,
      onTick: _load,
    );
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await MgmtClient(config: widget.config).pairingInfo();
      setState(() {
        data = d;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  String get code {
    final c = data['pairing_code']?.toString();
    if (c != null && c.isNotEmpty) {
      // Prefer Host-provided code if present; still never invent tokens.
      return c;
    }
    return widget.config.toPairingUri();
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

  Future<void> _copy(String text, String okMsg) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(okMsg), duration: const Duration(seconds: 1)),
    );
  }

  String get _payloadText {
    final raw = Security.redactText(data.toString());
    final rawQ = _payloadQuery.trim();
    var lines = raw.split('\n');
    if (rawQ.isNotEmpty) {
      if (_payloadRegex) {
        try {
          final re = RegExp(rawQ, caseSensitive: _payloadCase);
          lines = lines.where((l) => re.hasMatch(l)).toList();
        } catch (_) {
          return '(invalid regex: $_payloadQuery)';
        }
      } else {
        final q = _payloadCase ? rawQ : rawQ.toLowerCase();
        lines = lines
            .where((l) => (_payloadCase ? l : l.toLowerCase()).contains(q))
            .toList();
      }
      if (lines.isEmpty) return '（无匹配载荷行：$_payloadQuery）';
    }
    if (_payloadSorted) {
      lines = List<String>.from(lines)
        ..sort(
          (a, b) => _payloadSortAsc
              ? a.toLowerCase().compareTo(b.toLowerCase())
              : b.toLowerCase().compareTo(a.toLowerCase()),
        );
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cfg = widget.config;
    final publicUri = cfg.toPairingUri();
    return Scaffold(
      appBar: AppBar(
        title: Text(_autoRefresh ? '设备配对 · 自动' : '设备配对'),
        actions: [
          IconButton(
            tooltip: '复制公开摘要',
            onPressed: () =>
                _copy(cfg.toPublicSummary(), '已复制公开摘要'),
            icon: const Icon(Icons.notes_outlined),
          ),
          IconButton(
            tooltip: '复制公开 URI',
            onPressed: () => _copy(publicUri, '已复制公开配对 URI'),
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: '复制公开 JSON',
            onPressed: () {
              final payload = <String, dynamic>{
                'huanhermes.pairing_public.v1': true,
                'public_uri': publicUri,
                'public_summary': cfg.toPublicSummary(),
                'fingerprint': _fpHex(publicUri),
                if (data.isNotEmpty)
                  'host_pairing_meta': {
                    for (final e in data.entries)
                      if (!'${e.key}'.toLowerCase().contains('token') &&
                          !'${e.key}'.toLowerCase().contains('secret') &&
                          !'${e.value}'.toString().toLowerCase().contains(
                            'token=',
                          ))
                        e.key: e.value,
                  },
              };
              _copy(
                const JsonEncoder.withIndent('  ').convert(payload),
                '已复制公开 JSON',
              );
            },
            icon: const Icon(Icons.data_object_outlined),
          ),
          IconButton(
            tooltip: '复制公开 CSV',
            onPressed: () {
              final cfg = widget.config;
              final uri = cfg.toPairingUri();
              final fp = _fpHex(uri);
              final uriEsc = uri.replaceAll('"', '""');
              final sumEsc = cfg
                  .toPublicSummary()
                  .replaceAll('"', '""')
                  .replaceAll('\n', ' | ');
              final buf = StringBuffer();
              buf.writeln('key,value');
              buf.writeln('host,"${cfg.host}"');
              buf.writeln('bridge_port,${cfg.bridgePort}');
              buf.writeln('mgmt_port,${cfg.mgmtPort}');
              buf.writeln('use_tls,${cfg.useTls}');
              buf.writeln('public_uri,"$uriEsc"');
              buf.writeln('fingerprint_hex,"$fp"');
              buf.writeln('public_summary,"$sumEsc"');
              _copy(buf.toString(), '已复制公开 CSV');
            },
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: _wrapLines ? '截断详情' : '换行详情',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
          ),
          IconButton(
            tooltip: !_payloadSorted
                ? '排序载荷行'
                : (_payloadSortAsc ? '载荷 Z→A' : '载荷 A→Z'),
            onPressed: () {
              setState(() {
                if (!_payloadSorted) {
                  _payloadSorted = true;
                  _payloadSortAsc = true;
                } else if (_payloadSortAsc) {
                  _payloadSortAsc = false;
                } else {
                  _payloadSorted = false;
                  _payloadSortAsc = true;
                }
              });
            },
            icon: Icon(
              !_payloadSorted
                  ? Icons.sort
                  : (_payloadSortAsc ? Icons.sort_by_alpha : Icons.sort),
            ),
          ),
          IconButton(
            tooltip: _autoRefresh ? '暂停刷新' : '自动刷新',
            onPressed: () {
              setState(() => _autoRefresh = !_autoRefresh);
              _armTimer();
            },
            icon: Icon(
              _autoRefresh
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
            ),
          ),
          IconButton(
            tooltip: '回到顶部',
            onPressed: () {
              if (!_scroll.hasClients) return;
              _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 200),
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
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            },
            icon: const Icon(Icons.vertical_align_bottom),
          ),

          IconButton(
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        for (final item
                            in <(String, bool, void Function(bool))>[
                              (
                                AppStrings.wrap,
                                _wrapLines,
                                (v) => setState(() => _wrapLines = v),
                              ),
                              (
                                AppStrings.regex,
                                _payloadRegex,
                                (v) => setState(() => _payloadRegex = v),
                              ),
                              (
                                AppStrings.matchCase,
                                _payloadCase,
                                (v) => setState(() => _payloadCase = v),
                              ),
                              (
                                'Sort',
                                _payloadSorted,
                                (v) => setState(() => _payloadSorted = v),
                              ),
                              (
                                AppStrings.autoRefresh,
                                _autoRefresh,
                                (v) {
                                  setState(() => _autoRefresh = v);
                                  _armTimer();
                                },
                              ),
                            ])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(
                                item.$1,
                                style: const TextStyle(fontSize: 11),
                              ),
                              selected: item.$2,
                              visualDensity: VisualDensity.compact,
                              onSelected: item.$3,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (error != null)
                    Text(error!, style: TextStyle(color: cs.error)),
                  Text(
                    '分享不含令牌的连接摘要。可粘贴到另一设备的连接页。'
                    '可视指纹供人工核对。二维码便于扫描。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ConnectionFingerprint(
                      seed: publicUri,
                      size: 220,
                      cells: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: QrImageView(
                      data: publicUri,
                      size: 180,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      '用另一设备扫描以连接',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'fingerprint · ${cfg.host}:${cfg.bridgePort}/${cfg.mgmtPort}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                      maxLines: _wrapLines ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: SelectableText(
                      'hex ${_fpHex(publicUri)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton.icon(
                      onPressed: () =>
                          _copy(_fpHex(publicUri), '指纹 hex 已复制'),
                      icon: const Icon(Icons.tag, size: 16),
                      label: const Text('复制指纹 hex'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                      color: cs.surfaceContainerLow,
                    ),
                    child: SelectableText(
                      code,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _copy(code, '已复制配对文本'),
                        icon: const Icon(Icons.copy),
                        label: const Text('复制 URI'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _copy(
                          cfg.toPublicSummary(),
                          '已复制公开摘要',
                        ),
                        icon: const Icon(Icons.notes_outlined),
                        label: const Text('复制摘要'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _copy(publicUri, '已复制公开配对 URI'),
                        icon: const Icon(Icons.link),
                        label: const Text('复制公开 URI'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          final card = [
                            'HuanHermes 连接卡片（公开 · 不含令牌）',
                            'host: ${cfg.host}',
                            'bridge: ${cfg.bridgePort}',
                            'mgmt: ${cfg.mgmtPort}',
                            'tls: ${cfg.useTls ? 1 : 0}',
                            'uri: $publicUri',
                            'fingerprint: ${_fpHex(publicUri)}',
                            '',
                            '将 uri 行粘贴到连接页 → 导入配对 URI。',
                            '或从另一设备扫描二维码。',
                          ].join('\n');
                          _copy(card, '已复制粘贴卡片（不含令牌）');
                        },
                        icon: const Icon(Icons.sticky_note_2_outlined),
                        label: const Text('复制粘贴卡片'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '核对清单',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '1. 在两台设备上比对可视指纹',
                          ),
                          const Text('2. 核对 host:ports 与 hex 标签'),
                          const Text(
                            '3. 只粘贴公开 URI（切勿分享令牌）',
                          ),
                          const Text(
                            '4. Scan QR code on another device to import connection',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '主机载荷（已脱敏）',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _payloadFilterCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: IconButton(
                        tooltip: _payloadRegex
                            ? (_payloadCase
                                  ? '正则 · 大小写 开（长按恢复普通筛选）'
                                  : '正则 · 大小写 关（长按恢复普通筛选）')
                            : (_payloadCase
                                  ? '区分大小写（长按切换正则）'
                                  : '不区分大小写（长按切换正则）'),
                        icon: Icon(
                          _payloadRegex
                              ? Icons.code
                              : (_payloadCase
                                    ? Icons.text_fields
                                    : Icons.search),
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => _payloadCase = !_payloadCase),
                        onLongPress: () =>
                            setState(() => _payloadRegex = !_payloadRegex),
                      ),
                      hintText: _payloadRegex
                          ? (_payloadCase
                                ? '筛选载荷（正则 · 大小写）'
                                : '筛选载荷（正则）')
                          : (_payloadCase
                                ? '筛选载荷（区分大小写）'
                                : '筛选载荷行'),
                      border: const OutlineInputBorder(),
                      suffixIcon: _payloadQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _payloadFilterCtrl.clear();
                                setState(() => _payloadQuery = '');
                              },
                            ),
                    ),
                    onChanged: (v) => setState(() => _payloadQuery = v),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _payloadText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    maxLines: _wrapLines ? null : 8,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    data['note']?.toString() ??
                        '令牌仅保存在各设备。只分享公开 URI 或二维码。',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }
}
