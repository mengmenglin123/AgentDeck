// Fake SSH layer for discovery / companion bootstrap tests: no sockets, no
// sshd. A FakeSshServer scripts command replies by prefix and records every
// connection, command and upload.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:huanhermes_app/services/ssh_session.dart';

typedef FakeReply = SshCommandResult Function(String command);

SshCommandResult ok([String out = '', String err = '']) => SshCommandResult(
      stdout: utf8.encode(out),
      stderr: utf8.encode(err),
      exitCode: 0,
    );

SshCommandResult failed(int code, [String err = '']) => SshCommandResult(
      stdout: const [],
      stderr: utf8.encode(err),
      exitCode: code,
    );

class FakeSshServer {
  FakeSshServer({
    this.hostKeyType = 'ssh-ed25519',
    this.fingerprint = 'SHA256:AAAAfakeHostKeyFingerprint0001',
    this.password = 'pw',
    this.presentHostKey = true,
  });

  String hostKeyType;
  String fingerprint;
  String password;
  bool presentHostKey;

  /// Ordered (predicate, reply) rules; first match wins.
  final rules = <(bool Function(String), FakeReply)>[];
  final commands = <String>[];
  final uploads = <String, Uint8List>{};
  final requests = <SshConnectRequest>[];
  int opened = 0;
  int closed = 0;

  void on(bool Function(String cmd) when, FakeReply reply) =>
      rules.add((when, reply));

  SshSessionOpener get opener => (request) async {
        requests.add(request);
        if (presentHostKey) {
          final accepted = await request.verifyHostKey(
            hostKeyType,
            Uint8List.fromList(utf8.encode(fingerprint)),
          );
          if (!accepted) {
            // dartssh2 closes the transport with SSHHostkeyError.
            throw SSHHostkeyError('Hostkey verification failed');
          }
        }
        final passwordOk = request.password == password ||
            (request.identities?.isNotEmpty ?? false);
        if (!passwordOk) {
          throw SSHAuthFailError('All authentication methods failed');
        }
        opened++;
        return _FakeSession(this);
      };
}

class _FakeSession implements SshSession {
  _FakeSession(this.server);
  final FakeSshServer server;
  bool _closed = false;

  @override
  String? get remoteVersion => 'SSH-2.0-FakeSSH_9.6';

  @override
  Future<SshCommandResult> run(String command) async {
    if (_closed) throw StateError('session closed');
    server.commands.add(command);
    for (final (match, reply) in server.rules) {
      if (match(command)) return reply(command);
    }
    return failed(127, 'unexpected command');
  }

  @override
  Future<void> upload(String remotePath, Uint8List bytes) async {
    if (_closed) throw StateError('session closed');
    server.uploads[remotePath] = bytes;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    server.closed++;
  }
}

const installMarker =
    'HH_COMPANION\t{"version":"0.1.204","release_dir":"/home/u/.local/share/huanhermes/releases/0.1.204","service_path":"/home/u/.config/systemd/user/huanhermes-host.service","config_path":"/home/u/.config/huanhermes/host.toml","activated":true,"service_started":false}';

const configMarker =
    'HH_COMPANION_CONFIG\t{"bridge_token":"bt-0123456789abcdef0123","mgmt_token":"mt-0123456789abcdef0123","bridge_port":19810,"mgmt_port":19820,"config_path":"/home/u/.config/huanhermes/host.toml"}';

const discoveryOutput = 'HH_DISCOVERY\t1\nHH_REMOTE\t/bin/bash\n'
    'HH_AGENT\tcodex\t/usr/local/bin/codex\tcodex-cli 0.50.0\n'
    'HH_AGENT\tclaude\t/home/u/.local/bin/claude\t2.0.1 (Claude Code)\n';

bool isDiscovery(String c) => c.contains('HH_DISCOVERY');
bool isDownload(String c) => c.contains('curl --fail');
bool isInstall(String c) => c.contains('companion_installer.py');
bool isConfigure(String c) => c.contains('companion_configurator.py');

/// A server where every step succeeds over HTTPS.
FakeSshServer happyServer() => FakeSshServer()
  ..on(isDiscovery, (_) => ok(discoveryOutput))
  ..on(isDownload, (_) => ok())
  ..on(isInstall, (c) => ok('HH_COMPANION_TRANSPORT\tX\n$installMarker\n'))
  ..on(isConfigure, (_) => ok('$configMarker\n'));
