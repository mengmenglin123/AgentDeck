import 'package:flutter/foundation.dart';

import '../errors/app_errors.dart';
import '../models/connection_config.dart';
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

  ConnectionConfig draft = ConnectionConfig(
    bridgeToken: 'dev-bridge-token-change-me',
    mgmtToken: 'dev-mgmt-token-change-me',
  );

  ConnectionConfig? saved;
  ConnectionPhase phase = ConnectionPhase.idle;
  String? lastError;
  Map<String, dynamic>? lastStatus;
  bool loaded = false;

  bool get isReady => phase == ConnectionPhase.ready && saved != null;

  Future<void> bootstrap() async {
    final existing = await _store.load();
    if (existing != null) {
      draft = existing;
      saved = existing;
      // Do not auto-mark ready — user may be offline; keep form prefilled.
    }
    loaded = true;
    notifyListeners();
  }

  void updateDraft(ConnectionConfig next) {
    draft = next;
    notifyListeners();
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

    try {
      final client = _mgmtFactory(cfg);
      final status = await client.status();
      await _store.save(cfg);
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

  Future<void> disconnect({bool clearStorage = false}) async {
    if (clearStorage) {
      await _store.clear();
      draft = ConnectionConfig(
        bridgeToken: 'dev-bridge-token-change-me',
        mgmtToken: 'dev-mgmt-token-change-me',
      );
      saved = null;
    }
    phase = ConnectionPhase.idle;
    lastStatus = null;
    lastError = null;
    notifyListeners();
  }

  bool _fail(String message) {
    lastError = message;
    phase = ConnectionPhase.error;
    notifyListeners();
    return false;
  }
}
