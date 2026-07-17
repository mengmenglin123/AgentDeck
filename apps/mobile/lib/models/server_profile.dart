
import 'package:uuid/uuid.dart';

import 'connection_config.dart';

/// Named multi-server connection profile (P2-5).
class ServerProfile {
  ServerProfile({
    String? id,
    required this.name,
    required this.config,
    this.note,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final ConnectionConfig config;
  final String? note;
  final DateTime updatedAt;

  ServerProfile copyWith({
    String? id,
    String? name,
    ConnectionConfig? config,
    String? note,
    DateTime? updatedAt,
  }) {
    return ServerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      config: config ?? this.config,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'name': name,
        'note': note,
        'updatedAt': updatedAt.toIso8601String(),
        'config': config.toPublicJson(),
      };

  factory ServerProfile.fromJson(Map<String, dynamic> json, {String? bridgeToken, String? mgmtToken}) {
    final cfgMap = Map<String, dynamic>.from(json['config'] as Map? ?? json);
    if (bridgeToken != null) cfgMap['bridgeToken'] = bridgeToken;
    if (mgmtToken != null) cfgMap['mgmtToken'] = mgmtToken;
    return ServerProfile(
      id: (json['id'] as String?) ?? const Uuid().v4(),
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'Host',
      note: json['note'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      config: ConnectionConfig.fromJson(cfgMap),
    );
  }

  String get displayLabel {
    final h = config.host;
    final tls = config.useTls ? 'TLS' : 'plain';
    return '$name · $h · $tls';
  }
}
