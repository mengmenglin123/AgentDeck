import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection_config.dart';
import 'connection_store.dart';

/// Persists connection profile:
/// - non-secrets → SharedPreferences
/// - tokens → FlutterSecureStorage
class SecureConfigStore implements ConnectionStore {
  SecureConfigStore({
    FlutterSecureStorage? secureStorage,
    SharedPreferences? prefs,
  })  : _secure = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ),
        _prefsOverride = prefs;

  static const _prefsKey = 'huan_connection_public_v1';
  static const _bridgeTokenKey = 'huan_bridge_token_v1';
  static const _mgmtTokenKey = 'huan_mgmt_token_v1';

  final FlutterSecureStorage _secure;
  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  @override
  Future<void> init() async {
    _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    final p = _prefs ?? _prefsOverride;
    if (p == null) {
      throw StateError('SecureConfigStore.init() must be called first');
    }
    return p;
  }

  @override
  Future<void> save(ConnectionConfig config) async {
    await init();
    await _p.setString(_prefsKey, jsonEncode(config.toPublicJson()));
    await _secure.write(key: _bridgeTokenKey, value: config.bridgeToken);
    await _secure.write(key: _mgmtTokenKey, value: config.mgmtToken);
  }

  @override
  Future<ConnectionConfig?> load() async {
    await init();
    final raw = _p.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final bridge = await _secure.read(key: _bridgeTokenKey) ?? '';
    final mgmt = await _secure.read(key: _mgmtTokenKey) ?? '';
    return ConnectionConfig.fromJson({
      ...map,
      'bridgeToken': bridge,
      'mgmtToken': mgmt,
    });
  }

  @override
  Future<void> clear() async {
    await init();
    await _p.remove(_prefsKey);
    await _secure.delete(key: _bridgeTokenKey);
    await _secure.delete(key: _mgmtTokenKey);
  }
}
