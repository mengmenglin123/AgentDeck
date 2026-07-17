import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:huanhermes_app/errors/app_errors.dart';
import 'package:huanhermes_app/models/connection_config.dart';
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
      get: (url, {headers}) async => http.Response('{"ok":false,"error":"bad token"}', 401),
    );
    expect(() => client.status(), throwsA(isA<AuthError>()));
  });
}
