import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors/app_errors.dart';
import '../models/connection_config.dart';

typedef HttpGet = Future<http.Response> Function(
  Uri url, {
  Map<String, String>? headers,
});

/// Management REST client (MVP subset).
class MgmtClient {
  MgmtClient({
    required this.config,
    HttpGet? get,
  }) : _get = get ?? ((url, {headers}) => http.get(url, headers: headers));

  final ConnectionConfig config;
  final HttpGet _get;

  Future<Map<String, dynamic>> status() => _request('/status');

  Future<Map<String, dynamic>> projects() => _request('/projects');

  Future<Map<String, dynamic>> _request(String path) async {
    final url = Uri.parse('${config.mgmtBaseUrl}$path');
    final headers = <String, String>{
      'Authorization': 'Bearer ${config.mgmtToken}',
      'Accept': 'application/json',
    };
    late http.Response resp;
    try {
      resp = await _get(url, headers: headers).timeout(const Duration(seconds: 12));
    } on Exception catch (e) {
      throw DisconnectedError(e.toString());
    }

    if (resp.statusCode == 401) {
      throw AuthError(_extractError(resp.body) ?? 'unauthorized');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ProtocolError(
        _extractError(resp.body) ?? 'HTTP ${resp.statusCode}',
      );
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
