import '../models/connection_config.dart';

abstract class ConnectionStore {
  Future<void> init();
  Future<void> save(ConnectionConfig config);
  Future<ConnectionConfig?> load();
  Future<void> clear();
}
