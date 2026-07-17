import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/session_info.dart';
import '../services/connection_controller.dart';
import '../services/session_controller.dart';
import 'chat_screen.dart';
import 'mcp_screen.dart';
import 'pairing_screen.dart';
import 'skills_screen.dart';
import 'terminal_screen.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  SessionController? _sessions;
  final _titleCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final conn = context.watch<ConnectionController>();
    final cfg = conn.saved;
    if (cfg == null) return;
    if (_sessions == null) {
      _sessions = SessionController(config: cfg)..refresh();
    } else {
      _sessions!.updateConfig(cfg);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    _sessions?.dispose();
    super.dispose();
  }

  List<SessionInfo> _filtered(List<SessionInfo> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((s) {
      final hay = '${s.displayTitle} ${s.project} ${s.sessionKey} ${s.model ?? ''}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _openTerminal(SessionInfo session) async {
    final conn = context.read<ConnectionController>();
    final cfg = conn.saved;
    if (cfg == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalScreen(config: cfg, session: session),
      ),
    );
  }

  Future<void> _create() async {
    final s = _sessions;
    if (s == null) return;
    final created = await s.createSession(
      title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
    );
    _titleCtrl.clear();
    if (!mounted) return;
    if (created != null) {
      await _openChat(created);
    } else if (s.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.error!)));
    }
  }

  Future<void> _openChat(SessionInfo session) async {
    final conn = context.read<ConnectionController>();
    final cfg = conn.saved;
    if (cfg == null) return;
    final caps = _sessions?.projects
            .where((p) => p.name == session.project)
            .map((p) => p.capabilities)
            .firstWhere((_) => true, orElse: () => const <String>[]) ??
        const <String>[];
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          config: cfg,
          session: session,
          projectCapabilities: caps,
        ),
      ),
    );
    // refresh after returning (mock may have updated last_user)
    await _sessions?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionController>();
    final sessions = _sessions;
    if (sessions == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AnimatedBuilder(
      animation: sessions,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Sessions'),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: sessions.loading ? null : sessions.refresh,
                icon: const Icon(Icons.refresh),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) {
                  final cfg = conn.saved;
                  if (cfg == null) return;
                  Widget page;
                  switch (v) {
                    case 'skills':
                      page = SkillsScreen(config: cfg);
                      break;
                    case 'mcp':
                      page = McpScreen(config: cfg);
                      break;
                    case 'pairing':
                      page = PairingScreen(config: cfg);
                      break;
                    default:
                      return;
                  }
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'skills', child: Text('Skills (readonly)')),
                  PopupMenuItem(value: 'mcp', child: Text('MCP (readonly)')),
                  PopupMenuItem(value: 'pairing', child: Text('Pairing URI')),
                ],
              ),
              IconButton(
                tooltip: 'Edit connection',
                onPressed: () => conn.disconnect(),
                icon: const Icon(Icons.settings_ethernet),
              ),
              IconButton(
                tooltip: 'Clear profile',
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Clear saved profile?'),
                      content: const Text('Removes host settings and tokens.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                      ],
                    ),
                  );
                  if (ok == true) await conn.disconnect(clearStorage: true);
                },
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: Column(
            children: [
              if (conn.saved != null)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.dns_outlined, size: 20),
                  title: Text(conn.saved!.host),
                  subtitle: Text(conn.saved!.mgmtBaseUrl),
                ),
              if (sessions.projects.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: DropdownButtonFormField<String>(
                    value: sessions.projects.any((p) => p.name == sessions.selectedProject)
                        ? sessions.selectedProject
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Project',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: sessions.projects
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.name,
                            child: Text('${p.name} (${p.agentType})'),
                          ),
                        )
                        .toList(),
                    onChanged: sessions.selectProject,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search sessions',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(
                          hintText: 'New session title (optional)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _create(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: sessions.loading ? null : _create,
                      icon: const Icon(Icons.add),
                      label: const Text('New'),
                    ),
                  ],
                ),
              ),
              if (sessions.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(sessions.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final visible = _filtered(sessions.sessions);
                    return sessions.loading && sessions.sessions.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            onRefresh: sessions.refresh,
                            child: sessions.sessions.isEmpty
                                ? ListView(
                                    children: [
                                      const SizedBox(height: 48),
                                      Icon(
                                        Icons.forum_outlined,
                                        size: 40,
                                        color: Theme.of(context).colorScheme.outline,
                                      ),
                                      const SizedBox(height: 12),
                                      const Center(child: Text('No sessions yet')),
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 24),
                                        child: Text(
                                          'Create a session for Claude Code / Codex / Hermes and open chat to control the server agent.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : visible.isEmpty
                                    ? ListView(
                                        children: const [
                                          SizedBox(height: 48),
                                          Center(child: Text('No sessions match search')),
                                        ],
                                      )
                                    : ListView.separated(
                                        itemCount: visible.length,
                                        separatorBuilder: (_, __) => const Divider(height: 1),
                                        itemBuilder: (context, i) {
                                          final s = visible[i];
                                          return ListTile(
                                            title: Text(s.displayTitle),
                                            subtitle: Text(
                                              '${s.project} · ${s.model ?? "model?"} · ${s.sessionKey}',
                                            ),
                                            isThreeLine: true,
                                            leading: Icon(
                                              s.running
                                                  ? Icons.play_circle_fill
                                                  : Icons.chat_bubble_outline,
                                              color: s.running ? Colors.blue : null,
                                            ),
                                            onTap: () => _openChat(s),
                                            trailing: Wrap(
                                              spacing: 0,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Terminal',
                                                  icon: const Icon(Icons.terminal),
                                                  onPressed: () => _openTerminal(s),
                                                ),
                                                IconButton(
                                                  tooltip: 'Delete',
                                                  icon: const Icon(Icons.delete_outline),
                                                  onPressed: () => sessions.deleteSession(s),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                          );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
