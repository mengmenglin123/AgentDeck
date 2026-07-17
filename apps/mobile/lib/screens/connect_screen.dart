import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/connection_config.dart';
import '../services/connection_controller.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
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
    final c = context.read<ConnectionController>().draft;
    _host = TextEditingController(text: c.host);
    _bridgePort = TextEditingController(text: '${c.bridgePort}');
    _mgmtPort = TextEditingController(text: '${c.mgmtPort}');
    _bridgeToken = TextEditingController(text: c.bridgeToken);
    _mgmtToken = TextEditingController(text: c.mgmtToken);
    _useTls = c.useTls;
  }

  @override
  void dispose() {
    _host.dispose();
    _bridgePort.dispose();
    _mgmtPort.dispose();
    _bridgeToken.dispose();
    _mgmtToken.dispose();
    super.dispose();
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
    controller.updateDraft(_readForm(controller.draft));
    final ok = await controller.testAndSave();
    if (!mounted) return;
    if (!ok) {
      final err = controller.lastError ?? 'Connection failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = context.watch<ConnectionController>().phase;
    final busy = phase == ConnectionPhase.testing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Host'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'HuanHermes talks to your server via Management REST + Bridge WebSocket. '
              'Tokens stay in secure storage and are never logged.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText: '127.0.0.1 or your.domain',
              ),
              textInputAction: TextInputAction.next,
              enabled: !busy,
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
              title: const Text('Use TLS (WSS / HTTPS)'),
              subtitle: const Text('Required for production hosts'),
              value: _useTls,
              onChanged: busy
                  ? null
                  : (v) => setState(() => _useTls = v),
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
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: busy ? null : _onConnect,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link),
              label: Text(busy ? 'Testing…' : 'Test & Save'),
            ),
            const SizedBox(height: 12),
            Text(
              'Dev defaults match Mock Host (.env.example). Do not use default tokens on a public network.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
