import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/models/host_capabilities.dart';
import 'package:huanhermes_app/models/session_info.dart';

void main() {
  test('parses nested mock runtime and host capabilities', () {
    final runtime = HostRuntimeInfo.fromStatus({
      'version': 'mock-0.1.194',
      'capabilities': ['sessions', 'terminal', 'sessions', ''],
      'hermes': {'adapter': 'mock', 'process': false},
    });

    expect(runtime.version, 'mock-0.1.194');
    expect(runtime.adapterType, 'mock');
    expect(runtime.isRealHermes, isFalse);
    expect(runtime.displayLabel, 'Mock');
    expect(runtime.capabilities.supports('terminal'), isTrue);
    expect(runtime.capabilities.values.length, 2);
  });

  test('prefers explicit adapter and recognises live Hermes process', () {
    final runtime = HostRuntimeInfo.fromStatus({
      'adapter': 'compatible',
      'hermes': {'adapter': 'mock', 'process': true},
    });

    expect(runtime.adapterType, 'compatible');
    expect(runtime.isRealHermes, isTrue);
    expect(runtime.displayLabel, '真 Hermes');
  });

  test('normalises project capability values', () {
    final capabilities = CapabilitySet.from(['stream', 1, null, ' stream ']);
    expect(capabilities.supports('stream'), isTrue);
    expect(capabilities.supports('1'), isTrue);
    expect(capabilities.values.length, 2);
  });

  test('project capability gate distinguishes catalog support', () {
    final claude = ProjectInfo.fromJson({
      'name': 'claude-code',
      'agent_type': 'claudecode',
      'capabilities': ['skills_catalog', 'mcp_catalog', 'terminal'],
    });
    final hermes = ProjectInfo.fromJson({
      'name': 'hermes',
      'agent_type': 'hermes',
      'capabilities': ['memory_readonly', 'skills_catalog', 'mcp_catalog'],
    });
    expect(claude.hasCapability('skills_catalog'), isTrue);
    expect(claude.hasCapability('memory_readonly'), isFalse);
    expect(hermes.hasCapability('memory_readonly'), isTrue);
  });
}
