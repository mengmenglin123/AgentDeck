import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/models/connection_config.dart';
import 'package:huanhermes_app/models/session_info.dart';
import 'package:huanhermes_app/services/mgmt_client.dart';
import 'package:huanhermes_app/services/session_controller.dart';

class _QueuedMgmt extends MgmtClient {
  _QueuedMgmt(ConnectionConfig config) : super(config: config);

  final projectResults = <Completer<List<ProjectInfo>>>[];
  final sessionResults = <String, Completer<List<SessionInfo>>>{};
  var projectCall = 0;

  @override
  Future<List<ProjectInfo>> projects() => projectResults[projectCall++].future;

  @override
  Future<List<SessionInfo>> sessions({String? project}) {
    return sessionResults
        .putIfAbsent(
          project ?? '',
          Completer<List<SessionInfo>>.new,
        )
        .future;
  }
}

class _LocatorMgmt extends MgmtClient {
  _LocatorMgmt(ConnectionConfig config) : super(config: config);

  @override
  Future<List<ProjectInfo>> projects() async => [
        ProjectInfo(name: 'claude-code', agentType: 'claudecode'),
        ProjectInfo(name: 'codex', agentType: 'codex'),
      ];

  @override
  Future<List<SessionInfo>> sessions({String? project}) async {
    if (project == 'codex') {
      return [
        SessionInfo(
          id: 'codex-id',
          sessionKey: 'huan:codex:stable-key',
          project: 'codex',
        ),
      ];
    }
    return [
      SessionInfo(
        id: 'claude-id',
        sessionKey: 'huan:claude:other',
        project: 'claude-code',
      ),
    ];
  }
}

void main() {
  test('latest project selection wins over stale refresh', () async {
    final config = ConnectionConfig(
      host: '127.0.0.1',
      mgmtToken: 'mgmt',
      bridgeToken: 'bridge',
      deviceId: 'test',
    );
    final mgmt = _QueuedMgmt(config);
    final firstProjects = Completer<List<ProjectInfo>>();
    final secondProjects = Completer<List<ProjectInfo>>();
    mgmt.projectResults.addAll([firstProjects, secondProjects]);
    final controller = SessionController(
      config: config,
      mgmtFactory: (_) => mgmt,
    );

    final firstRefresh = controller.refresh();
    firstProjects.complete([
      ProjectInfo(name: 'claude-code', agentType: 'claudecode'),
      ProjectInfo(name: 'codex', agentType: 'codex'),
    ]);
    await Future<void>.delayed(Duration.zero);

    controller.selectProject('codex');
    secondProjects.complete([
      ProjectInfo(name: 'claude-code', agentType: 'claudecode'),
      ProjectInfo(name: 'codex', agentType: 'codex'),
    ]);
    await Future<void>.delayed(Duration.zero);
    mgmt.sessionResults['codex']!.complete([
      SessionInfo(id: 'codex-1', sessionKey: 'codex-1', project: 'codex'),
    ]);
    await Future<void>.delayed(Duration.zero);

    mgmt.sessionResults['claude-code']!.complete([
      SessionInfo(
          id: 'claude-1', sessionKey: 'claude-1', project: 'claude-code'),
    ]);
    await firstRefresh;

    expect(controller.selectedProject, 'codex');
    expect(controller.sessions.single.project, 'codex');
  });

  test('locates stable session key across projects', () async {
    final config = ConnectionConfig(
      host: '127.0.0.1',
      mgmtToken: 'mgmt',
      bridgeToken: 'bridge',
      deviceId: 'test',
    );
    final mgmt = _LocatorMgmt(config);
    final controller = SessionController(
      config: config,
      mgmtFactory: (_) => mgmt,
    )
      ..selectedProject = 'claude-code'
      ..sessions = [
        SessionInfo(
          id: 'claude-id',
          sessionKey: 'huan:claude:other',
          project: 'claude-code',
        ),
      ];

    final found = await controller.locateSession('huan:codex:stable-key');

    expect(found?.project, 'codex');
    expect(controller.selectedProject, 'codex');
    expect(controller.sessions.single.sessionKey, 'huan:codex:stable-key');
  });
}
