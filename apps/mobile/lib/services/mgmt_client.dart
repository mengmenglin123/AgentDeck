
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors/app_errors.dart';
import '../models/connection_config.dart';
import '../models/session_info.dart';

typedef HttpSender = Future<http.Response> Function(
  String method,
  Uri url, {
  Map<String, String>? headers,
  Object? body,
});

/// Management REST client.
///
/// Supports **both**:
/// - HuanHermes Mock flat paths: `/sessions`, `/sessions/{id}`
/// - project-scoped paths: `/projects/{name}/sessions`
///
/// Never prints tokens. Does not modify any host config.
class MgmtClient {
  MgmtClient({
    required this.config,
    HttpSender? sender,
    Future<http.Response> Function(Uri url, {Map<String, String>? headers})? get,
  })  : _send = sender ??
            ((method, url, {headers, body}) async {
              switch (method) {
                case 'GET':
                  return http.get(url, headers: headers);
                case 'POST':
                  return http.post(url, headers: headers, body: body);
                case 'DELETE':
                  return http.delete(url, headers: headers);
                default:
                  throw ProtocolError('unsupported method $method');
              }
            }),
        _legacyGet = get;

  final ConnectionConfig config;
  final HttpSender _send;
  final Future<http.Response> Function(Uri url, {Map<String, String>? headers})? _legacyGet;

  /// Detected host dialect after first successful call: `flat` | `project` | null.
  String? dialect;

  Future<Map<String, dynamic>> status() => _request('GET', '/status');

