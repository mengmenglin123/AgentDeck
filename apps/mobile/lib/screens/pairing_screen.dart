
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/connection_config.dart';
import '../services/mgmt_client.dart';
import '../utils/security.dart';

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
    if (c != null && c.isNotEmpty) return c;
    final cfg = widget.config;
    return 'huanhermes://connect?host=${cfg.host}&bridge=${cfg.bridgePort}&mgmt=${cfg.mgmtPort}&tls=${cfg.useTls ? 1 : 0}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Device pairing')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (error != null) Text(error!, style: TextStyle(color: cs.error)),
                Text(
                  'Share this connection stub (no tokens). Paste into Connect or scan as text QR elsewhere.',
                  style: Theme.of(context).textTheme.bodyMedium,
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
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied pairing text')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
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
                      'Tokens stay on each device. Never put secrets in QR payloads committed to git.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
    );
  }
}
