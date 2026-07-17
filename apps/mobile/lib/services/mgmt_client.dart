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

/// Management REST client (MVP subset).
class MgmtClient {
  MgmtClient({
    required this.config,
    HttpSender? sender,
    // Backward-compatible test hook for GET-only tests.
    Future<http.Response> Function(Uri url, {Map<String, String>? headers})? get,
  }) : _send = sender ??
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

  Future<List<SessionInfo>> sessions({String? project}) async {
    final q = (project == null || project.isEmpty) ? '' : '?project=$project';
    final data = await _request('GET', '/sessions$q');
    final list = data['sessions'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => SessionInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<SessionInfo> createSession({
    required String project,
    String? title,
  }) async {
    final body = <String, dynamic>{'project': project};
    if (title != null && title.isNotEmpty) body['title'] = title;
    final data = await _request('POST', '/sessions', body: body);
    return SessionInfo.fromJson(data);
  }

  Future<void> deleteSession(String sessionId) async {
    await _request('DELETE', '/sessions/${Uri.encodeComponent(sessionId)}');
  }

  Future<Map<String, dynamic>> sessionDetail(String sessionId) async {
    return _request('GET', '/sessions/${Uri.encodeComponent(sessionId)}');
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
