
import 'package:flutter/foundation.dart';

import '../errors/app_errors.dart';
import '../models/connection_config.dart';
import '../models/server_profile.dart';
import 'mgmt_client.dart';
import 'connection_store.dart';

enum ConnectionPhase {
  idle,
  testing,
  ready,
  error,
}

class ConnectionController extends ChangeNotifier {
  ConnectionController({
    required ConnectionStore store,
    MgmtClient Function(ConnectionConfig config)? mgmtFactory,
  })  : _store = store,
        _mgmtFactory = mgmtFactory ?? ((c) => MgmtClient(config: c));

  final ConnectionStore _store;
  final MgmtClient Function(ConnectionConfig config) _mgmtFactory;

  ConnectionConfig draft = ConnectionConfig();
  ConnectionConfig? saved;
  ConnectionPhase phase = ConnectionPhase.idle;
  String? lastError;
  Map<String, dynamic>? lastStatus;
  bool loaded = false;

  List<ServerProfile> profiles = [];
  String? activeProfileId;
  String draftProfileName = 'Default';

  bool get isReady => phase == ConnectionPhase.ready && saved != null;

  Future<void> bootstrap() async {
    await _store.init();
    await refreshProfiles();
    final existing = await _store.load();
    if (existing != null) {
      draft = existing;
      saved = existing;
      // Prefer saved tokens only when present; empty = user fills form.
    } else {
      // Dev-friendly placeholders for Mock only (not secrets).
      draft = ConnectionConfig(
        bridgeToken: 'dev-bridge-token-change-me',
        mgmtToken: 'dev-mgmt-token-change-me',
      );
    }
    activeProfileId = await _store.activeProfileId();
    if (activeProfileId != null) {
      final hit = profiles.where((p) => p.id == activeProfileId);
      if (hit.isNotEmpty) draftProfileName = hit.first.name;
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> refreshProfiles() async {
    profiles = await _store.listProfiles();
    activeProfileId = await _store.activeProfileId();
    notifyListeners();
  }

  void updateDraft(ConnectionConfig next) {
    draft = next;
    notifyListeners();
  }

  void updateDraftProfileName(String name) {
    draftProfileName = name.trim().isEmpty ? 'Default' : name.trim();
    notifyListeners();
  }

  /// Select an existing profile into the form (does not auto-connect).
  Future<void> selectProfile(String id) async {
    await refreshProfiles();
    final hit = profiles.where((p) => p.id == id);
    if (hit.isEmpty) return;
    final p = hit.first;
    draft = p.config;
    draftProfileName = p.name;
    activeProfileId = p.id;
    await _store.setActiveProfileId(id);
    // Drop ready state so user re-tests (security: no silent connect after switch).
    phase = ConnectionPhase.idle;
    lastStatus = null;
    lastError = null;
    saved = null;
    notifyListeners();
  }

  /// Load a saved profile and run Test & connect (for in-app host switching).
  Future<bool> switchAndConnect(String id) async {
    await selectProfile(id);
    return testAndSave();
  }

  Future<bool> testAndSave() async {
    phase = ConnectionPhase.testing;
    lastError = null;
    lastStatus = null;
    notifyListeners();

    final cfg = draft;
    if (cfg.host.trim().isEmpty) {
      return _fail('Host is required');
    }
    if (!cfg.hasTokens) {
      return _fail('Bridge token and Management token are required');
    }
    // P2-6: warn plain HTTP to non-local hosts (soft fail optional — still allow LAN)
    if (!cfg.useTls && !_isLocalHost(cfg.host)) {
      // Soft: continue but record status note
    }

    try {
      final client = _mgmtFactory(cfg);
      final status = await client.status();

      ServerProfile profile;
      if (activeProfileId != null && profiles.any((p) => p.id == activeProfileId)) {
        final prev = profiles.firstWhere((p) => p.id == activeProfileId);
        profile = prev.copyWith(
          name: draftProfileName,
          config: cfg,
          updatedAt: DateTime.now(),
        );
      } else {
        profile = ServerProfile(name: draftProfileName, config: cfg);
      }
      await _store.upsertProfile(profile, setActive: true);
      activeProfileId = profile.id;
      await refreshProfiles();

      saved = cfg;
      lastStatus = status;
      phase = ConnectionPhase.ready;
      notifyListeners();
      return true;
    } on AuthError catch (e) {
      return _fail(e.message);
    } on DisconnectedError catch (e) {
      return _fail('Cannot reach host: ${e.message}');
    } on ProtocolError catch (e) {
      return _fail(e.message);
    } catch (e) {
      return _fail(e.toString());
    }
  }

  Future<void> deleteActiveProfile() async {
    final id = activeProfileId;
    if (id == null) return;
    await _store.deleteProfile(id);
    await refreshProfiles();
    if (profiles.isEmpty) {
      draft = ConnectionConfig(
        bridgeToken: 'dev-bridge-token-change-me',
        mgmtToken: 'dev-mgmt-token-change-me',
      );
      draftProfileName = 'Default';
      activeProfileId = null;
      saved = null;
      phase = ConnectionPhase.idle;
    } else {
      await selectProfile(profiles.first.id);
    }
    notifyListeners();
  }

  Future<void> startNewProfile() async {
    draft = ConnectionConfig(
      bridgeToken: '',
      mgmtToken: '',
    );
    draftProfileName = 'Host ${profiles.length + 1}';
    activeProfileId = null;
    phase = ConnectionPhase.idle;
    lastStatus = null;
    lastError = null;
    saved = null;
    notifyListeners();
  }

  Future<void> disconnect({bool clearStorage = false}) async {
    if (clearStorage) {
      await _store.clear();
      profiles = [];
      draft = ConnectionConfig(
        bridgeToken: 'dev-bridge-token-change-me',
        mgmtToken: 'dev-mgmt-token-change-me',
      );
      draftProfileName = 'Default';
      activeProfileId = null;
      saved = null;
    }
    phase = ConnectionPhase.idle;
    lastStatus = null;
    lastError = null;
    notifyListeners();
  }

  bool _isLocalHost(String host) {
    final h = host.trim().toLowerCase();
    return h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '::1' ||
        h == '10.0.2.2' ||
        h.startsWith('192.168.') ||
        h.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(h);
  }

  /// Public helper for UI warning.
  bool get draftNeedsTlsWarning =>
      !draft.useTls && !_isLocalHost(draft.host);

  bool _fail(String message) {
    lastError = message;
    phase = ConnectionPhase.error;
    notifyListeners();
    return false;
  }
}
