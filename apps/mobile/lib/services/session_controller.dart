import 'package:flutter/foundation.dart';

import '../errors/app_errors.dart';
import '../models/connection_config.dart';
import '../models/session_info.dart';
import 'mgmt_client.dart';

class SessionController extends ChangeNotifier {
  SessionController({
    required ConnectionConfig config,
    MgmtClient Function(ConnectionConfig config)? mgmtFactory,
  })  : _config = config,
        _mgmtFactory = mgmtFactory ?? ((c) => MgmtClient(config: c));

  ConnectionConfig _config;
  final MgmtClient Function(ConnectionConfig config) _mgmtFactory;

  List<SessionInfo> sessions = [];
  List<ProjectInfo> projects = [];
  String? selectedProject;
  bool loading = false;
  String? error;

  void updateConfig(ConnectionConfig config) {
    _config = config;
  }

  MgmtClient get _mgmt => _mgmtFactory(_config);

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      projects = await _mgmt.projects();
      if (selectedProject == null && projects.isNotEmpty) {
        selectedProject = projects.first.name;
      }
      sessions = await _mgmt.sessions(project: selectedProject);
      // newest first
      sessions.sort((a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));
    } on AuthError catch (e) {
      error = e.message;
    } on DisconnectedError catch (e) {
      error = 'Cannot reach host: ${e.message}';
    } on ProtocolError catch (e) {
      error = e.message;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void selectProject(String? name) {
    selectedProject = name;
    notifyListeners();
    refresh();
  }

  Future<SessionInfo?> createSession({String? title}) async {
    final project = selectedProject ?? 'claude-code';
    try {
      final s = await _mgmt.createSession(project: project, title: title);
      await refresh();
      return s;
    } on Exception catch (e) {
      error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteSession(SessionInfo session) async {
    try {
      await _mgmt.deleteSession(session.id);
      await refresh();
    } on Exception catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }
}
