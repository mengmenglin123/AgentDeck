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
  int _refreshGeneration = 0;

  void updateConfig(ConnectionConfig config) {
    _config = config;
  }

  MgmtClient get _mgmt => _mgmtFactory(_config);

  ProjectInfo? get selectedProjectInfo {
    final name = selectedProject;
    if (name == null) return null;
    for (final project in projects) {
      if (project.name == name) return project;
    }
    return null;
  }

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final nextProjects = await _mgmt.projects();
      if (generation != _refreshGeneration) return;
      projects = nextProjects;
      final available = projects.map((project) => project.name).toSet();
      if (selectedProject == null || !available.contains(selectedProject)) {
        selectedProject = projects.isEmpty ? null : projects.first.name;
      }
      final project = selectedProject;
      final nextSessions = await _mgmt.sessions(project: project);
      if (generation != _refreshGeneration || project != selectedProject)
        return;
      nextSessions.sort(
        (a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0),
      );
      sessions = nextSessions;
    } on AuthError catch (e) {
      if (generation == _refreshGeneration) error = e.message;
    } on DisconnectedError catch (e) {
      if (generation == _refreshGeneration) {
        error = 'Cannot reach host: ${e.message}';
      }
    } on ProtocolError catch (e) {
      if (generation == _refreshGeneration) error = e.message;
    } catch (e) {
      if (generation == _refreshGeneration) error = e.toString();
    } finally {
      if (generation == _refreshGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<SessionInfo?> locateSession(String reference) async {
    final ref = reference.trim();
    if (ref.isEmpty) return null;
    SessionInfo? matchIn(Iterable<SessionInfo> values) {
      for (final session in values) {
        if (session.sessionKey == ref || session.id == ref) return session;
      }
      return null;
    }

    final current = matchIn(sessions);
    if (current != null) return current;

    final generation = ++_refreshGeneration;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final nextProjects = await _mgmt.projects();
      if (generation != _refreshGeneration) return null;
      projects = nextProjects;
      for (final project in nextProjects) {
        final projectSessions = await _mgmt.sessions(project: project.name);
        if (generation != _refreshGeneration) return null;
        final match = matchIn(projectSessions);
        if (match == null) continue;
        projectSessions.sort(
          (a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0),
        );
        selectedProject = project.name;
        sessions = projectSessions;
        return match;
      }
      return null;
    } on Exception catch (exception) {
      if (generation == _refreshGeneration) error = exception.toString();
      return null;
    } finally {
      if (generation == _refreshGeneration) {
        loading = false;
        notifyListeners();
      }
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
      await _mgmt.deleteSession(
        session.id,
        project: session.project.isEmpty ? selectedProject : session.project,
      );
      await refresh();
    } on Exception catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<SessionInfo?> renameSession(SessionInfo session, String title) async {
    final t = title.trim();
    if (t.isEmpty) return null;
    try {
      final s = await _mgmt.renameSession(
        session.id,
        title: t,
        project: session.project.isEmpty ? selectedProject : session.project,
      );
      await refresh();
      return s;
    } on Exception catch (e) {
      error = e.toString();
      notifyListeners();
      return null;
    }
  }
}