  Future<List<ProjectInfo>> projects() async {
    final data = await _request('GET', '/projects');
    final list = data['projects'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => ProjectInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> projectDetail(String name) async {
    return _request('GET', '/projects/${Uri.encodeComponent(name)}');
  }

  Future<Map<String, dynamic>> agents() async {
    try {
      return await _request('GET', '/agents');
    } on ProtocolError {
      return {'agents': <String>[], 'platforms': <String>[]};
    }
  }

  /// Readonly skills list when Host exposes GET /skills (Mock + optional Host).
  Future<List<Map<String, dynamic>>> listSkills() async {
    try {
      final data = await _request('GET', '/skills');
      final list = data['skills'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on ProtocolError {
      return const [];
    }
  }

  /// Pairing payload for QR / text share (no live secrets returned by Mock).
  Future<Map<String, dynamic>> pairingInfo() async {
    try {
      return await _request('GET', '/pairing');
    } on ProtocolError {
      return {
        'scheme': 'huanhermes',
        'version': 1,
        'host': config.host,
        'bridge_port': config.bridgePort,
        'mgmt_port': config.mgmtPort,
        'use_tls': config.useTls,
        'pairing_code':
            'huanhermes://connect?host=${config.host}&bridge=${config.bridgePort}&mgmt=${config.mgmtPort}&tls=${config.useTls ? 1 : 0}',
        'note': 'Host has no /pairing — local fallback from App config',
      };
    }
  }

  Future<List<SessionInfo>> sessions({String? project}) async {
    final proj = project ?? '';
    // Prefer dialect if known
    if (dialect == 'project' && proj.isNotEmpty) {
      return _sessionsProjectScoped(proj);
    }
    if (dialect == 'flat') {
      return _sessionsFlat(project: project);
    }

    // Auto-detect: try project-scoped first when project known,
    // then flat path.
    if (proj.isNotEmpty) {
      try {
        final list = await _sessionsProjectScoped(proj);
        dialect = 'project';
        return list;
      } on ProtocolError catch (e) {
        // 404 / not found → try flat
        if (!_looksMissing(e.message)) rethrow;
      }
    }
    final list = await _sessionsFlat(project: project);
    dialect = 'flat';
    return list;
  }

  Future<List<SessionInfo>> _sessionsFlat({String? project}) async {
    final q = (project == null || project.isEmpty) ? '' : '?project=${Uri.encodeComponent(project)}';
    final data = await _request('GET', '/sessions$q');
    return _parseSessions(data, project: project);
  }

  Future<List<SessionInfo>> _sessionsProjectScoped(String project) async {
    final data = await _request('GET', '/projects/${Uri.encodeComponent(project)}/sessions');
    return _parseSessions(data, project: project);
  }

  List<SessionInfo> _parseSessions(Map<String, dynamic> data, {String? project}) {
    final list = data['sessions'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      m.putIfAbsent('project', () => project ?? '');
      return SessionInfo.fromJson(m);
    }).toList();
  }

  Future<SessionInfo> createSession({
    required String project,
    String? title,
    String? sessionKey,
  }) async {
    final body = <String, dynamic>{'project': project};
    if (title != null && title.isNotEmpty) {
      body['title'] = title;
      body['name'] = title;
    }
    if (sessionKey != null && sessionKey.isNotEmpty) {
      body['session_key'] = sessionKey;
    }

    if (dialect == 'project') {
      return _createProjectScoped(project, body);
    }
    if (dialect == 'flat') {
      final data = await _request('POST', '/sessions', body: body);
      return SessionInfo.fromJson(data);
    }

    // Auto: try project-scoped then flat
    try {
      final s = await _createProjectScoped(project, body);
      dialect = 'project';
      return s;
    } on ProtocolError catch (e) {
      if (!_looksMissing(e.message) && !e.message.contains('session_key')) {
        // If host requires session_key, generate one and retry project path
        if (e.message.contains('session_key')) {
          body['session_key'] = sessionKey ?? _genSessionKey(project);
          try {
            final s = await _createProjectScoped(project, body);
            dialect = 'project';
            return s;
          } on ProtocolError {
            // fall through to flat
          }
        } else {
          rethrow;
        }
      } else if (e.message.contains('session_key')) {
        body['session_key'] = sessionKey ?? _genSessionKey(project);
        try {
          final s = await _createProjectScoped(project, body);
          dialect = 'project';
          return s;
        } on ProtocolError {
          // fall through
        }
      }
    }
    final data = await _request('POST', '/sessions', body: body);
    dialect = 'flat';
    return SessionInfo.fromJson(data);
  }

  Future<SessionInfo> _createProjectScoped(String project, Map<String, dynamic> body) async {
    // Ensure session_key present for strict hosts
    body = Map<String, dynamic>.from(body);
    body.putIfAbsent('session_key', () => _genSessionKey(project));
    final data = await _request(
      'POST',
      '/projects/${Uri.encodeComponent(project)}/sessions',
      body: body,
    );
    data.putIfAbsent('project', () => project);
    return SessionInfo.fromJson(data);
  }

  String _genSessionKey(String project) {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    // platform:scope:user  — App is bridge platform adapter
    return 'huanhermes-app:$project:$id';
  }

  Future<void> deleteSession(String sessionId, {String? project}) async {
    if (dialect == 'project' && project != null && project.isNotEmpty) {
      await _request(
        'DELETE',
        '/projects/${Uri.encodeComponent(project)}/sessions/${Uri.encodeComponent(sessionId)}',
      );
      return;
    }
    try {
      await _request('DELETE', '/sessions/${Uri.encodeComponent(sessionId)}');
      return;
    } on ProtocolError catch (e) {
      if (project != null && project.isNotEmpty && _looksMissing(e.message)) {
        await _request(
          'DELETE',
          '/projects/${Uri.encodeComponent(project)}/sessions/${Uri.encodeComponent(sessionId)}',
        );
        dialect = 'project';
        return;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sessionDetail(String sessionId, {String? project}) async {
    try {
      return await _request('GET', '/sessions/${Uri.encodeComponent(sessionId)}');
    } on ProtocolError catch (e) {
      if (project != null && project.isNotEmpty && _looksMissing(e.message)) {
        return await _request(
          'GET',
          '/projects/${Uri.encodeComponent(project)}/sessions/${Uri.encodeComponent(sessionId)}',
        );
      }
      rethrow;
    }
  }

  bool _looksMissing(String msg) {
    final m = msg.toLowerCase();
    return m.contains('404') ||
        m.contains('not found') ||
        m.contains('unknown') ||
        m.contains('page not found');
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final url = Uri.parse('${config.mgmtBaseUrl}$path');
    final headers = <String, String>{
      'Authorization': 'Bearer ${config.mgmtToken}',
      'Accept': 'application/json',
    };
    Object? rawBody;
    if (body != null) {
      headers['Content-Type'] = 'application/json';
      rawBody = jsonEncode(body);
    }

    late http.Response resp;
    try {
      if (method == 'GET' && _legacyGet != null) {
        resp = await _legacyGet!(url, headers: headers).timeout(const Duration(seconds: 12));
      } else {
        resp = await _send(method, url, headers: headers, body: rawBody)
            .timeout(const Duration(seconds: 12));
      }
    } on Exception catch (e) {
      throw DisconnectedError(e.toString());
    }

    if (resp.statusCode == 401) {
      throw AuthError(_extractError(resp.body) ?? 'unauthorized');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ProtocolError(_extractError(resp.body) ?? 'HTTP ${resp.statusCode}');
    }

    final payload = _decode(resp.body);
    if (payload['ok'] != true) {
      throw ProtocolError(payload['error']?.toString() ?? 'request failed');
    }
    final data = payload['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return {'ok': true, 'data': {}};
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      throw ProtocolError('invalid json envelope');
    } on FormatException catch (e) {
      throw ProtocolError('invalid json: ${e.message}');
    }
  }

  String? _extractError(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map && v['error'] != null) return v['error'].toString();
    } catch (_) {}
    return body.isEmpty ? null : body;
  }
}
