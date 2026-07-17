
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/connection_config.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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
        title: const Text('Device pairing'),
        actions: [
          IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (error != null) Text(error!, style: TextStyle(color: cs.error)),
                Text(
                  'Share connection stub without tokens. Paste into Connect on another device. '
                  'Visual fingerprint is for human verification only — not a camera QR (P4).',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Center(child: ConnectionFingerprint(seed: publicUri, size: 168)),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'fingerprint · ${cfg.host}:${cfg.bridgePort}/${cfg.mgmtPort}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontFamily: 'monospace'),
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
    );
  }
}
