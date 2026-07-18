import '../models/connection_config.dart';
import '../models/server_profile.dart';

/// Persistence for one or many Host profiles.
abstract class ConnectionStore {
  Future<void> init();

  /// Active connection config (backward compatible).
  Future<void> save(ConnectionConfig config);
  Future<ConnectionConfig?> load();
  Future<void> clear();

  /// Multi-profile (P2-5)
  Future<List<ServerProfile>> listProfiles();
  Future<String?> activeProfileId();
  Future<void> setActiveProfileId(String id);
  Future<void> upsertProfile(ServerProfile profile, {bool setActive = true});
  Future<void> deleteProfile(String id);
}
