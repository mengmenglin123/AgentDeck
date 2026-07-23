import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/discovered_agent.dart';
import 'ssh_discovery_service.dart';

typedef CompanionAssetLoader = Future<Uint8List> Function(String assetPath);

class SshBootstrapException implements Exception {
  const SshBootstrapException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CompanionInstallResult {
  const CompanionInstallResult({
    required this.version,
    required this.releaseDirectory,
    required this.servicePath,
    required this.configPath,
    required this.activated,
    required this.serviceStarted,
  });

  final String version;
  final String releaseDirectory;
  final String servicePath;
  final String configPath;
  final bool activated;
  final bool serviceStarted;
}

class CompanionHostConfig {
  const CompanionHostConfig({
    required this.bridgeToken,
    required this.mgmtToken,
    required this.bridgePort,
    required this.mgmtPort,
    required this.configPath,
  });

  final String bridgeToken;
  final String mgmtToken;
  final int bridgePort;
  final int mgmtPort;
  final String configPath;
}

class SshBootstrapService {
  SshBootstrapService({
    SshSocketConnector? socketConnector,
    CompanionAssetLoader? assetLoader,
    Uuid? uuid,
  })  : _socketConnector = socketConnector ??
            ((host, port, timeout) => SSHSocket.connect(
                  host,
                  port,
                  timeout: timeout,
                )),
        _assetLoader = assetLoader ?? _loadAsset,
        _uuid = uuid ?? const Uuid();

  static const releaseVersion = '0.1.202';
  static const assetPath =
      'assets/companion/huanhermes-host-0.1.202.tar.gz';
  static const archiveSha256 =
      'ba3cc5a67da38ae13266baa10c09c21f93d852f82e2eeecc023e8f832dca96d9';

  final SshSocketConnector _socketConnector;
  final CompanionAssetLoader _assetLoader;
  final Uuid _uuid;

