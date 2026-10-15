// SSH discovery + companion bootstrap services over a fake SSH layer.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/models/discovered_agent.dart';
import 'package:huanhermes_app/services/ssh_bootstrap_service.dart';
import 'package:huanhermes_app/services/ssh_discovery_service.dart';
import 'package:huanhermes_app/services/ssh_session.dart';
import 'dart:async';

import 'ssh_fakes.dart';

final _archive = Uint8List.fromList(List<int>.generate(64, (i) => i));
final _tmpPath = RegExp(r'^/tmp/huanhermes-companion-[a-f0-9]{32}\.tar\.gz$');

Future<bool> _trust(SshHostKey _) async => true;

SshBootstrapService _bootstrap(FakeSshServer s, {List<String>? loaded}) =>
    SshBootstrapService(
      openSession: s.opener,
      assetLoader: (path) async {
        loaded?.add(path);
        return _archive;
      },
    );

void main() {
  group('SshDiscoveryService', () {
    test('discovers agents, reports the verified host key, closes', () async {
      final server = happyServer();
      SshHostKey? seen;
      final r = await SshDiscoveryService(openSession: server.opener).discover(
        host: ' 10.0.0.5 ',
        port: 2222,
        username: ' u ',
        password: 'pw',
        verifyHostKey: (k) async {
          seen = k;
          return true;
        },
      );
      expect(r.host, '10.0.0.5');
      expect(server.requests.single.port, 2222);
      expect(server.requests.single.username, 'u');
      expect(r.agents.map((a) => a.kind), [
        DiscoveredAgentKind.codex,
        DiscoveredAgentKind.claudeCode,
      ]);
      expect(r.hostKey.fingerprint, server.fingerprint);
      expect(seen!.type, 'ssh-ed25519');
      expect(r.remoteVersion, contains('FakeSSH'));
      expect(server.closed, server.opened);
    });

    test('rejected host key aborts before any command', () async {
      final server = happyServer();
      await expectLater(
        SshDiscoveryService(openSession: server.opener).discover(
          host: 'h',
          port: 22,
          username: 'u',
          password: 'pw',
          verifyHostKey: (_) async => false,
        ),
        throwsA(isA<SshDiscoveryException>()
            .having((e) => e.message, 'message', contains('指纹未被确认'))),
      );
      expect(server.commands, isEmpty);
    });

    test('wrong password is reported as auth failure', () async {
      final server = happyServer();
      await expectLater(
        SshDiscoveryService(openSession: server.opener).discover(
          host: 'h',
          port: 22,
          username: 'u',
          password: 'nope',
          verifyHostKey: _trust,
        ),
        throwsA(isA<SshDiscoveryException>()
            .having((e) => e.message, 'message', contains('认证失败'))),
      );
    });

    test('missing credentials fail fast without connecting', () async {
      final server = happyServer();
      await expectLater(
        SshDiscoveryService(openSession: server.opener).discover(
          host: 'h',
          port: 22,
          username: 'u',
          verifyHostKey: _trust,
        ),
        throwsA(isA<SshDiscoveryException>()),
      );
      expect(server.requests, isEmpty);
    });

    test('garbage private key is a parse error, not a crash', () async {
      final server = happyServer();
      await expectLater(
        SshDiscoveryService(openSession: server.opener).discover(
          host: 'h',
          port: 22,
          username: 'u',
          privateKeyPem: 'not a key',
          verifyHostKey: _trust,
        ),
        throwsA(isA<SshDiscoveryException>()
            .having((e) => e.message, 'message', contains('私钥解析失败'))),
      );
      expect(server.requests, isEmpty);
    });
  });

  group('SshBootstrapService.install', () {
    test('HTTPS path: pinned download, no SFTP upload, parsed result',
        () async {
      final server = happyServer();
      final loaded = <String>[];
      final r = await _bootstrap(server, loaded: loaded).install(
        host: 'h',
        port: 22,
        username: 'u',
        password: 'pw',
        verifyHostKey: _trust,
      );
      expect(r.version, '0.1.204');
      expect(r.activated, isTrue);
      expect(r.serviceStarted, isFalse);
      expect(server.commands, hasLength(2));
      expect(server.commands[0], contains(SshBootstrapService.releaseUrl));
      expect(server.commands[1], contains('HH_COMPANION_TRANSPORT\\tHTTPS'));
      expect(server.commands[1], contains(SshBootstrapService.archiveSha256));
      expect(server.uploads, isEmpty);
      expect(loaded, isEmpty, reason: 'bundled asset only for SFTP fallback');
      // Both commands use the same generated temp path.
      final path = RegExp(r"archive='([^']+)'")
          .firstMatch(server.commands[0])!
          .group(1)!;
      expect(path, matches(_tmpPath));
      expect(server.commands[1], contains("archive='$path'"));
      expect(server.closed, 1);
    });

    test('no curl/wget (exit 42) falls back to SFTP upload of the asset',
        () async {
      final server = FakeSshServer()
        ..on(isDownload, (_) => failed(42))
        ..on(isInstall, (_) => ok('$installMarker\n'));
      final loaded = <String>[];
      final r = await _bootstrap(server, loaded: loaded).install(
        host: 'h',
        port: 22,
        username: 'u',
        password: 'pw',
        verifyHostKey: _trust,
      );
      expect(r.configPath, endsWith('host.toml'));
      expect(loaded, [SshBootstrapService.assetPath]);
      expect(server.uploads.keys.single, matches(_tmpPath));
      expect(server.uploads.values.single, _archive);
      expect(server.commands.last, contains('HH_COMPANION_TRANSPORT\\tSFTP'));
      expect(server.commands.last,
          contains("archive='${server.uploads.keys.single}'"));
    });

    test('empty bundled archive is refused before upload', () async {
      final server = FakeSshServer()..on(isDownload, (_) => failed(1));
      await expectLater(
        SshBootstrapService(
          openSession: server.opener,
          assetLoader: (_) async => Uint8List(0),
        ).install(
          host: 'h',
          port: 22,
          username: 'u',
          password: 'pw',
          verifyHostKey: _trust,
        ),
        throwsA(isA<SshBootstrapException>()
            .having((e) => e.message, 'message', contains('安装包为空'))),
      );
      expect(server.uploads, isEmpty);
    });

    test('installer failure surfaces stderr (checksum mismatch)', () async {
      final server = FakeSshServer()
        ..on(isDownload, (_) => ok())
        ..on(
            isInstall,
            (_) => failed(
                1, 'sha256sum: WARNING: 1 computed checksum did NOT match'));
      await expectLater(
        _bootstrap(server).install(
          host: 'h',
          port: 22,
          username: 'u',
          password: 'pw',
          verifyHostKey: _trust,
        ),
        throwsA(isA<SshBootstrapException>()
            .having((e) => e.message, 'message', contains('did NOT match'))),
      );
      expect(server.closed, 1);
    });

    test('installer success without a typed marker is an error', () async {
      final server = FakeSshServer()
        ..on(isDownload, (_) => ok())
        ..on(isInstall, (_) => ok('done\n'));
      await expectLater(
        _bootstrap(server).install(
          host: 'h',
          port: 22,
          username: 'u',
          password: 'pw',
          verifyHostKey: _trust,
        ),
        throwsA(isA<SshBootstrapException>()),
      );
    });

    test('rejected host key: nothing runs on the server', () async {
      final server = happyServer();
      await expectLater(
        _bootstrap(server).install(
          host: 'h',
          port: 22,
          username: 'u',
          password: 'pw',
          verifyHostKey: (_) async => false,
        ),
        throwsA(isA<SshBootstrapException>()
            .having((e) => e.message, 'message', contains('指纹未被确认'))),
      );
      expect(server.commands, isEmpty);
      expect(server.uploads, isEmpty);
    });

    test('server that never presents a host key is refused before install',
        () async {
      final server = happyServer()..presentHostKey = false;
      await expectLater(
        _bootstrap(server).install(
          host: 'h',
          port: 22,
          username: 'u',
          password: 'pw',
          verifyHostKey: _trust,
        ),
        throwsA(isA<SshBootstrapException>()
            .having((e) => e.message, 'message', contains('Host Key'))),
      );
      expect(server.commands.where(isInstall), isEmpty);
      expect(server.uploads, isEmpty);
    });

    test('auth failure', () async {
      final server = happyServer();
      await expectLater(
        _bootstrap(server).install(
          host: 'h',
          port: 22,
          username: 'u',
          password: 'bad',
          verifyHostKey: _trust,
        ),
        throwsA(isA<SshBootstrapException>()
            .having((e) => e.message, 'message', contains('认证失败'))),
      );
    });
  });

  group('SshBootstrapService.configure', () {
    test('parses generated tokens and ports', () async {
      final server = happyServer();
      final c = await _bootstrap(server).configure(
        host: 'h',
        port: 22,
        username: 'u',
        password: 'pw',
        verifyHostKey: _trust,
      );
      expect(c.bridgeToken, startsWith('bt-'));
      expect(c.mgmtToken, startsWith('mt-'));
      expect(c.bridgePort, 19810);
      expect(c.mgmtPort, 19820);
      expect(server.commands.single, SshBootstrapService.configureCommand);
      expect(server.closed, 1);
    });

    test('configurator stderr is surfaced', () async {
      final server = FakeSshServer()
        ..on(isConfigure, (_) => failed(2, 'companion not installed'));
      await expectLater(
        _bootstrap(server).configure(
          host: 'h',
          port: 22,
          username: 'u',
          password: 'pw',
          verifyHostKey: _trust,
        ),
        throwsA(isA<SshBootstrapException>().having(
            (e) => e.message, 'message', contains('companion not installed'))),
      );
    });
  });

  group('PausableDeadline', () {
    testWidgets('times out on running time only', (tester) async {
      final d = PausableDeadline(const Duration(seconds: 20),
          now: () => tester.binding.clock.now());
      final work = Completer<int>();
      Object? error;
      int? value;
      d.guard(work.future).then<void>((v) {
        value = v;
      }, onError: (Object e) {
        error = e;
      });
      await tester.pump(const Duration(seconds: 5));
      d.pause(); // user reading the fingerprint dialog
      await tester.pump(const Duration(minutes: 3));
      expect(error, isNull);
      d.resume();
      await tester.pump(const Duration(seconds: 14));
      expect(error, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(error, isA<TimeoutException>());
      expect(value, isNull);
    });

    testWidgets('completes with the work result and cancels its timer',
        (tester) async {
      final d = PausableDeadline(const Duration(seconds: 1));
      final r = d.guard(Future<int>.value(7));
      await tester.pump();
      expect(await r, 7);
      await tester.pump(const Duration(seconds: 5)); // no pending-timer error
    });
  });
}
