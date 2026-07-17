class SessionInfo {
  SessionInfo({
    required this.id,
    required this.sessionKey,
    required this.project,
    this.title,
    this.lastUser,
    this.updatedAt,
  });

  final String id;
  final String sessionKey;
  final String project;
  final String? title;
  final String? lastUser;
  final double? updatedAt;

  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final last = lastUser?.trim();
    if (last != null && last.isNotEmpty) {
      return last.length > 40 ? '${last.substring(0, 40)}…' : last;
    }
    return id;
  }

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['session_key'] ?? '').toString();
    return SessionInfo(
      id: id,
      sessionKey: (json['session_key'] ?? id).toString(),
      project: (json['project'] ?? 'claude-code').toString(),
      title: json['title']?.toString(),
      lastUser: json['last_user']?.toString(),
      updatedAt: _asDouble(json['updated_at']),
    );
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

class ProjectInfo {
  ProjectInfo({
    required this.name,
    required this.agentType,
    this.sessionsCount = 0,
    this.note,
  });

  final String name;
  final String agentType;
  final int sessionsCount;
  final String? note;

  factory ProjectInfo.fromJson(Map<String, dynamic> json) {
    return ProjectInfo(
      name: (json['name'] ?? '').toString(),
      agentType: (json['agent_type'] ?? json['agentType'] ?? '').toString(),
      sessionsCount: (json['sessions_count'] is num)
          ? (json['sessions_count'] as num).toInt()
          : int.tryParse('${json['sessions_count'] ?? 0}') ?? 0,
      note: json['note']?.toString(),
    );
  }
}
