
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    _name.dispose();
    _host.dispose();
    _bridgePort.dispose();
    _mgmtPort.dispose();
    _bridgeToken.dispose();
    _mgmtToken.dispose();
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
      final err = Security.redactText(controller.lastError ?? 'Connection failed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _importPairing() async {
    final ctrl = TextEditingController();
    final pasted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import pairing URI'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'huanhermes://connect?host=…&bridge=…&mgmt=…&tls=0',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (pasted == null || pasted.isEmpty || !mounted) return;
    final overlay = ConnectionConfig.tryParsePairingUri(pasted);
    if (overlay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not parse pairing URI')),
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
              ? 'Host fields + tokens imported (review before connect)'
              : 'Host fields filled — still enter tokens, then Test & connect',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ConnectionController>();
    final phase = controller.phase;
    final busy = phase == ConnectionPhase.testing;
    final warnTls = Security.shouldWarnPlaintext(_host.text.trim(), _useTls);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Host'),
        actions: [
          IconButton(
            tooltip: 'Copy public',
            onPressed: () async {
              final host = _host.text.trim();
              if (host.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter host first'), duration: Duration(seconds: 1)),
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
              await Clipboard.setData(ClipboardData(text: cfg.toPublicSummary()));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Public summary copied (no tokens)'), duration: Duration(seconds: 1)),
              );
            },
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            tooltip: 'Import pairing URI',
            onPressed: busy ? null : _importPairing,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: 'New profile',
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
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'HuanHermes is a console only — agents run on your server. '
              'Tokens stay in secure storage. Do not paste secrets into git.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _ConnectionStatusBanner(controller: controller),
            if (controller.profiles.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Saved hosts', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: controller.profiles.map((p) {
                  final selected = p.id == controller.activeProfileId;
                  return FilterChip(
                    label: Text(p.name),
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
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Profile name',
                hintText: 'Home / Work / Mock',
              ),
              enabled: !busy,
              onChanged: controller.updateDraftProfileName,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText: '127.0.0.1 or your.domain',
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
                    decoration: const InputDecoration(labelText: 'Bridge port'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    enabled: !busy,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _mgmtPort,
                    decoration: const InputDecoration(labelText: 'Mgmt port'),
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
              title: const Text('Use TLS (wss / https)'),
              subtitle: const Text('Recommended for public networks'),
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
                  title: Text('Plaintext to non-local host'),
                  subtitle: Text(
                    'Traffic is not encrypted. Prefer a TLS reverse proxy, '
                    'or enable TLS on your Host. Tokens still stay on device.',
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _bridgeToken,
              obscureText: _obscureBridge,
              decoration: InputDecoration(
                labelText: 'Bridge token',
                suffixIcon: IconButton(
                  icon: Icon(_obscureBridge ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureBridge = !_obscureBridge),
                ),
              ),
              enabled: !busy,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mgmtToken,
              obscureText: _obscureMgmt,
              decoration: InputDecoration(
                labelText: 'Management token',
                suffixIcon: IconButton(
                  icon: Icon(_obscureMgmt ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureMgmt = !_obscureMgmt),
                ),
              ),
              enabled: !busy,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy ? null : _onConnect,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: Text(busy ? 'Connecting…' : 'Test & connect'),
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
                            title: const Text('Delete this profile?'),
                            content: const Text(
                              'Tokens for this profile will be removed from the device.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete'),
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
                label: const Text('Delete profile'),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'See docs/guides/connect-real-host.md — fill tokens in the App only; '
              'do not change Host channel/provider config for this App.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatusBanner extends StatelessWidget {
  const _ConnectionStatusBanner({required this.controller});

  final ConnectionController controller;

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
          title = 'Connected · health degraded';
          subtitle = controller.lastHealthError ?? 'Last /status probe failed';
        } else {
          color = Colors.green;
          icon = Icons.check_circle_outline;
          title = 'Connected · ready';
          final ok = controller.lastHealthOkAt;
          subtitle = ok == null
              ? 'Host profile active'
              : 'Last health OK ${ok.toLocal().toIso8601String().substring(11, 19)}';
        }
      case ConnectionPhase.testing:
        color = Colors.amber.shade800;
        icon = Icons.hourglass_top;
        title = 'Testing connection…';
        subtitle = 'Probing management + bridge';
      case ConnectionPhase.error:
        color = cs.error;
        icon = Icons.error_outline;
        title = 'Connection error';
        subtitle = controller.lastError ?? 'Check host / ports / tokens';
      case ConnectionPhase.idle:
        color = cs.onSurfaceVariant;
        icon = Icons.link_off;
        title = 'Not connected';
        subtitle = 'Fill profile and Test & Save';
    }
    return Card(
      color: color.withOpacity(0.12),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        subtitle: Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
