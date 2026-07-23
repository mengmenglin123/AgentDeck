import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/models/discovered_agent.dart';
import 'package:huanhermes_app/services/ssh_discovery_service.dart';

void main() {
  test('parses installed agents and maps driver capabilities', () {
    const output = '''
banner from remote shell
HH_DISCOVERY\t1
HH_AGENT\tcodex\t/usr/bin/codex\tcodex-cli 0.137.0
HH_AGENT\tclaude\t/usr/bin/claude\t2.1.150 (Claude Code)
HH_AGENT\thermes\t/usr/local/bin/hermes\tHermes Agent v0.18.2
''';

    final agents = SshDiscoveryService.parseDiscoveryOutput(output);

    expect(agents, hasLength(3));
    expect(agents[0].kind, DiscoveredAgentKind.codex);
    expect(agents[0].driver, 'codex_exec_json');
    expect(agents[0].capabilities, contains('terminal'));
    expect(agents[1].kind, DiscoveredAgentKind.claudeCode);
    expect(agents[1].driver, 'claude_stream_json');
    expect(agents[2].kind, DiscoveredAgentKind.hermes);
    expect(agents[2].driver, 'hermes_stream_json');
  });

  test('ignores unknown, malformed, empty, and duplicate probes', () {
    const output = '''
HH_AGENT\tunknown\t/usr/bin/unknown\t1.0
HH_AGENT\tcodex\t\tmissing path
HH_AGENT\tcodex\t/usr/bin/codex\tfirst
HH_AGENT\tcodex\t/opt/codex\tduplicate
not a probe
''';

    final agents = SshDiscoveryService.parseDiscoveryOutput(output);

    expect(agents, hasLength(1));
    expect(agents.single.path, '/usr/bin/codex');
    expect(agents.single.version, 'first');
  });

  test('normalizes claude-code aliases', () {
    final agent = DiscoveredAgent.fromProbe(
      command: 'claude-code',
      path: '/opt/claude',
      version: '2.1',
    );

    expect(agent.id, 'claude-code');
    expect(agent.label, 'Claude Code');
  });
}
