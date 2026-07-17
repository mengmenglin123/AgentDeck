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

  @override
  String toString() =>
      'ConnectionConfig(host=$host, bridge=$bridgePort, mgmt=$mgmtPort, tls=$useTls, device=$deviceId)';
}
