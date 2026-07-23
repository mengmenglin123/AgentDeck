import 'host_capabilities.dart';

class SessionInfo {
  SessionInfo({
    required this.id,
    required this.sessionKey,
    required this.project,
    this.title,
    this.lastUser,
    this.updatedAt,
    this.createdAt,
    this.running = false,
    this.mode,
    this.model,
    this.workdir,
    this.platform,
    this.agentType,
    this.live = false,
  });

  final String id;
  final String sessionKey;
  final String project;
  final String? title;
  final String? lastUser;
  final double? updatedAt;
  final double? createdAt;
  final bool running;
  final String? mode;
  final String? model;
  final String? workdir;
  final String? platform;
  final String? agentType;
  final bool live;

  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final last = lastUser?.trim();
    if (last != null && last.isNotEmpty) {
      return last.length > 40 ? '${last.substring(0, 40)}…' : last;
    }
    // prefer short session_key tail
    final sk = sessionKey;
    if (sk.contains(':')) {
      final parts = sk.split(':');
      return parts.last.length > 16 ? parts.last.substring(0, 16) : parts.last;
    }
    return id;
  }

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    final sk = (json['session_key'] ?? json['id'] ?? '').toString();
    final id = (json['id'] ?? sk).toString();
    final title =
        (json['title'] ?? json['name'] ?? json['chat_name'])?.toString();
    // last message can be string or object
    String? lastUser = json['last_user']?.toString();
    final lm = json['last_message'];
    if (lastUser == null || lastUser.isEmpty) {
      if (lm is String) {
        lastUser = lm;
      } else if (lm is Map && lm['content'] != null) {
        lastUser = lm['content'].toString();
      }
    }
    return SessionInfo(
      id: id,
      sessionKey: sk.isEmpty ? id : sk,
      project: (json['project'] ?? '').toString(),
      title: title,
      lastUser: lastUser,
      updatedAt: _asDouble(json['updated_at'] ?? json['updatedAt']),
      createdAt: _asDouble(
        json['created_at'] ?? json['createdAt'] ?? json['created'],
      ),
      running: json['running'] == true ||
          json['live'] == true ||
          json['active'] == true,
      mode: json['mode']?.toString(),
      model: json['model']?.toString(),
      workdir: json['workdir']?.toString() ?? json['work_dir']?.toString(),
      platform: json['platform']?.toString(),
      agentType: (json['agent_type'] ?? json['agentType'])?.toString(),
      live: json['live'] == true || json['active'] == true,
    );
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) {
      final asNum = double.tryParse(v);
      if (asNum != null) return asNum;
      // ISO timestamp
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.millisecondsSinceEpoch / 1000.0;
    }
    return null;
  }
}

class ProjectInfo {
  ProjectInfo({
    required this.name,
    required this.agentType,
    this.sessionsCount = 0,
    this.note,
    this.platforms = const [],
    this.capabilities = const [],
    this.models = const [],
    this.channels = const [],
  });

  final String name;
  final String agentType;
  final int sessionsCount;
  final String? note;
  final List<String> platforms;
  final List<String> capabilities;
  final List<String> models;
  final List<String> channels;

  CapabilitySet get capabilitySet => CapabilitySet.from(capabilities);

  bool hasCapability(String c) => capabilitySet.supports(c);

  factory ProjectInfo.fromJson(Map<String, dynamic> json) {
    final plats = <String>[];
    final raw = json['platforms'];
    if (raw is List) {
      for (final p in raw) {
        if (p is String) {
          plats.add(p);
        } else if (p is Map && p['type'] != null) {
          plats.add(p['type'].toString());
        }
      }
    }
    final caps = <String>[];
    final cr = json['capabilities'];
    if (cr is List) {
      for (final c in cr) {
        if (c != null) caps.add(c.toString());
      }
    }
    final models = _strings(json['models'] ?? json['model_catalog']);
    final channels = _strings(json['channels'] ?? json['providers']);
    return ProjectInfo(
      name: (json['name'] ?? '').toString(),
      agentType: (json['agent_type'] ?? json['agentType'] ?? '').toString(),
      sessionsCount: (json['sessions_count'] is num)
          ? (json['sessions_count'] as num).toInt()
          : int.tryParse('${json['sessions_count'] ?? 0}') ?? 0,
      note: json['note']?.toString(),
      platforms: plats,
      capabilities: caps,
      models: models,
      channels: channels,
    );
  }

  static List<String> _strings(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((item) {
          if (item is Map) {
            return (item['id'] ?? item['name'] ?? item['model'] ?? '')
                .toString();
          }
          return item?.toString() ?? '';
        })
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
  }
}
