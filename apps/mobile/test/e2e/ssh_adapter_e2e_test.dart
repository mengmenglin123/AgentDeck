// Real dartssh2 adapter (socket, KEX, host-key callback, password auth,
// exec, SFTP upload) against a loopback paramiko server. Skips when python3
// or paramiko is unavailable.
@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/models/discovered_agent.dart';
import 'package:huanhermes_app/services/ssh_bootstrap_service.dart';
import 'package:huanhermes_app/services/ssh_discovery_service.dart';

Process? _proc;
int _port = 0;
String _fp = '';
String? _skip;

String _script() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final f = File('${dir.path}/test/e2e/fake_sshd.py');
    if (f.existsSync()) return f.path;
    final g = File('${dir.path}/apps/mobile/test/e2e/fake_sshd.py');
    if (g.existsSync()) return g.path;
    dir = dir.parent;
  }
  throw StateError('fake_sshd.py not found');
}

void main() {
  setUpAll(() async {
    try {
      final probe = await Process.run('python3', ['-c', 'import paramiko']);
      if (probe.exitCode != 0) {
        _skip = 'paramiko not installed';
        return;
      }
    } catch (_) {
      _skip = 'python3 not available';
      return;
    }
    _proc = await Process.start('python3', [_script()]);
    final lines = _proc!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    _proc!.stderr.transform(utf8.decoder).listen(stderr.write);
    await for (final l in lines.timeout(const Duration(seconds: 20))) {
      if (l.startsWith('PORT ')) _port = int.parse(l.substring(5));
      if (l.startsWith('FP ')) {
        _fp = l.substring(3);
        break;
      }
    }
  });

  tearDownAll(() => _proc?.kill());

  test('discovery over real SSH: host key fingerprint matches the server',
      () async {
    if (_skip != null) return markTestSkipped(_skip!);
    SshHostKey? seen;
    final r = await SshDiscoveryService().discover(
      host: '127.0.0.1',
      port: _port,
      username: 'u',
      password: 'pw',
      verifyHostKey: (k) async {
        seen = k;
        // Slow user: must not trip the connect timeout.
        await Future<void>.delayed(const Duration(seconds: 3));
        return true;
      },
      timeout: const Duration(seconds: 2),
    );
    expect(seen!.fingerprint, _fp);
    expect(r.hostKey.fingerprint, _fp);
    expect(r.agents.single.kind, DiscoveredAgentKind.codex);
    expect(r.stderr, 'motd noise');
    expect(r.remoteVersion, contains('paramiko'));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('wrong password → auth error; rejected key → no commands', () async {
    if (_skip != null) return markTestSkipped(_skip!);
    await expectLater(
      SshDiscoveryService().discover(
        host: '127.0.0.1',
        port: _port,
        username: 'u',
        password: 'wrong',
        verifyHostKey: (_) async => true,
      ),
      throwsA(isA<SshDiscoveryException>()
          .having((e) => e.message, 'message', contains('认证失败'))),
    );
    await expectLater(
      SshDiscoveryService().discover(
        host: '127.0.0.1',
        port: _port,
        username: 'u',
        password: 'pw',
        verifyHostKey: (_) async => false,
      ),
      throwsA(isA<SshDiscoveryException>()
          .having((e) => e.message, 'message', contains('指纹未被确认'))),
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('install falls back to a real SFTP upload and installs from it',
      () async {
    if (_skip != null) return markTestSkipped(_skip!);
    final archive = Uint8List.fromList(List<int>.generate(70000, (i) => i % 251));
    final r = await SshBootstrapService(assetLoader: (_) async => archive)
        .install(
      host: '127.0.0.1',
      port: _port,
      username: 'u',
      password: 'pw',
      verifyHostKey: (k) async => k.fingerprint == _fp,
    );
    expect(r.version, '0.1.204');
    expect(r.configPath, '/c/host.toml');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
