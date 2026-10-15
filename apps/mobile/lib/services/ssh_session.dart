import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Result of one remote command.
class SshCommandResult {
  const SshCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final List<int> stdout;
  final List<int> stderr;
  final int? exitCode;
}

/// Raw host-key callback: [fingerprint] is the UTF-8 `SHA256:<base64>` text
/// dartssh2 hands to `onVerifyHostKey`.
typedef SshRawHostKeyVerifier = Future<bool> Function(
  String type,
  Uint8List fingerprint,
);

typedef SshSocketConnector = Future<SSHSocket> Function(
  String host,
  int port,
  Duration timeout,
);

class SshConnectRequest {
  const SshConnectRequest({
    required this.host,
    required this.port,
    required this.username,
    required this.identities,
    required this.password,
    required this.verifyHostKey,
    required this.timeout,
  });

  final String host;
  final int port;
  final String username;
  final List<SSHKeyPair>? identities;
  final String? password;
  final SshRawHostKeyVerifier verifyHostKey;
  final Duration timeout;
}

/// The small slice of an SSH connection the discovery / bootstrap flows use.
/// Production wraps dartssh2; tests inject a fake (no network, no sshd).
abstract class SshSession {
  String? get remoteVersion;
  Future<SshCommandResult> run(String command);
  Future<void> upload(String remotePath, Uint8List bytes);
  void close();
}

typedef SshSessionOpener = Future<SshSession> Function(
  SshConnectRequest request,
);

SshSessionOpener dartSsh2Opener([SshSocketConnector? connector]) {
  final connect = connector ??
      ((host, port, timeout) =>
          SSHSocket.connect(host, port, timeout: timeout));
  return (request) async {
    final socket = await connect(request.host, request.port, request.timeout)
        .timeout(request.timeout);
    // The connect deadline must not count the time the user spends
    // comparing the host-key fingerprint in a dialog, so dartssh2's own
    // handshake timer is off and this deadline pauses during verification.
    final deadline = PausableDeadline(request.timeout);
    var hostKeyRejected = false;
    final client = SSHClient(
      socket,
      username: request.username,
      identities: request.identities,
      onPasswordRequest: () async => request.password,
      onVerifyHostKey: (type, fingerprint) async {
        deadline.pause();
        try {
          final ok = await request.verifyHostKey(type, fingerprint);
          if (!ok) hostKeyRejected = true;
          return ok;
        } finally {
          deadline.resume();
        }
      },
      authTimeout: request.timeout,
    );
    try {
      await deadline.guard(client.authenticated);
    } catch (_) {
      client.close();
      socket.close();
      // dartssh2 reports a rejected key as SSHAuthAbortError("Connection
      // closed before authentication"); surface it as a host-key error.
      if (hostKeyRejected) {
        throw SSHHostkeyError('Hostkey verification failed');
      }
      rethrow;
    }
    return _DartSsh2Session(socket, client);
  };
}

/// A timeout whose clock can be paused (e.g. while a dialog waits on the
/// user). [guard] fails with [TimeoutException] once the *running* time
/// exceeds [budget].
class PausableDeadline {
  PausableDeadline(this.budget, {DateTime Function()? now})
      : _remaining = budget,
        _now = now ?? DateTime.now;

  final Duration budget;
  final DateTime Function() _now;
  Duration _remaining;
  DateTime? _runningSince;
  Timer? _timer;
  Completer<void>? _expired;
  int _pauses = 0;

  bool get isPaused => _pauses > 0;

  void pause() {
    _pauses++;
    if (_pauses != 1) return;
    final since = _runningSince;
    if (since != null) {
      _remaining -= _now().difference(since);
      _runningSince = null;
    }
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (_pauses == 0) return;
    _pauses--;
    if (_pauses == 0 && _expired != null) _arm();
  }

  void _arm() {
    _timer?.cancel();
    if (_remaining <= Duration.zero) {
      _fire();
      return;
    }
    _runningSince = _now();
    _timer = Timer(_remaining, _fire);
  }

  void _fire() {
    final e = _expired;
    if (e != null && !e.isCompleted) {
      e.completeError(TimeoutException('deadline exceeded', budget));
    }
  }

  Future<T> guard<T>(Future<T> work) async {
    _expired = Completer<void>();
    if (!isPaused) _arm();
    try {
      final r = await Future.any<Object?>([
        work,
        _expired!.future,
      ]);
      return r as T;
    } finally {
      _timer?.cancel();
      _timer = null;
      _runningSince = null;
    }
  }
}

class _DartSsh2Session implements SshSession {
  _DartSsh2Session(this._socket, this._client);

  final SSHSocket _socket;
  final SSHClient _client;

  @override
  String? get remoteVersion => _client.remoteVersion;

  @override
  Future<SshCommandResult> run(String command) async {
    final r = await _client.runWithResult(command);
    return SshCommandResult(
      stdout: r.stdout,
      stderr: r.stderr,
      exitCode: r.exitCode,
    );
  }

  @override
  Future<void> upload(String remotePath, Uint8List bytes) async {
    final sftp = await _client.sftp();
    final file = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      await file.writeBytes(bytes);
    } finally {
      await file.close();
      try {
        await sftp.close();
      } catch (_) {}
    }
  }

  @override
  void close() {
    _client.close();
    _socket.close();
  }
}
