import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection_config.dart';
import '../models/server_profile.dart';
import 'connection_store.dart';

/// Persists multi-server profiles:
/// - public metadata → SharedPreferences
/// - tokens per profile → FlutterSecureStorage
///
/// Migrates legacy single-profile keys on first load.
class SecureConfigStore implements ConnectionStore, RecoverableConnectionStore {
  SecureConfigStore({
    FlutterSecureStorage? secureStorage,
    SharedPreferences? prefs,
  }) : _secure =
           secureStorage ??
           const FlutterSecureStorage(
             // resetOnError: if the Keystore key behind the encrypted prefs is
             // gone (reinstall + restored backup, OEM keystore wipe), the
             // plugin wipes the unreadable store instead of throwing forever.
             aOptions: AndroidOptions(
               encryptedSharedPreferences: true,
               resetOnError: true,
             ),
           ),
       _prefsOverride = prefs;

  static const _profilesKey = 'huan_profiles_public_v2';
  static const _activeKey = 'huan_active_profile_v2';

  // legacy single-profile
  static const _legacyPrefsKey = 'huan_connection_public_v1';
  static const _legacyBridge = 'huan_bridge_token_v1';
  static const _legacyMgmt = 'huan_mgmt_token_v1';

  final FlutterSecureStorage _secure;
  final SharedPreferences? _prefsOverride;
  SharedPreferences? _prefs;

  @override
  Future<void> init() async {
    _prefs ??= _prefsOverride ?? await SharedPreferences.getInstance();
    await _migrateLegacyIfNeeded();
  }

  SharedPreferences get _p {
    final p = _prefs ?? _prefsOverride;
    if (p == null) {
      throw StateError('SecureConfigStore.init() must be called first');
    }
    return p;
  }

  String _bridgeKey(String id) => 'huan_p_${id}_bridge';
  String _mgmtKey(String id) => 'huan_p_${id}_mgmt';

  Future<void> _migrateLegacyIfNeeded() async {
    final existing = _p.getString(_profilesKey);
    if (existing != null && existing.isNotEmpty) return;
    final raw = _p.getString(_legacyPrefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final bridge = await _secure.read(key: _legacyBridge) ?? '';
      final mgmt = await _secure.read(key: _legacyMgmt) ?? '';
      final cfg = ConnectionConfig.fromJson({
        ...map,
        'bridgeToken': bridge,
        'mgmtToken': mgmt,
      });
      final profile = ServerProfile(
        name: 'Default',
        config: cfg,
        note: 'migrated',
      );
      await upsertProfile(profile, setActive: true);
      await _p.remove(_legacyPrefsKey);
      await _secure.delete(key: _legacyBridge);
      await _secure.delete(key: _legacyMgmt);
    } catch (_) {
      // leave legacy; user can re-enter
    }
  }

  @override
  Future<List<ServerProfile>> listProfiles() async {
    await init();
    final raw = _p.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List? ?? [];
    final out = <ServerProfile>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id = m['id']?.toString() ?? '';
      final bridge = id.isEmpty
          ? ''
          : (await _secure.read(key: _bridgeKey(id)) ?? '');
      final mgmt = id.isEmpty
          ? ''
          : (await _secure.read(key: _mgmtKey(id)) ?? '');
      out.add(ServerProfile.fromJson(m, bridgeToken: bridge, mgmtToken: mgmt));
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<void> _savePublicList(List<ServerProfile> profiles) async {
    final public = profiles.map((e) => e.toPublicJson()).toList();
    await _p.setString(_profilesKey, jsonEncode(public));
  }

  @override
  Future<String?> activeProfileId() async {
    await init();
    return _p.getString(_activeKey);
  }

  @override
  Future<void> setActiveProfileId(String id) async {
    await init();
    await _p.setString(_activeKey, id);
  }

  @override
  Future<void> upsertProfile(
    ServerProfile profile, {
    bool setActive = true,
  }) async {
    await init();
    final list = await listProfiles();
    final idx = list.indexWhere((p) => p.id == profile.id);
    final next = profile.copyWith(updatedAt: DateTime.now());
    if (idx >= 0) {
      list[idx] = next;
    } else {
      list.add(next);
    }
    await _secure.write(
      key: _bridgeKey(next.id),
      value: next.config.bridgeToken,
    );
    await _secure.write(key: _mgmtKey(next.id), value: next.config.mgmtToken);
    await _savePublicList(list);
    if (setActive) await setActiveProfileId(next.id);
  }

  @override
  Future<void> deleteProfile(String id) async {
    await init();
    final list = await listProfiles();
    list.removeWhere((p) => p.id == id);
    await _secure.delete(key: _bridgeKey(id));
    await _secure.delete(key: _mgmtKey(id));
    await _savePublicList(list);
    final active = await activeProfileId();
    if (active == id) {
      if (list.isEmpty) {
        await _p.remove(_activeKey);
      } else {
        await setActiveProfileId(list.first.id);
      }
    }
  }

  @override
  Future<void> save(ConnectionConfig config) async {
    await init();
    final activeId = await activeProfileId();
    final list = await listProfiles();
    if (activeId != null) {
      final idx = list.indexWhere((p) => p.id == activeId);
      if (idx >= 0) {
        final updated = list[idx].copyWith(
          config: config,
          updatedAt: DateTime.now(),
        );
        await upsertProfile(updated, setActive: true);
        return;
      }
    }
    // no active → create Default
    await upsertProfile(
      ServerProfile(name: 'Default', config: config),
      setActive: true,
    );
  }

  @override
  Future<ConnectionConfig?> load() async {
    await init();
    final list = await listProfiles();
    if (list.isEmpty) return null;
    final activeId = await activeProfileId();
    final match = list.where((p) => p.id == activeId);
    if (match.isNotEmpty) return match.first.config;
    return list.first.config;
  }

  /// Wipes every persisted profile and secret without reading them first.
  /// Used at startup when the store cannot be read at all.
  @override
  Future<void> resetCorrupted() async {
    try {
      await _secure.deleteAll();
    } catch (_) {
      // Nothing more we can do; resetOnError handles the next access.
    }
    final p = _prefs ?? _prefsOverride ?? await SharedPreferences.getInstance();
    _prefs = p;
    for (final key in const [
      _profilesKey,
      _activeKey,
      _legacyPrefsKey,
    ]) {
      await p.remove(key);
    }
  }

  @override
  Future<void> clear() async {
    await init();
    final list = await listProfiles();
    for (final p in list) {
      await _secure.delete(key: _bridgeKey(p.id));
      await _secure.delete(key: _mgmtKey(p.id));
    }
    await _p.remove(_profilesKey);
    await _p.remove(_activeKey);
    await _p.remove(_legacyPrefsKey);
    await _secure.delete(key: _legacyBridge);
    await _secure.delete(key: _legacyMgmt);
  }
}
