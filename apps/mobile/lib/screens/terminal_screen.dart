import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../models/connection_config.dart';
import '../models/session_info.dart';
import '../services/app_settings_controller.dart';
import '../services/bridge_client.dart';
import '../services/terminal_history_store.dart';
import '../utils/security.dart';
import '../utils/catalog_ui.dart';
import '../l10n/app_strings.dart';
import '../utils/query_match.dart';

/// Lightweight terminal console over Bridge `terminal_input` / `terminal_out`.
/// Not a full PTY — Host may map to real shell later; Mock echoes commands.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({
    super.key,
    required this.config,
    required this.session,
  });

  final ConnectionConfig config;
  final SessionInfo session;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen>
    with WidgetsBindingObserver {
  BridgeClient? _bridge;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _buf = StringBuffer();
  String _streamId = 'term-ui';
  bool _connecting = true;
  String? _error;
  bool _busy = false;
  final _history = TerminalHistoryStore();
  List<String> _hist = [];
  int _histIndex = -1; // -1 = drafting new
  String _draftBeforeHist = '';
  double _termScale = 1.0; // local terminal font multiplier
  String _workdir = '/workspace'; // best-effort local track (Mock cd/pwd)
  bool _newestFirst = false;
  bool _wrapLines = true;
  bool _showFind = false;
  bool _showTs = false;
  final _findCtrl = TextEditingController();
  String _findQuery = '';
  bool _findCase = false;
  bool _findRegex = false;
  int _termCols = 80;
  int _termRows = 24;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _buf.writeln(
      'HuanHermes 终端通道（会话 ${widget.session.sessionKey}）',
    );
    _buf.writeln('输入 help · 仅协议演示');
    _buf.writeln('↑/↓ 本机历史 · 仅本设备');
    _buf.writeln('');
    _loadHistory();
    try {
      final s = context.read<AppSettingsController>();
      _termScale = s.terminalFontScale.clamp(0.85, 1.4);
    } catch (_) {}
    _connect();
  }

  Future<void> _setTermScale(double v) async {
    final nv = v.clamp(0.85, 1.4);
    setState(() => _termScale = nv);
    try {
      await context.read<AppSettingsController>().setTerminalFontScale(nv);
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final h = await _history.load();
    if (!mounted) return;
    setState(() => _hist = h);
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final b = BridgeClient(
        config: widget.config,
        onMessage: _onMsg,
        onError: (e) {
          if (!mounted) return;
          setState(() => _error = Security.redactText(e.toString()));
        },
      );
      await b.connect();
      if (!mounted) {
        await b.close();
        return;
      }
      b.terminalResize(
        sessionKey: widget.session.sessionKey,
        cols: _termCols,
        rows: _termRows,
      );
      setState(() {
        _bridge = b;
        _connecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = Security.redactText(e.toString());
      });
    }
  }

  void _onMsg(Map<String, dynamic> payload) {
    final type = payload['type']?.toString();
    final sk = payload['session_key']?.toString() ?? '';
    if (sk.isNotEmpty && sk != widget.session.sessionKey) return;

    if (type == 'terminal_clear') {
      setState(() {
        _buf.clear();
        _busy = false;
      });
      return;
    }
    if (type == 'terminal_exit') {
      setState(() {
        _buf.writeln('[session closed by host]');
        _busy = false;
      });
      _scrollBottom();
      return;
    }
    if (type == 'terminal_out' || type == 'terminal_ack') {
      final data = payload['data']?.toString() ?? '';
      if (data.isNotEmpty) {
        setState(() => _buf.write(data));
        _scrollBottom();
      }
      if (payload['done'] == true) {
        setState(() => _busy = false);
      }
      return;
    }
  }

  void _pushResize({int? cols, int? rows}) {
    final c = cols ?? _termCols;
    final r = rows ?? _termRows;
    if (c == _termCols && r == _termRows && cols == null && rows == null)
      return;
    _termCols = c.clamp(20, 240);
    _termRows = r.clamp(5, 120);
    final b = _bridge;
    if (b == null) return;
    try {
      b.terminalResize(
        sessionKey: widget.session.sessionKey,
        cols: _termCols,
        rows: _termRows,
      );
    } catch (_) {}
  }

  void _updateGeometryFromBox(BoxConstraints constraints) {
    // Approx mono cell ~7.2x fontSize width, line height 1.35 * fontSize.
    final fs = 13.0 * _termScale;
    final cellW = fs * 0.62;
    final cellH = fs * 1.35;
    final cols = (constraints.maxWidth / cellW).floor().clamp(20, 240);
    final rows = (constraints.maxHeight / cellH).floor().clamp(5, 120);
    if (cols != _termCols || rows != _termRows) {
      _pushResize(cols: cols, rows: rows);
      if (mounted) setState(() {});
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _sendRaw(String text) {
    if (_bridge == null || _busy) return;
    // Allow Ctrl-C even though trim would keep it; reject empty only.
    if (text.isEmpty) return;
    if (text != '\u0003' && text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      _bridge!.terminalInput(
        sessionKey: widget.session.sessionKey,
        data: text,
        streamId: _streamId,
      );
    } catch (e) {
      setState(() {
        _busy = false;
        _error = Security.redactText(e.toString());
      });
    }
  }

  void _noteWorkdirFromCommand(String text) {
    final t = text.trim();
    if (t == 'cd' || t == 'cd ~') {
      _workdir = '/workspace';
      return;
    }
    if (t.startsWith('cd ')) {
      final arg = t.substring(3).trim();
      if (arg.isEmpty || arg == '~') {
        _workdir = '/workspace';
      } else if (arg == '-') {
        // prev unknown client-side
      } else if (arg.startsWith('/')) {
        if (arg == '/') {
          _workdir = '/workspace';
        } else if (arg.startsWith('/workspace')) {
          var w = arg;
          while (w.length > 1 && w.endsWith('/')) {
            w = w.substring(0, w.length - 1);
          }
          _workdir = w;
        }
      } else if (!arg.contains('..')) {
        final base = _workdir.endsWith('/')
            ? _workdir.substring(0, _workdir.length - 1)
            : _workdir;
        _workdir = '$base/$arg';
      }
    }
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty || _bridge == null || _busy) return;
    _history.push(text);
    _hist.removeWhere((e) => e == text.trimRight());
    _hist.insert(0, text.trimRight());
    while (_hist.length > 50) {
      _hist.removeLast();
    }
    _histIndex = -1;
    _draftBeforeHist = '';
    _input.clear();
    _noteWorkdirFromCommand(text);
    _sendRaw(text);
  }

  void _quick(String cmd) {
    if (_bridge == null || _busy || _connecting) return;
    _sendRaw(cmd);
  }

  void _histUp() {
    if (_hist.isEmpty) return;
    if (_histIndex < 0) {
      _draftBeforeHist = _input.text;
      _histIndex = 0;
    } else if (_histIndex < _hist.length - 1) {
      _histIndex += 1;
    } else {
      return;
    }
    setState(() => _input.text = _hist[_histIndex]);
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  void _histDown() {
    if (_histIndex < 0) return;
    if (_histIndex == 0) {
      _histIndex = -1;
      setState(() => _input.text = _draftBeforeHist);
    } else {
      _histIndex -= 1;
      setState(() => _input.text = _hist[_histIndex]);
    }
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  Future<void> _pickHistory() async {
    final items = List<String>.from(_hist);
    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('暂无本机终端历史'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('命令历史'),
              subtitle: const Text('仅本机'),
              trailing: IconButton(
                tooltip: '清空',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () async {
                  await _history.clear();
                  setState(() {
                    _hist = [];
                    _histIndex = -1;
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ),
            for (final c in items)
              ListTile(
                dense: true,
                leading: const Icon(Icons.history, size: 18),
                title: Text(
                  c,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _input.text = picked;
        _histIndex = -1;
      });
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
  }

  void _interrupt() {
    // Soft interrupt signal over terminal channel (Host may map to Ctrl-C).
    if (_bridge == null || _connecting) return;
    try {
      _bridge!.terminalInput(
        sessionKey: widget.session.sessionKey,
        data: '\u0003',
        streamId: _streamId,
      );
      setState(() {
        _buf.writeln('^C');
        _busy = false;
      });
    } catch (e) {
      setState(() => _error = Security.redactText(e.toString()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _findCtrl.dispose();
    _scroll.dispose();
    unawaited(_bridge?.close() ?? Future.value());
    super.dispose();
  }

  String get _displayBuffer {
    final full = _buf.toString();
    final rawQ = _findQuery.trim();
    var lines = full.split('\n');
    // Drop trailing empty from final newline for consistent processing.
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines = lines.sublist(0, lines.length - 1);
    }
    if (rawQ.isNotEmpty) {
      if (_findRegex) {
        try {
          final re = RegExp(rawQ, caseSensitive: _findCase);
          lines = lines.where((l) => re.hasMatch(l)).toList();
        } catch (_) {
          return '(invalid regex: $_findQuery)\n';
        }
      } else {
        final q = _findCase ? rawQ : rawQ.toLowerCase();
        lines = lines
            .where((l) => (_findCase ? l : l.toLowerCase()).contains(q))
            .toList();
      }
      if (lines.isEmpty) return '(${AppStrings.terminalNoMatch}: $_findQuery)\n';
    }
    if (_showTs) {
      // Display-only synthetic stamps (not from Host) — local console aid.
      final now = DateTime.now();
      final stamped = <String>[];
      for (var i = 0; i < lines.length; i++) {
        final t = now.subtract(Duration(seconds: lines.length - 1 - i));
        final hh = t.hour.toString().padLeft(2, '0');
        final mm = t.minute.toString().padLeft(2, '0');
        final ss = t.second.toString().padLeft(2, '0');
        stamped.add('[$hh:$mm:$ss] ${lines[i]}');
      }
      lines = stamped;
    }
    if (_newestFirst) {
      lines = lines.reversed.toList();
    }
    return lines.isEmpty ? '' : (lines.join('\n') + '\n');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Foreground resume: re-open Bridge when dropped (P4-4 terminal).
      if (_bridge == null && !_connecting) {
        _connect();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _connecting
                    ? Colors.amber
                    : _bridge != null
                        ? Colors.green
                        : Colors.redAccent,
              ),
            ),
            Expanded(
              child: Text(
                '${AppStrings.terminalTitle} · ${widget.session.project} · ${_termCols}x$_termRows',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _showFind ? '隐藏查找' : AppStrings.terminalFind,
            onPressed: () {
              setState(() {
                _showFind = !_showFind;
                if (!_showFind) {
                  _findQuery = '';
                  _findCtrl.clear();
                }
              });
            },
            icon: Icon(_showFind ? Icons.search_off : Icons.search),
          ),
          IconButton(
            tooltip: AppStrings.terminalHistory,
            onPressed: _pickHistory,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: '重新连接',
            onPressed: _connecting
                ? null
                : () async {
                    await _bridge?.close();
                    await _connect();
                  },
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: AppStrings.more,
            onSelected: (value) async {
              switch (value) {
                case 'clear':
                  setState(() {
                    _buf.clear();
                    _busy = false;
                  });
                  break;
                case 'copy':
                  final text = _buf.toString();
                  if (text.trim().isEmpty) return;
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已复制 ${text.length} 字符'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                  break;
                case 'csv':
                  final raw = _buf.toString();
                  if (raw.trim().isEmpty) return;
                  final lines = raw.split('\n');
                  final buf = StringBuffer();
                  buf.writeln('n,text');
                  for (var i = 0; i < lines.length; i++) {
                    final text = lines[i].replaceAll('"', '""');
                    buf.writeln('$i,"$text"');
                  }
                  await Clipboard.setData(ClipboardData(text: buf.toString()));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已复制 CSV（${lines.length} 行）'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                  break;
                case 'top':
                  if (!_scroll.hasClients) return;
                  _scroll.animateTo(0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut);
                  break;
                case 'bottom':
                  if (!_scroll.hasClients) return;
                  _scroll.animateTo(_scroll.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut);
                  break;
                case 'smaller':
                  if (_termScale > 0.85) await _setTermScale(_termScale - 0.1);
                  break;
                case 'larger':
                  if (_termScale < 1.4) await _setTermScale(_termScale + 0.1);
                  break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.copy_all_outlined),
                  title: Text('复制全部'),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart_outlined),
                  title: Text('复制 CSV'),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_sweep_outlined),
                  title: Text(AppStrings.terminalClear),
                  dense: true,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'top',
                child: ListTile(
                  leading: Icon(Icons.vertical_align_top),
                  title: Text(AppStrings.jumpTop),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'bottom',
                child: ListTile(
                  leading: Icon(Icons.vertical_align_bottom),
                  title: Text(AppStrings.jumpBottom),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'smaller',
                child: ListTile(
                  leading: Icon(Icons.text_decrease),
                  title: Text('更小字号'),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'larger',
                child: ListTile(
                  leading: Icon(Icons.text_increase),
                  title: Text('更大字号'),
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.info_outline, size: 18),
              title: const Text(AppStrings.terminalHint),
              subtitle: Text('Bridge terminal_input / terminal_out · 几何 ${_termCols}×${_termRows}'),
            ),
          ),
          if (_error != null)
            Material(
              color: cs.errorContainer,
              child: ListTile(
                dense: true,
                title: Text(
                  _error!,
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _error = null),
                ),
              ),
            ),
          if (_connecting) const LinearProgressIndicator(minHeight: 2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: Row(
              children: [
                for (final item in <(String, bool, void Function(bool))>[
                  (AppStrings.terminalWrap, _wrapLines, (v) => setState(() => _wrapLines = v)),
                  (
                    AppStrings.terminalNewest,
                    _newestFirst,
                    (v) => setState(() => _newestFirst = v),
                  ),
                  (AppStrings.terminalTimestamps, _showTs, (v) => setState(() => _showTs = v)),
                  (AppStrings.terminalFindChip, _showFind, (v) => setState(() => _showFind = v)),
                  (AppStrings.regex, _findRegex, (v) => setState(() => _findRegex = v)),
                  (AppStrings.matchCase, _findCase, (v) => setState(() => _findCase = v)),
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
          Material(
            color: cs.surfaceContainerLow,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  for (final q in const [
                    ('help', 'help'),
                    ('pwd', 'pwd'),
                    ('ls', 'ls'),
                    ('whoami', 'whoami'),
                    ('y', 'y'),
                    ('n', 'n'),
                    ('^C', null),
                    ('clear', 'clear'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(q.$1, style: const TextStyle(fontSize: 12)),
                        onPressed: (_connecting || _bridge == null)
                            ? null
                            : () {
                                if (q.$2 == null) {
                                  _interrupt();
                                } else {
                                  _quick(q.$2!);
                                }
                              },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_showFind)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: TextField(
                controller: _findCtrl,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: _findRegex
                      ? (_findCase
                          ? '正则查找（区分大小写，仅客户端）'
                          : '正则查找（仅客户端）')
                      : (_findCase
                          ? '查找（区分大小写，仅客户端）'
                          : '本地缓冲查找（仅客户端）'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: IconButton(
                    tooltip: _findRegex
                        ? (_findCase
                            ? '正则 · 大小写开（长按普通查找）'
                            : '正则 · 大小写关（长按普通查找）')
                        : (_findCase
                            ? '区分大小写（长按切换正则）'
                            : '不区分大小写（长按切换正则）'),
                    icon: Icon(
                      _findRegex
                          ? Icons.code
                          : (_findCase ? Icons.text_fields : Icons.search),
                      size: 18,
                    ),
                    onPressed: () => setState(() => _findCase = !_findCase),
                    onLongPress: () => setState(() => _findRegex = !_findRegex),
                  ),
                  suffixIcon: _findQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _findCtrl.clear();
                            setState(() => _findQuery = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _findQuery = v),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _updateGeometryFromBox(constraints);
                });
                return Container(
                  width: double.infinity,
                  color: Colors.black,
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection:
                          _wrapLines ? Axis.vertical : Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.sizeOf(context).width - 24,
                          maxWidth: _wrapLines
                              ? MediaQuery.sizeOf(context).width - 24
                              : double.infinity,
                        ),
                        child: SelectableText(
                          _displayBuffer,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13 * _termScale,
                            color: const Color(0xFFB2FF59),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '更早',
                    onPressed: _hist.isEmpty ? null : _histUp,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    tooltip: '更新（历史下一条）',
                    onPressed: _histIndex < 0 ? null : _histDown,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_connecting && _bridge != null,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: '$_workdir › 命令…',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      inputFormatters: [LengthLimitingTextInputFormatter(4000)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_connecting || _bridge == null || _busy)
                        ? null
                        : _send,
                    child: const Text(AppStrings.terminalRun),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
