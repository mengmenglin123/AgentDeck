import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:huanhermes_app/models/connection_config.dart';
import 'package:huanhermes_app/services/connection_controller.dart';
import 'package:huanhermes_app/services/connection_store.dart';
import 'package:huanhermes_app/services/mgmt_client.dart';

class MemoryConfigStore implements ConnectionStore {
  ConnectionConfig? _cfg;

  @override
  Future<void> init() async {}

  @override
  Future<void> save(ConnectionConfig config) async => _cfg = config;

  @override
  Future<ConnectionConfig?> load() async => _cfg;

  @override
  Future<void> clear() async => _cfg = null;
}

void main() {
  test('testAndSave succeeds and marks ready', () async {
    final store = MemoryConfigStore();
    final controller = ConnectionController(
      store: store,
      mgmtFactory: (c) => MgmtClient(
        config: c,
        get: (url, {headers}) async => http.Response(
          jsonEncode({
            'ok': true,
            'data': {'version': 'mock', 'uptime_sec': 1},
          }),
          200,
        ),
      ),
    );
    controller.draft = ConnectionConfig(
      host: '127.0.0.1',
      bridgeToken: 'dev-bridge-token-change-me',
      mgmtToken: 'dev-mgmt-token-change-me',
      deviceId: 't1',
    );
    final ok = await controller.testAndSave();
    expect(ok, isTrue);
    expect(controller.isReady, isTrue);
    expect(controller.lastStatus?['version'], 'mock');
    final loaded = await store.load();
    expect(loaded?.host, '127.0.0.1');
  });

  test('missing tokens fails', () async {
    final store = MemoryConfigStore();
    final controller = ConnectionController(store: store);
    controller.draft = ConnectionConfig(host: '127.0.0.1', deviceId: 't2');
    final ok = await controller.testAndSave();
    expect(ok, isFalse);
    expect(controller.phase, ConnectionPhase.error);
  });
}
