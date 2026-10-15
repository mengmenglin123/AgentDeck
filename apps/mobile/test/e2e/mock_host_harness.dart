// Starts the real Python Mock Host (server/mock-host/mock_host.py) on free
// loopback ports so app code can be exercised over real HTTP + WebSocket.
//
// Run with: NO_PROXY=127.0.0.1,localhost flutter test test/e2e
// Tests skip themselves when python3 is not available.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:huanhermes_app/models/connection_config.dart';

class MockHost {
  MockHost._(this._proc, this.bridgePort, this.mgmtPort, this.log);

  static const bridgeToken = 'e2e-bridge-token-0123456789';
  static const mgmtToken = 'e2e-mgmt-token-0123456789';

  final Process _proc;
  final int bridgePort;
  final int mgmtPort;
  final StringBuffer log;

  ConnectionConfig config({String deviceId = 'e2edevice001'}) =>
      ConnectionConfig(
        host: '127.0.0.1',
        bridgePort: bridgePort,
        mgmtPort: mgmtPort,
        bridgeToken: bridgeToken,
        mgmtToken: mgmtToken,
        deviceId: deviceId,
      );

  static Future<bool> pythonAvailable() async {
    try {
      final r = await Process.run('python3', ['--version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static String _scriptPath() {
    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      final f = File('${dir.path}/server/mock-host/mock_host.py');
      if (f.existsSync()) return f.path;
      dir = dir.parent;
    }
    throw StateError('mock_host.py not found from ${Directory.current.path}');
  }

  static Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  static Future<MockHost> start({Map<String, String> extraEnv = const {}}) async {
    final script = _scriptPath();
    final b = await _freePort();
    var m = await _freePort();
    while (m == b) {
      m = await _freePort();
    }
    final env = Map<String, String>.from(Platform.environment)
      ..addAll({
        'HUAN_BRIDGE_PORT': '$b',
        'HUAN_MGMT_PORT': '$m',
        'HUAN_BRIDGE_TOKEN': bridgeToken,
        'HUAN_MGMT_TOKEN': mgmtToken,
        'NO_PROXY': '127.0.0.1,localhost',
        'no_proxy': '127.0.0.1,localhost',
        'PYTHONUNBUFFERED': '1',
      })
      ..addAll(extraEnv);
    final proc = await Process.start('python3', [script],
        environment: env, workingDirectory: File(script).parent.path);
    final log = StringBuffer();
    proc.stdout.transform(utf8.decoder).listen(log.write);
    proc.stderr.transform(utf8.decoder).listen(log.write);
    final host = MockHost._(proc, b, m, log);
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final c = HttpClient()..findProxy = (_) => 'DIRECT';
        final req = await c.getUrl(Uri.parse('http://127.0.0.1:$m/api/v1/status'));
        req.headers.set('Authorization', 'Bearer $mgmtToken');
        final res = await req.close();
        await res.drain<void>();
        c.close(force: true);
        if (res.statusCode == 200) return host;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    proc.kill();
    throw StateError('mock host did not start:\n$log');
  }

  Future<void> stop() async {
    _proc.kill();
    await _proc.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
      _proc.kill(ProcessSignal.sigkill);
      return -1;
    });
  }
}

/// Polls [cond] on the real event loop until it is true or [timeout] passes.
Future<void> waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 10), String? reason}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('waitFor timed out${reason == null ? '' : ': $reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}
