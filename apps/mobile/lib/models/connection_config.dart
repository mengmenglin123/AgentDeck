import 'package:uuid/uuid.dart';

/// Host connection profile — mirrors packages/huan_protocol ConnectionConfig.
class ConnectionConfig {
  ConnectionConfig({
    this.host = '127.0.0.1',
    this.bridgePort = 9810,
    this.mgmtPort = 9820,
    this.bridgeToken = '',
    this.mgmtToken = '',
    this.useTls = false,
    this.platformName = 'huanhermes-app',
    String? deviceId,
  }) : deviceId = deviceId ?? const Uuid().v4().replaceAll('-', '').substring(0, 12);

  final String host;
  final int bridgePort;
  final int mgmtPort;
  final String bridgeToken;
  final String mgmtToken;
  final bool useTls;
  final String platformName;
  final String deviceId;

  String get bridgeWsUrl {
    final scheme = useTls ? 'wss' : 'ws';
    // Token is NOT embedded in logged URLs by callers; still kept for wire compat.
    return '$scheme://$host:$bridgePort/bridge/ws?token=$bridgeToken';
  }

  /// Safe URL for display/logs (token redacted).
  String get bridgeWsUrlRedacted {
    final scheme = useTls ? 'wss' : 'ws';
    return '$scheme://$host:$bridgePort/bridge/ws?token=***';
  }

  String get mgmtBaseUrl {
    final scheme = useTls ? 'https' : 'http';
    return '$scheme://$host:$mgmtPort/api/v1';
  }

  ConnectionConfig copyWith({
    String? host,
    int? bridgePort,
    int? mgmtPort,
    String? bridgeToken,
    String? mgmtToken,
    bool? useTls,
    String? platformName,
    String? deviceId,
  }) {
    return ConnectionConfig(
      host: host ?? this.host,
      bridgePort: bridgePort ?? this.bridgePort,
      mgmtPort: mgmtPort ?? this.mgmtPort,
      bridgeToken: bridgeToken ?? this.bridgeToken,
      mgmtToken: mgmtToken ?? this.mgmtToken,
      useTls: useTls ?? this.useTls,
      platformName: platformName ?? this.platformName,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  Map<String, dynamic> toJson({bool includeSecrets = true}) {
    return {
      'host': host,
      'bridgePort': bridgePort,
      'mgmtPort': mgmtPort,
      'useTls': useTls,
      'platformName': platformName,
      'deviceId': deviceId,
      if (includeSecrets) 'bridgeToken': bridgeToken,
      if (includeSecrets) 'mgmtToken': mgmtToken,
    };
  }

  /// Public prefs only (no tokens).
  Map<String, dynamic> toPublicJson() => toJson(includeSecrets: false);

  factory ConnectionConfig.fromJson(Map<String, dynamic> json) {
    return ConnectionConfig(
      host: (json['host'] as String?)?.trim().isNotEmpty == true
          ? (json['host'] as String).trim()
          : '127.0.0.1',
      bridgePort: _asInt(json['bridgePort'], 9810),
      mgmtPort: _asInt(json['mgmtPort'], 9820),
      bridgeToken: (json['bridgeToken'] as String?) ?? '',
      mgmtToken: (json['mgmtToken'] as String?) ?? '',
      useTls: json['useTls'] == true,
      platformName: (json['platformName'] as String?) ?? 'huanhermes-app',
      deviceId: json['deviceId'] as String?,
    );
  }

  static int _asInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  bool get hasTokens => bridgeToken.isNotEmpty && mgmtToken.isNotEmpty;

  String sessionKeyFor(String conversationId) => 'huan:$deviceId:$conversationId';

  /// Public pairing URI — host/ports/tls only (never embeds tokens).
  String toPairingUri({bool includeTokens = false}) {
    final q = <String, String>{
      'host': host,
      'bridge': '$bridgePort',
      'mgmt': '$mgmtPort',
      'tls': useTls ? '1' : '0',
    };
    if (includeTokens) {
      if (bridgeToken.isNotEmpty) q['bridge_token'] = bridgeToken;
      if (mgmtToken.isNotEmpty) q['mgmt_token'] = mgmtToken;
    }
    return Uri(scheme: 'huanhermes', host: 'connect', queryParameters: q).toString();
  }

  /// One-line public summary for clipboard / share cards.
  String toPublicSummary() =>
      'HuanHermes Host $host\nbridge=$bridgePort mgmt=$mgmtPort tls=$useTls\n${toPairingUri()}';

  /// Parse `huanhermes://connect?host=&bridge=&mgmt=&tls=` (no secrets expected).
  static ConnectionConfig? tryParsePairingUri(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    Uri uri;
    try {
      uri = Uri.parse(s);
    } catch (_) {
      return null;
    }
    final isScheme = uri.scheme == 'huanhermes';
    final looksQuery =
        s.contains('host=') && (s.contains('bridge=') || s.contains('mgmt='));
    if (!isScheme && !looksQuery) return null;
    if (uri.queryParameters.isEmpty && uri.fragment.isNotEmpty) {
      try {
        uri = Uri.parse('huanhermes://connect?${uri.fragment}');
      } catch (_) {}
    }
    final params = uri.queryParameters;
    final host = (params['host'] ?? params['h'] ?? '').trim();
    if (host.isEmpty) return null;
    final bridge =
        int.tryParse(params['bridge'] ?? params['bridge_port'] ?? '') ?? 9810;
    final mgmt =
        int.tryParse(params['mgmt'] ?? params['mgmt_port'] ?? '') ?? 9820;
    final tlsRaw = (params['tls'] ?? params['use_tls'] ?? '0').toLowerCase();
    final useTls = tlsRaw == '1' || tlsRaw == 'true' || tlsRaw == 'yes';
    return ConnectionConfig(
      host: host,
      bridgePort: bridge,
      mgmtPort: mgmt,
      useTls: useTls,
      bridgeToken: (params['bridge_token'] ?? '').trim(),
      mgmtToken: (params['mgmt_token'] ?? '').trim(),
    );
  }

  /// Merge pairing overlay; keep existing tokens unless overlay supplies them.
  ConnectionConfig mergePairing(ConnectionConfig overlay) {
    return copyWith(
      host: overlay.host,
      bridgePort: overlay.bridgePort,
      mgmtPort: overlay.mgmtPort,
      useTls: overlay.useTls,
      bridgeToken:
          overlay.bridgeToken.isNotEmpty ? overlay.bridgeToken : bridgeToken,
      mgmtToken: overlay.mgmtToken.isNotEmpty ? overlay.mgmtToken : mgmtToken,
    );
  }

  @override
  String toString() =>
      'ConnectionConfig(host=$host, bridge=$bridgePort, mgmt=$mgmtPort, tls=$useTls, device=$deviceId)';
}
