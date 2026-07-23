import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:huanhermes_app/models/connection_config.dart';
import 'package:huanhermes_app/models/server_profile.dart';
import 'package:huanhermes_app/services/connection_controller.dart';
import 'package:huanhermes_app/services/connection_store.dart';
import 'package:huanhermes_app/services/mgmt_client.dart';

class MemoryConfigStore implements ConnectionStore {
  ConnectionConfig? _cfg;
  final Map<String, ServerProfile> _profiles = {};
  String? _active;

  @override
  Future<void> init() async {}

  @override
  Future<void> save(ConnectionConfig config) async {
    _cfg = config;
    final id = _active ?? 'mem-default';
    _active = id;
    _profiles[id] = ServerProfile(
      id: id,
      name: _profiles[id]?.name ?? 'Default',
      config: config,
    );
  }

  @override
  Future<ConnectionConfig?> load() async {
    if (_active != null && _profiles.containsKey(_active)) {
      return _profiles[_active]!.config;
    }
    return _cfg;
  }

  @override
  Future<void> clear() async {
    _cfg = null;
    _profiles.clear();
    _active = null;
  }

  @override
  Future<List<ServerProfile>> listProfiles() async => _profiles.values.toList();

  @override
  Future<String?> activeProfileId() async => _active;

  @override
  Future<void> setActiveProfileId(String id) async => _active = id;

  @override
  Future<void> upsertProfile(ServerProfile profile,
      {bool setActive = true}) async {
    _profiles[profile.id] = profile;
    _cfg = profile.config;
    if (setActive) _active = profile.id;
  }

  @override
  Future<void> deleteProfile(String id) async {
    _profiles.remove(id);
    if (_active == id) {
      _active = _profiles.keys.isEmpty ? null : _profiles.keys.first;
      _cfg = _active == null ? null : _profiles[_active]?.config;
    }
  }
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
    expect(controller.profiles, isNotEmpty);
  });

  test('missing tokens fails', () async {
    final store = MemoryConfigStore();
    final controller = ConnectionController(store: store);
    controller.draft = ConnectionConfig(host: '127.0.0.1', deviceId: 't2');
    final ok = await controller.testAndSave();
    expect(ok, isFalse);
    expect(controller.phase, ConnectionPhase.error);
  });

  test('reads nested Mock adapter without calling it real Hermes', () {
    final controller = ConnectionController(store: MemoryConfigStore());
    controller.lastStatus = {
      'hermes': {'adapter': 'mock', 'process': false},
    };
    expect(controller.adapterType, 'mock');
    expect(controller.isRealHermes, isFalse);

    controller.lastStatus = {
      'hermes': {'adapter': 'hermes', 'process': true},
    };
    expect(controller.adapterType, 'hermes');
    expect(controller.isRealHermes, isTrue);
  });

  test('multi profile switch does not auto-ready', () async {
    final store = MemoryConfigStore();
    final controller = ConnectionController(
      store: store,
      mgmtFactory: (c) => MgmtClient(
        config: c,
        get: (url, {headers}) async => http.Response(
          jsonEncode({
            'ok': true,
            'data': {'version': 'mock'},
          }),
          200,
        ),
      ),
    );
    controller.draftProfileName = 'A';
    controller.draft = ConnectionConfig(
      host: '127.0.0.1',
      bridgeToken: 'a',
      mgmtToken: 'a',
      deviceId: 'a',
    );
    await controller.testAndSave();
    expect(controller.isReady, isTrue);

    await controller.startNewProfile();
    expect(controller.isReady, isFalse);
    controller.draftProfileName = 'B';
    controller.draft = ConnectionConfig(
      host: '10.0.0.2',
      bridgeToken: 'b',
      mgmtToken: 'b',
      deviceId: 'b',
    );
    await controller.testAndSave();
    expect(controller.profiles.length, greaterThanOrEqualTo(2));
  });
}
