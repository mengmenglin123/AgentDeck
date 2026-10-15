import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/models/connection_config.dart';
import 'package:huanhermes_app/models/server_profile.dart';
import 'package:huanhermes_app/screens/connect_screen.dart';
import 'package:huanhermes_app/services/connection_store.dart';
import 'package:huanhermes_app/services/secure_config_store.dart';
import 'package:huanhermes_app/startup/app_bootstrap.dart';
import 'package:huanhermes_app/startup/startup_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Store whose reads fail until [resetCorrupted] is called.
class _BrokenStore implements ConnectionStore, RecoverableConnectionStore {
  _BrokenStore({this.hang = false});

  final bool hang;
  bool broken = true;
  int resets = 0;

  Future<T> _maybeFail<T>(T value) {
    if (!broken) return Future.value(value);
    if (hang) return Completer<T>().future; // never completes
    return Future.error(StateError('keystore key missing'));
  }

  @override
  Future<void> resetCorrupted() async {
    resets++;
    broken = false;
  }

  @override
  Future<void> init() => _maybeFail(null);
  @override
  Future<List<ServerProfile>> listProfiles() => _maybeFail(<ServerProfile>[]);
  @override
  Future<String?> activeProfileId() => _maybeFail(null);
  @override
  Future<ConnectionConfig?> load() => _maybeFail(null);
  @override
  Future<void> save(ConnectionConfig config) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<void> setActiveProfileId(String id) async {}
  @override
  Future<void> upsertProfile(ServerProfile profile,
      {bool setActive = true}) async {}
  @override
  Future<void> deleteProfile(String id) async {}
}

/// Secure storage that behaves like encrypted prefs whose Keystore key is gone.
class _KeylessSecureStorage extends FlutterSecureStorage {
  _KeylessSecureStorage();

  bool wiped = false;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (!wiped) throw StateError('javax.crypto.AEADBadTagException');
    return null;
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    wiped = true;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('store init throwing → profiles reset, app still loads', () async {
    final store = _BrokenStore();
    final result = await AppBootstrap(store: store).run();
    expect(store.resets, 1);
    expect(result.profilesReset, isTrue);
    expect(result.connection.loaded, isTrue);
    expect(result.connection.profiles, isEmpty);
    expect(result.failedSteps, contains('connection'));
  });

  test('store hanging → times out instead of blocking startup', () async {
    final store = _BrokenStore(hang: true);
    final result = await AppBootstrap(
      store: store,
      stepTimeout: const Duration(milliseconds: 50),
    ).run();
    expect(result.profilesReset, isTrue);
    expect(result.connection.loaded, isTrue);
  });

  test('unreadable encrypted secure storage is wiped and startup continues',
      () async {
    SharedPreferences.setMockInitialValues({
      'huan_profiles_public_v2':
          '[{"id":"p1","name":"Old","updatedAt":"2026-10-01T00:00:00.000"}]',
      'huan_active_profile_v2': 'p1',
    });
    final secure = _KeylessSecureStorage();
    final store = SecureConfigStore(secureStorage: secure);
    final result = await AppBootstrap(store: store).run();
    expect(secure.wiped, isTrue);
    expect(result.profilesReset, isTrue);
    expect(result.connection.loaded, isTrue);
    expect(result.connection.profiles, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('huan_profiles_public_v2'), isNull);
  });

  test('healthy store → no reset', () async {
    final store = _BrokenStore()..broken = false;
    final result = await AppBootstrap(store: store).run();
    expect(result.profilesReset, isFalse);
    expect(result.failedSteps, isEmpty);
  });

  testWidgets('UI appears immediately and reaches connect screen when store '
      'init throws', (tester) async {
    await tester.pumpWidget(
      StartupGate(bootstrap: () => AppBootstrap(store: _BrokenStore()).run()),
    );
    // First frame: a real Flutter screen, not the native splash.
    expect(find.byKey(const Key('startup-loading')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(ConnectScreen), findsOneWidget);
    expect(find.textContaining('已重置'), findsOneWidget);
  });
}
