import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/connection_config.dart';
import '../models/session_info.dart';
import '../services/bridge_client.dart';
import '../utils/security.dart';

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

class _TerminalScreenState extends State<TerminalScreen> {
  BridgeClient? _bridge;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _buf = StringBuffer();
  String _streamId = 'term-ui';
  bool _connecting = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _buf.writeln('HuanHermes terminal channel (session ${widget.session.sessionKey})');
    _buf.writeln('Type help · protocol demo only');
    _buf.writeln('');
    _connect();
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
      b.terminalResize(sessionKey: widget.session.sessionKey);
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

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty || _bridge == null || _busy) return;
    _input.clear();
    _sendRaw(text);
  }

  void _quick(String cmd) {
    if (_bridge == null || _busy || _connecting) return;
    _sendRaw(cmd);
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
    _input.dispose();
    _scroll.dispose();
    unawaited(_bridge?.close() ?? Future.value());
    super.dispose();
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
                'Terminal · ${widget.session.project}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            onPressed: () async {
              final text = _buf.toString();
              if (text.trim().isEmpty) return;
              await Clipboard.setData(ClipboardData(text: text));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied ${text.length} chars'), duration: const Duration(seconds: 1)),
              );
            },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Clear local buffer',
            onPressed: () => setState(_buf.clear),
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Reconnect',
            onPressed: _connecting
                ? null
                : () async {
                    await _bridge?.close();
                    await _connect();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Material(
              color: cs.errorContainer,
              child: ListTile(
                dense: true,
                title: Text(_error!, style: TextStyle(color: cs.onErrorContainer, fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _error = null),
                ),
              ),
            ),
          if (_connecting) const LinearProgressIndicator(minHeight: 2),
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
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                controller: _scroll,
                child: SelectableText(
                  _buf.toString(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Color(0xFFB2FF59),
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_connecting && _bridge != null,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        hintText: 'command…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      inputFormatters: [LengthLimitingTextInputFormatter(4000)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_connecting || _bridge == null || _busy) ? null : _send,
                    child: const Text('Run'),
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
