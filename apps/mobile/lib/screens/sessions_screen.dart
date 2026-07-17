import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/session_info.dart';
import '../services/connection_controller.dart';
import '../services/session_controller.dart';
import 'chat_screen.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  SessionController? _sessions;
  final _titleCtrl = TextEditingController();

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
    _sessions?.dispose();
    super.dispose();
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(config: cfg, session: session),
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                child: sessions.loading && sessions.sessions.isEmpty
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
                            : ListView.separated(
                                itemCount: sessions.sessions.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final s = sessions.sessions[i];
                                  return ListTile(
                                    title: Text(s.displayTitle),
                                    subtitle: Text(
                                      '${s.project} · ${s.model ?? "model?"} · ${s.sessionKey}',
                                    ),
                                    isThreeLine: true,
                                    leading: Icon(
                                      s.running ? Icons.play_circle_fill : Icons.chat_bubble_outline,
                                      color: s.running ? Colors.blue : null,
                                    ),
                                    onTap: () => _openChat(s),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => sessions.deleteSession(s),
                                    ),
                                  );
                                },
                              ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
