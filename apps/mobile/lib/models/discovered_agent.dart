enum DiscoveredAgentKind { codex, claudeCode, hermes }

class DiscoveredAgent {
  const DiscoveredAgent({
    required this.kind,
    required this.command,
    required this.path,
    required this.version,
    required this.driver,
    this.capabilities = const [],
  });

  final DiscoveredAgentKind kind;
  final String command;
  final String path;
  final String version;
  final String driver;
  final List<String> capabilities;

  String get id => switch (kind) {
        DiscoveredAgentKind.codex => 'codex',
        DiscoveredAgentKind.claudeCode => 'claude-code',
        DiscoveredAgentKind.hermes => 'hermes',
      };

  String get label => switch (kind) {
        DiscoveredAgentKind.codex => 'Codex',
        DiscoveredAgentKind.claudeCode => 'Claude Code',
        DiscoveredAgentKind.hermes => 'Hermes',
      };

  factory DiscoveredAgent.fromProbe({
    required String command,
    required String path,
    required String version,
  }) {
    final normalized = command.trim().toLowerCase();
    final kind = switch (normalized) {
      'codex' => DiscoveredAgentKind.codex,
      'claude' || 'claude-code' => DiscoveredAgentKind.claudeCode,
      'hermes' || 'hermes-agent' => DiscoveredAgentKind.hermes,
      _ => throw FormatException('unsupported agent: $command'),
    };
    final driver = switch (kind) {
      DiscoveredAgentKind.codex => 'codex_exec_json',
      DiscoveredAgentKind.claudeCode => 'claude_stream_json',
      DiscoveredAgentKind.hermes => 'hermes_text',
    };
    final capabilities = switch (kind) {
      DiscoveredAgentKind.codex => const ['stream', 'model', 'tools', 'terminal'],
      DiscoveredAgentKind.claudeCode => const ['stream', 'model', 'tools'],
      DiscoveredAgentKind.hermes => const ['stream', 'tools'],
    };
    return DiscoveredAgent(
      kind: kind,
      command: normalized,
      path: path.trim(),
      version: version.trim(),
      driver: driver,
      capabilities: capabilities,
    );
  }
}

class SshHostKey {
  const SshHostKey({required this.type, required this.fingerprint});

  final String type;
  final String fingerprint;
}

class SshDiscoveryResult {
  const SshDiscoveryResult({
    required this.host,
    required this.remoteVersion,
    required this.agents,
    required this.hostKey,
    this.stderr = '',
    this.exitCode,
    this.bridgeToken,
    this.mgmtToken,
    this.bridgePort = 9810,
    this.mgmtPort = 9820,
  });

  final String host;
  final String remoteVersion;
  final List<DiscoveredAgent> agents;
  final SshHostKey hostKey;
  final String stderr;
  final int? exitCode;
  final String? bridgeToken;
  final String? mgmtToken;
  final int bridgePort;
  final int mgmtPort;
}
