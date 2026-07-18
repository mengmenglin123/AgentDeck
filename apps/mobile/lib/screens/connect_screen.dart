import 'dart:convert';

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
            tooltip: 'Copy fingerprint hex',
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
              );
              final hex = _fpHex(cfg.toPairingUri());
              await Clipboard.setData(ClipboardData(text: hex));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Fingerprint $hex'), duration: const Duration(seconds: 1)),
              );
            },
            icon: const Icon(Icons.fingerprint),
          ),

          IconButton(
            tooltip: 'Copy profiles (no tokens)',
            onPressed: controller.profiles.isEmpty
                ? null
                : () async {
                    final list = controller.profiles.map((p) => p.toPublicJson()).toList();
                    final text = const JsonEncoder.withIndent('  ').convert({
                      'huanhermes.profiles_public.v1': true,
                      'count': list.length,
                      'profiles': list,
                    });
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied ${list.length} public profile(s)'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.ios_share_outlined),
          ),
          IconButton(
            tooltip: 'Copy profiles CSV',
            onPressed: controller.profiles.isEmpty
                ? null
                : () async {
                    final buf = StringBuffer();
                    buf.writeln('id,name,host,bridge_port,mgmt_port,use_tls,note');
                    for (final p in controller.profiles) {
                      final id = p.id.replaceAll('"', '""');
                      final name = p.name.replaceAll('"', '""');
                      final host = p.config.host.replaceAll('"', '""');
                      final note = (p.note ?? '').replaceAll('"', '""');
                      buf.writeln(
                        '"$id","$name","$host",${p.config.bridgePort},${p.config.mgmtPort},${p.config.useTls},"$note"',
                      );
                    }
                    await Clipboard.setData(ClipboardData(text: buf.toString()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied profiles CSV (${controller.profiles.length})'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: _wrapLines ? 'Clamp health text' : 'Wrap health text',
            onPressed: () => setState(() => _wrapLines = !_wrapLines),
            icon: Icon(_wrapLines ? Icons.wrap_text : Icons.notes),
          ),
          IconButton(
            tooltip: _sortMode == 'tls'
                ? (_sortAsc ? 'TLS first' : 'Plain first')
                : (_sortMode == 'bridgePort'
                    ? (_sortAsc ? 'Bridge port high→low' : 'Bridge port low→high')
                    : (_sortMode == 'note'
                        ? (_sortAsc ? 'Note Z→A' : 'Note A→Z')
                        : (_sortMode == 'port'
                            ? (_sortAsc ? 'Mgmt port high→low' : 'Mgmt port low→high')
                            : (_sortMode == 'host'
                                ? (_sortAsc ? 'Host Z→A' : 'Host A→Z')
                                : (_sortMode == 'updated'
                                    ? (_sortAsc ? 'Updated new→old' : 'Updated old→new')
                                    : (_sortAsc ? 'Profiles Z→A' : 'Profiles A→Z')))))),
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
                  _sortAsc = true;
                } else if (_sortMode == 'updated' && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortMode == 'updated' && !_sortAsc) {
                  _sortMode = 'port';
                  _sortAsc = true;
                } else if (_sortMode == 'port' && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortMode == 'port' && !_sortAsc) {
                  _sortMode = 'note';
                  _sortAsc = true;
                } else if (_sortMode == 'note' && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortMode == 'note' && !_sortAsc) {
                  _sortMode = 'bridgePort';
                  _sortAsc = true;
                } else if (_sortMode == 'bridgePort' && _sortAsc) {
                  _sortAsc = false;
                } else if (_sortMode == 'bridgePort' && !_sortAsc) {
                  _sortMode = 'tls';
                  _sortAsc = true;
                } else if (_sortMode == 'tls' && _sortAsc) {
                  _sortAsc = false;
                } else {
                  _sortMode = 'name';
                  _sortAsc = true;
                }
              });
            },
            icon: Icon(_sortMode == 'tls'
                ? Icons.lock_outline
                : (_sortMode == 'bridgePort'
                    ? Icons.settings_ethernet
                    : (_sortMode == 'note'
                        ? Icons.sticky_note_2_outlined
                        : (_sortMode == 'port'
                            ? Icons.tag
                            : (_sortMode == 'host'
                                ? Icons.dns_outlined
                                : (_sortMode == 'updated'
                                    ? Icons.schedule
                                    : (_sortAsc ? Icons.sort_by_alpha : Icons.sort))))))),
          ),

          IconButton(
            tooltip: 'Jump to top',
            onPressed: () {
              if (!_scroll.hasClients) return;
              _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
            },
            icon: const Icon(Icons.vertical_align_top),
          ),

          IconButton(
            tooltip: 'Jump to end',
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
          controller: _scroll,
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
                spacing: 6,
                children: [
                  for (final f in [
                    ('all', 'All TLS'),
                    ('tls', 'TLS'),
                    ('plain', 'Plain'),
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
              TextField(
                controller: _profileFilterCtrl,
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText: _queryRegex
                      ? (_queryCase
                          ? 'Filter profiles (regex · case)'
                          : 'Filter profiles (regex)')
                      : (_queryCase
                          ? 'Filter profiles (case-sensitive)'
                          : 'Filter profiles name/host/note'),
                  prefixIcon: IconButton(
                    tooltip: _queryRegex
                        ? (_queryCase
                            ? 'Regex · case on (long-press: plain filter)'
                            : 'Regex · case off (long-press: plain filter)')
                        : (_queryCase
                            ? 'Case-sensitive (long-press: regex)'
                            : 'Case-insensitive (long-press: regex)'),
                    icon: Icon(
                      _queryRegex
                          ? Icons.code
                          : (_queryCase ? Icons.text_fields : Icons.search),
                      size: 18,
                    ),
                    onPressed: () => setState(() => _queryCase = !_queryCase),
                    onLongPress: () => setState(() => _queryRegex = !_queryRegex),
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
                children: (List.of(controller.profiles)
                    .where((p) {
                      if (_tlsFilter == 'tls' && !p.config.useTls) return false;
                      if (_tlsFilter == 'plain' && p.config.useTls) return false;
                      final rawQ = _profileQuery.trim();
                      if (rawQ.isEmpty) return true;
                      final hayRaw =
                          '${p.name} ${p.config.host} ${p.config.bridgePort} ${p.config.mgmtPort} ${p.note ?? ''}';
                      if (_queryRegex) {
                        try {
                          return RegExp(rawQ, caseSensitive: _queryCase).hasMatch(hayRaw);
                        } catch (_) {
                          return false;
                        }
                      }
                      final q = _queryCase ? rawQ : rawQ.toLowerCase();
                      final hay = _queryCase ? hayRaw : hayRaw.toLowerCase();
                      return hay.contains(q);
                    })
                    .toList()
                  ..sort((a, b) {
                    int c;
                    if (_sortMode == 'host') {
                      c = a.config.host.toLowerCase().compareTo(b.config.host.toLowerCase());
                      if (c == 0) {
                        c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
                      }
                    } else if (_sortMode == 'updated') {
                      c = a.updatedAt.compareTo(b.updatedAt);
                      if (c == 0) {
                        c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
                      }
                    } else if (_sortMode == 'port') {
                      c = a.config.mgmtPort.compareTo(b.config.mgmtPort);
                      if (c == 0) {
                        c = a.config.bridgePort.compareTo(b.config.bridgePort);
                      }
                      if (c == 0) {
                        c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
                      }
                    } else if (_sortMode == 'note') {
                      c = (a.note ?? '').toLowerCase().compareTo((b.note ?? '').toLowerCase());
                      if (c == 0) {
                        c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
                      }
                    } else if (_sortMode == 'bridgePort') {
                      c = a.config.bridgePort.compareTo(b.config.bridgePort);
                      if (c == 0) {
                        c = a.config.mgmtPort.compareTo(b.config.mgmtPort);
                      }
                      if (c == 0) {
                        c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
                      }
                    } else if (_sortMode == 'tls') {
                      final ta = a.config.useTls ? 1 : 0;
                      final tb = b.config.useTls ? 1 : 0;
                      c = ta.compareTo(tb);
                      if (c == 0) {
                        c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
                      }
                    } else {
                      c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
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
    final lat = controller.lastTestLatencyMs;
    if (lat != null && phase != ConnectionPhase.testing) {
      subtitle = subtitle + ' · last test ' + lat.toString() + ' ms';
    }
    return Card(
      color: color.withOpacity(0.12),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        subtitle: Text(
          subtitle,
          maxLines: _wrapLines ? 8 : 3,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
        ),
      ),
    );
  }
}
