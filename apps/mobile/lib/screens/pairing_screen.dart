import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/app_settings_controller.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';
import '../widgets/connection_fingerprint.dart';

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
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _armTimer() {
    _timer?.cancel();
    if (!_autoRefresh || !mounted) return;
    final sec = context.read<AppSettingsController>().dashboardRefreshSec;
    if (sec <= 0) return;
    _timer = Timer.periodic(Duration(seconds: sec), (_) {
      if (!mounted || loading) return;
      _load();
    });
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cfg = widget.config;
    final publicUri = cfg.toPairingUri();
    return Scaffold(
      appBar: AppBar(
        title: Text(_autoRefresh ? 'Device pairing · auto' : 'Device pairing'),
        actions: [
          IconButton(
            tooltip: 'Copy public summary',
            onPressed: () => _copy(cfg.toPublicSummary(), 'Copied public summary'),
            icon: const Icon(Icons.notes_outlined),
          ),
          IconButton(
            tooltip: 'Copy public URI',
            onPressed: () => _copy(publicUri, 'Copied public pairing URI'),
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: 'Copy public JSON',
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
                          !'${e.value}'.toString().toLowerCase().contains('token='))
                        e.key: e.value,
                  },
              };
              _copy(const JsonEncoder.withIndent('  ').convert(payload), 'Copied public JSON');
            },
            icon: const Icon(Icons.data_object_outlined),
          ),

          IconButton(
            tooltip: _autoRefresh ? 'Pause auto-refresh' : 'Auto-refresh',
            onPressed: () {
              setState(() => _autoRefresh = !_autoRefresh);
              _armTimer();
            },
            icon: Icon(_autoRefresh ? Icons.pause_circle_outline : Icons.play_circle_outline),
          ),
          IconButton(
            tooltip: 'Jump to top',
            onPressed: () {
              if (!_scroll.hasClients) return;
              _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
            },
            icon: const Icon(Icons.vertical_align_top),
          ),
          IconButton(
            tooltip: 'Jump to end',
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

          IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
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
                if (error != null) Text(error!, style: TextStyle(color: cs.error)),
                Text(
                  'Share connection stub without tokens. Paste into Connect on another device. '
                  'Visual fingerprint is for human verification only — not a camera QR (P4).',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Center(child: ConnectionFingerprint(seed: publicUri, size: 220, cells: 13)),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'fingerprint · ${cfg.host}:${cfg.bridgePort}/${cfg.mgmtPort}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: SelectableText(
                    'hex ${_fpHex(publicUri)}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace'),
                  ),
                ),
                Center(
                  child: TextButton.icon(
                    onPressed: () => _copy(_fpHex(publicUri), 'Fingerprint hex copied'),
                    icon: const Icon(Icons.tag, size: 16),
                    label: const Text('Copy fingerprint hex'),
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
                  child: SelectableText(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _copy(code, 'Copied pairing text'),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy URI'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _copy(cfg.toPublicSummary(), 'Copied public summary'),
                      icon: const Icon(Icons.notes_outlined),
                      label: const Text('Copy summary'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _copy(publicUri, 'Copied public pairing URI'),
                      icon: const Icon(Icons.link),
                      label: const Text('Copy public URI'),
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
                        Text('Verify checklist', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        const Text('1. Compare visual fingerprint on both devices'),
                        const Text('2. Match host:ports line and hex tag'),
                        const Text('3. Paste public URI only (never share tokens)'),
                        const Text('4. Camera QR scan remains P4'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Host payload (redacted)', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SelectableText(
                  Security.redactText(data.toString()),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 16),
                Text(
                  data['note']?.toString() ??
                      'Tokens stay on each device. Camera QR scan is not implemented yet.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
    );
  }
}
