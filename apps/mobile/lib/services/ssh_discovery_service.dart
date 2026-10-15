import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/discovered_agent.dart';
import 'ssh_session.dart';

export 'ssh_session.dart'
    show
        SshSocketConnector,
        SshSessionOpener,
        SshSession,
        SshCommandResult,
        SshConnectRequest;

typedef SshHostKeyVerifier = Future<bool> Function(SshHostKey key);

class SshDiscoveryException implements Exception {
  const SshDiscoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SshDiscoveryService {
  SshDiscoveryService({
    SshSocketConnector? socketConnector,
    SshSessionOpener? openSession,
  }) : _openSession = openSession ?? dartSsh2Opener(socketConnector);

  final SshSessionOpener _openSession;

  static const command = r'''LC_ALL=C sh -s <<'HH_DISCOVERY'
probe() {
  name="$1"
  path="$(command -v "$name" 2>/dev/null || true)"
  if [ -z "$path" ]; then
    return 0
  fi
  version="$("$path" --version 2>&1 | head -n 1 | tr '\t\r\n' '   ')"
  printf 'HH_AGENT\t%s\t%s\t%s\n' "$name" "$path" "$version"
}
printf 'HH_DISCOVERY\t1\n'
printf 'HH_REMOTE\t%s\n' "$(printf '%s' "$SHELL")"
probe codex
probe claude
probe hermes
HH_DISCOVERY''';

  Future<SshDiscoveryResult> discover({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKeyPem,
    String? privateKeyPassphrase,
    required SshHostKeyVerifier verifyHostKey,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final cleanHost = host.trim();
    final cleanUser = username.trim();
    if (cleanHost.isEmpty || cleanUser.isEmpty) {
      throw const SshDiscoveryException('SSH 主机和用户名不能为空');
    }
    if ((password ?? '').isEmpty && (privateKeyPem ?? '').trim().isEmpty) {
      throw const SshDiscoveryException('请输入 SSH 密码或私钥');
    }

    final identities = parsePrivateKey(privateKeyPem, privateKeyPassphrase);
    SshSession? session;
    SshHostKey? hostKey;
    try {
      session = await _openSession(
        SshConnectRequest(
          host: cleanHost,
          port: port,
          username: cleanUser,
          identities: identities,
          password: password,
          timeout: timeout,
          verifyHostKey: (type, fingerprint) async {
            final key = SshHostKey(
              type: type,
              fingerprint: decodeFingerprint(fingerprint),
            );
            hostKey = key;
            return verifyHostKey(key);
          },
        ),
      );
      final result = await session.run(command).timeout(timeout);
      final key = hostKey;
      if (key == null) {
        throw const SshDiscoveryException('SSH 主机未提供可验证的 Host Key');
      }
      final parsed = parseDiscoveryOutput(
        utf8.decode(result.stdout, allowMalformed: true),
      );
      return SshDiscoveryResult(
        host: cleanHost,
        remoteVersion: session.remoteVersion ?? 'unknown SSH server',
        agents: parsed,
        hostKey: key,
        stderr: utf8.decode(result.stderr, allowMalformed: true).trim(),
        exitCode: result.exitCode,
      );
    } on SshDiscoveryException {
      rethrow;
    } on SSHHostkeyError {
      throw const SshDiscoveryException('SSH 主机指纹未被确认，已中止连接');
    } on SSHAuthFailError catch (error) {
      throw SshDiscoveryException('SSH 认证失败：$error');
    } on TimeoutException {
      throw const SshDiscoveryException('SSH 探测超时');
    } catch (error) {
      throw SshDiscoveryException('SSH 探测失败：$error');
    } finally {
      session?.close();
    }
  }

  static List<SSHKeyPair>? parsePrivateKey(
    String? pem,
    String? passphrase,
  ) {
    final text = pem?.trim() ?? '';
    if (text.isEmpty) return null;
    try {
      return SSHKeyPair.fromPem(text, passphrase);
    } catch (error) {
      throw SshDiscoveryException('SSH 私钥解析失败：$error');
    }
  }

  static String decodeFingerprint(Uint8List bytes) {
    final decoded = utf8.decode(bytes, allowMalformed: true).trim();
    return decoded.isEmpty
        ? base64Url.encode(bytes).replaceAll('=', '')
        : decoded;
  }

  static List<DiscoveredAgent> parseDiscoveryOutput(String output) {
    final agents = <DiscoveredAgent>[];
    final seen = <String>{};
    for (final line in const LineSplitter().convert(output)) {
      final fields = line.split('\t');
      if (fields.length < 4 || fields.first != 'HH_AGENT') continue;
      final command = fields[1].trim();
      final path = fields[2].trim();
      if (path.isEmpty || !seen.add(command)) continue;
      try {
        agents.add(
          DiscoveredAgent.fromProbe(
            command: command,
            path: path,
            version: fields.sublist(3).join('\t'),
          ),
        );
      } on FormatException {
        // Ignore unknown executables; discovery is forward-compatible.
      }
    }
    return agents;
  }
}