  Future<CompanionInstallResult> install({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKeyPem,
    String? privateKeyPassphrase,
    required SshHostKeyVerifier verifyHostKey,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final cleanHost = host.trim();
    final cleanUser = username.trim();
    if (cleanHost.isEmpty || cleanUser.isEmpty) {
      throw const SshBootstrapException('SSH 主机和用户名不能为空');
    }
    if ((password ?? '').isEmpty && (privateKeyPem ?? '').trim().isEmpty) {
      throw const SshBootstrapException('请输入 SSH 密码或私钥');
    }
    final archive = await _assetLoader(assetPath);
    if (archive.isEmpty) {
      throw const SshBootstrapException('Companion 安装包为空');
    }
    final suffix = _uuid.v4().replaceAll('-', '');
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(suffix)) {
      throw const SshBootstrapException('无法生成安全的远端临时路径');
    }
    final remoteArchive = '/tmp/huanhermes-companion-$suffix.tar.gz';

    SSHSocket? socket;
    SSHClient? client;
    SshHostKey? hostKey;
    try {
      socket = await _socketConnector(cleanHost, port, timeout).timeout(timeout);
      client = SSHClient(
        socket,
        username: cleanUser,
        identities: SshDiscoveryService.parsePrivateKey(
          privateKeyPem,
          privateKeyPassphrase,
        ),
        onPasswordRequest: () async => password,
        onVerifyHostKey: (type, fingerprint) async {
          final key = SshHostKey(
            type: type,
            fingerprint: SshDiscoveryService.decodeFingerprint(fingerprint),
          );
          hostKey = key;
          return verifyHostKey(key);
        },
        handshakeTimeout: timeout,
        authTimeout: timeout,
      );
      final sftp = await client.sftp();
      final file = await sftp.open(
        remoteArchive,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      try {
        await file.writeBytes(archive);
      } finally {
        await file.close();
      }
      final command = buildInstallCommand(remoteArchive);
      final execution = await client.runWithResult(command).timeout(timeout);
      final key = hostKey;
      if (key == null) {
        throw const SshBootstrapException('SSH 主机未提供可验证的 Host Key');
      }
      final stdout = utf8.decode(execution.stdout, allowMalformed: true);
      final stderr = utf8.decode(execution.stderr, allowMalformed: true).trim();
      if (execution.exitCode != 0) {
        throw SshBootstrapException(
          stderr.isEmpty ? 'Companion 安装失败' : 'Companion 安装失败：$stderr',
        );
      }
      return parseInstallOutput(stdout);
    } on SshBootstrapException {
      rethrow;
    } on SSHAuthFailError catch (error) {
      throw SshBootstrapException('SSH 认证失败：$error');
    } on TimeoutException {
      throw const SshBootstrapException('Companion 安装超时');
    } catch (error) {
      throw SshBootstrapException('Companion 安装失败：$error');
    } finally {
      client?.close();
      socket?.close();
    }
  }

  static String buildInstallCommand(String remoteArchive) {
    if (!RegExp(r'^/tmp/huanhermes-companion-[a-fA-F0-9]{32}\.tar\.gz$')
        .hasMatch(remoteArchive)) {
      throw const SshBootstrapException('远端安装包路径无效');
    }
    return '''set -eu
umask 077
archive='$remoteArchive'
work="\${archive%.tar.gz}"
trap 'rm -rf -- "\$work" "\$archive"' EXIT HUP INT TERM
command -v python3 >/dev/null 2>&1
command -v tar >/dev/null 2>&1
command -v sha256sum >/dev/null 2>&1
printf '%s  %s\n' '$archiveSha256' "\$archive" | sha256sum -c -
rm -rf -- "\$work"
mkdir -p -- "\$work"
tar -xzf "\$archive" -C "\$work" --strip-components=1
python3 "\$work/server/companion_installer.py" install --source "\$work" --prefix "\$HOME/.local/share/huanhermes" --version '$releaseVersion'
''';
  }

  Future<CompanionHostConfig> configure({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKeyPem,
    String? privateKeyPassphrase,
    required SshHostKeyVerifier verifyHostKey,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (host.trim().isEmpty || username.trim().isEmpty) {
      throw const SshBootstrapException('SSH 主机和用户名不能为空');
    }
    SSHSocket? socket;
    SSHClient? client;
    SshHostKey? hostKey;
    try {
      socket = await _socketConnector(host.trim(), port, timeout).timeout(timeout);
      client = SSHClient(
        socket,
        username: username.trim(),
        identities: SshDiscoveryService.parsePrivateKey(privateKeyPem, privateKeyPassphrase),
        onPasswordRequest: () async => password,
        onVerifyHostKey: (type, fingerprint) async {
          final key = SshHostKey(
            type: type,
            fingerprint: SshDiscoveryService.decodeFingerprint(fingerprint),
          );
          hostKey = key;
          return verifyHostKey(key);
        },
        handshakeTimeout: timeout,
        authTimeout: timeout,
      );
      final execution = await client.runWithResult(
        r'''set -eu
python3 "$HOME/.local/share/huanhermes/current/server/companion_configurator.py" --prefix "$HOME/.local/share/huanhermes" --workspace "$HOME"''',
      ).timeout(timeout);
      if (hostKey == null) {
        throw const SshBootstrapException('SSH 主机未提供可验证的 Host Key');
      }
      if (execution.exitCode != 0) {
        final error = utf8.decode(execution.stderr, allowMalformed: true).trim();
        throw SshBootstrapException(error.isEmpty ? 'Host 配置初始化失败' : error);
      }
      return parseConfigOutput(utf8.decode(execution.stdout, allowMalformed: true));
    } on SshBootstrapException {
      rethrow;
    } on SSHAuthFailError catch (error) {
      throw SshBootstrapException('SSH 认证失败：$error');
    } on TimeoutException {
      throw const SshBootstrapException('Host 配置初始化超时');
    } catch (error) {
      throw SshBootstrapException('Host 配置初始化失败：$error');
    } finally {
      client?.close();
      socket?.close();
    }
  }

  static CompanionHostConfig parseConfigOutput(String output) {
    for (final line in const LineSplitter().convert(output)) {
      if (!line.startsWith('HH_COMPANION_CONFIG\t')) continue;
      try {
        final value = jsonDecode(line.substring('HH_COMPANION_CONFIG\t'.length));
        if (value is Map<String, dynamic> &&
            value['bridge_token'] is String &&
            value['mgmt_token'] is String &&
            value['bridge_port'] is int &&
            value['mgmt_port'] is int &&
            value['config_path'] is String) {
          return CompanionHostConfig(
            bridgeToken: value['bridge_token'] as String,
            mgmtToken: value['mgmt_token'] as String,
            bridgePort: value['bridge_port'] as int,
            mgmtPort: value['mgmt_port'] as int,
            configPath: value['config_path'] as String,
          );
        }
      } on FormatException {
        continue;
      }
    }
    throw const SshBootstrapException('服务器未返回有效的 Host 配置');
  }

  static CompanionInstallResult parseInstallOutput(String output) {
    for (final line in const LineSplitter().convert(output)) {
      if (!line.startsWith('HH_COMPANION\t')) continue;
      dynamic value;
      try {
        value = jsonDecode(line.substring('HH_COMPANION\t'.length));
      } on FormatException {
        continue;
      }
      if (value is! Map<String, dynamic>) break;
      final version = value['version'];
      final releaseDirectory = value['release_dir'];
      final servicePath = value['service_path'];
      final configPath = value['config_path'];
      final activated = value['activated'];
      final serviceStarted = value['service_started'];
      if (version is String &&
          releaseDirectory is String &&
          servicePath is String &&
          configPath is String &&
          activated is bool &&
          serviceStarted is bool) {
        return CompanionInstallResult(
          version: version,
          releaseDirectory: releaseDirectory,
          servicePath: servicePath,
          configPath: configPath,
          activated: activated,
          serviceStarted: serviceStarted,
        );
      }
    }
    throw const SshBootstrapException('服务器未返回有效的 Companion 安装结果');
  }

  static Future<Uint8List> _loadAsset(String path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
