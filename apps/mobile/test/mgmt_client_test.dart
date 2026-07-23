import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:huanhermes_app/errors/app_errors.dart';
import 'package:huanhermes_app/models/connection_config.dart';
import 'package:huanhermes_app/models/session_info.dart';
import 'package:huanhermes_app/services/mgmt_client.dart';

void main() {
  final cfg = ConnectionConfig(
    host: '127.0.0.1',
    mgmtPort: 9820,
    mgmtToken: 'dev-mgmt-token-change-me',
    bridgeToken: 'dev-bridge-token-change-me',
    deviceId: 'test',
  );

  test('status maps envelope data', () async {
    final client = MgmtClient(
      config: cfg,
      get: (url, {headers}) async {
        expect(url.path, endsWith('/status'));
        expect(headers?['Authorization'], 'Bearer dev-mgmt-token-change-me');
        return http.Response(
          jsonEncode({
            'ok': true,
            'data': {'version': 'mock-0.1', 'projects': 3},
          }),
          200,
        );
      },
    );
    final data = await client.status();
    expect(data['version'], 'mock-0.1');
    expect(data['projects'], 3);
  });

  test('401 becomes AuthError', () async {
    final client = MgmtClient(
      config: cfg,
      get: (url, {headers}) async =>
          http.Response('{"ok":false,"error":"bad token"}', 401),
    );
    expect(() => client.status(), throwsA(isA<AuthError>()));
  });

  test('createSession posts body', () async {
    final client = MgmtClient(
      config: cfg,
      sender: (method, url, {headers, body}) async {
        expect(method, 'POST');
        expect(url.path, endsWith('/sessions'));
        final map = jsonDecode(body as String) as Map<String, dynamic>;
        expect(map['project'], 'claude-code');
        return http.Response(
          jsonEncode({
            'ok': true,
            'data': {
              'id': 'huan:mock:abc',
              'session_key': 'huan:mock:abc',
              'project': 'claude-code',
              'title': 'T',
            },
          }),
          200,
        );
      },
    );
    final s = await client.createSession(project: 'claude-code', title: 'T');
    expect(s.id, 'huan:mock:abc');
    expect(s.project, 'claude-code');
  });
  test('agent catalogs are project scoped', () async {
    final seen = <Uri>[];
    final client = MgmtClient(
      config: cfg,
      sender: (method, url, {headers, body}) async {
        seen.add(url);
        final key = url.pathSegments.last;
        return http.Response(
            jsonEncode({
              'ok': true,
              'data': key == 'skills'
                  ? {'skills': <dynamic>[]}
                  : key == 'mcp'
                      ? {'servers': <dynamic>[]}
                      : {'agents': <dynamic>[]},
            }),
            200);
      },
    );
    await client.listSkills(project: 'codex');
    await client.listMcp(project: 'claude-code');
    await client.agents(project: 'hermes');
    await client.listMemory(project: 'codex');
    expect(seen.map((uri) => uri.queryParameters['project']).toList(),
        ['codex', 'claude-code', 'hermes', 'codex']);
  });

  test('project catalogs parse models and channels', () {
    final project = ProjectInfo.fromJson({
      'name': 'codex',
      'agent_type': 'codex',
      'models': [
        {'id': 'gpt-5-codex'},
        'o4-mini',
      ],
      'channels': [
        {'name': 'openai'},
      ],
    });
    expect(project.models, ['gpt-5-codex', 'o4-mini']);
    expect(project.channels, ['openai']);
  });
}
