// End-to-end checks of the app's service layer against the real Python Mock
// Host over loopback HTTP + WebSocket (no fakes in the network path).
@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/errors/app_errors.dart';
import 'package:huanhermes_app/models/session_info.dart';
import 'package:huanhermes_app/services/bridge_client.dart';
import 'package:huanhermes_app/services/chat_controller.dart';
import 'package:huanhermes_app/services/connection_controller.dart';
import 'package:huanhermes_app/services/mgmt_client.dart';
import 'package:huanhermes_app/services/notification_service.dart';
import 'package:huanhermes_app/services/session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../connection_controller_test.dart' show MemoryConfigStore;
import 'mock_host_harness.dart';

final notifications = <MethodCall>[];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding replaces HttpClient with a 400-only mock; these tests
  // need the real network to reach the loopback mock host.
  HttpOverrides.global = null;

  late MockHost host;
  var skip = false;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // Route notifications to a recording channel (Android implementation).
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        notifications.add(call);
        if (call.method == 'initialize') return true;
        return null;
      },
    );
    if (!await MockHost.pythonAvailable()) {
      skip = true;
      return;
    }
    host = await MockHost.start();
  });

  tearDownAll(() async {
    if (!skip) await host.stop();
  });

  MgmtClient mgmt() => MgmtClient(config: host.config());

  group('connect / profiles', () {
    test('testAndSave connects, saves profile and probes health', () async {
      if (skip) return markTestSkipped('python3 missing');
      final store = MemoryConfigStore();
      final c = ConnectionController(store: store);
      c.updateDraft(host.config());
      expect(await c.testAndSave(), isTrue, reason: c.lastError);
      expect(c.isReady, isTrue);
      expect(c.hostRuntime.displayLabel, isNotEmpty);
      expect((await store.listProfiles()), hasLength(1));
      expect(await c.probeHealth(), isTrue);
      await c.disconnect();
      c.dispose();
    });

    test('wrong mgmt token is rejected with a readable error', () async {
      if (skip) return markTestSkipped('python3 missing');
      final c = ConnectionController(store: MemoryConfigStore());
      c.updateDraft(host.config().copyWith(mgmtToken: 'wrong-token-xxxxxxxxxx'));
      expect(await c.testAndSave(), isFalse);
      expect(c.isReady, isFalse);
      expect(c.lastError, isNotNull);
      c.dispose();
    });

    test('wrong bridge token fails chat connect without crashing', () async {
      if (skip) return markTestSkipped('python3 missing');
      final cfg = host.config().copyWith(bridgeToken: 'wrong-bridge-xxxxxxxxxx');
      final chat = ChatController(
        config: cfg,
        session: SessionInfo(id: 's-bad', sessionKey: 'huanhermes-app:e2e:bad', project: 'claude-code'),
      )..autoReconnect = false;
      await chat.connect();
      expect(chat.connected, isFalse);
      expect(chat.error, isNotNull);
      chat.dispose();
    });
  });

  group('management API (every screen data source)', () {
    test('status / projects / project detail / agents', () async {
      if (skip) return markTestSkipped('python3 missing');
      final st = await mgmt().status();
      expect(st['capabilities'], isA<List>());
      final projects = await mgmt().projects();
      expect(projects.map((p) => p.name), containsAll(['claude-code', 'codex', 'hermes']));
      final detail = await mgmt().projectDetail('claude-code');
      expect(detail, isNotEmpty);
      final agents = await mgmt().agents();
      expect(agents, isNotEmpty);
    });

    test('skills / MCP / memory / cron / activity / logs', () async {
      if (skip) return markTestSkipped('python3 missing');
      expect(await mgmt().listSkills(project: 'claude-code'), isNotEmpty);
      expect(await mgmt().listMcp(project: 'claude-code'), isNotEmpty);
      expect(await mgmt().listMemory(), isNotEmpty);
      expect(await mgmt().listCron(), isNotEmpty);
      expect(await mgmt().listActivity(limit: 20), isNotEmpty);
      expect(await mgmt().logs(), isNotEmpty);
    });

    test('workspace tree / git / diff (read-only)', () async {
      if (skip) return markTestSkipped('python3 missing');
      final ws = await mgmt().workspace();
      expect(ws, isNotEmpty);
      expect(await mgmt().workspaceGit(), isNotEmpty);
      expect(await mgmt().workspaceDiff(), isNotEmpty);
    });

    test('pairing info carries no tokens', () async {
      if (skip) return markTestSkipped('python3 missing');
      final p = await mgmt().pairingInfo();
      final s = p.toString();
      expect(s.contains(MockHost.mgmtToken), isFalse);
      expect(s.contains(MockHost.bridgeToken), isFalse);
    });
  });

  group('sessions', () {
    test('list / create / rename / delete through SessionController', () async {
      if (skip) return markTestSkipped('python3 missing');
      final sc = SessionController(config: host.config());
      await sc.refresh();
      expect(sc.error, isNull);
      expect(sc.projects, isNotEmpty);
      final before = sc.sessions.length;
      final created = await sc.createSession(title: 'e2e 会话');
      expect(created, isNotNull, reason: sc.error);
      expect(sc.sessions.length, before + 1);
      final renamed = await sc.renameSession(created!, '改名后');
      expect(renamed?.displayTitle, '改名后');
      expect(sc.sessions.any((s) => s.displayTitle == '改名后'), isTrue);
      await sc.deleteSession(sc.sessions.firstWhere((s) => s.id == created.id));
      expect(sc.error, isNull);
      expect(sc.sessions.any((s) => s.id == created.id), isFalse);
      final located = await sc.locateSession('does-not-exist');
      expect(located, isNull);
      sc.dispose();
    });
  });

  group('chat', () {
    late SessionInfo session;
    setUp(() async {
      if (skip) return;
      session = await mgmt().createSession(project: 'claude-code', title: 'chat e2e');
      notifications.clear();
    });

    test('streams thinking, tool call/result and final reply', () async {
      if (skip) return markTestSkipped('python3 missing');
      final chat = ChatController(config: host.config(), session: session);
      await chat.connect();
      expect(chat.connected, isTrue, reason: chat.error);
      expect(await chat.send('你好 e2e'), isTrue);
      await waitFor(() => !chat.runActive && chat.messages.any((m) => m.role == 'assistant' && !m.streaming),
          reason: 'run_done');
      final roles = chat.messages.map((m) => m.role).toList();
      expect(roles.firstWhere((r) => r != 'system'), 'user');
      expect(roles, contains('tool'));
      expect(roles, contains('assistant'));
      final reply = chat.messages.lastWhere((m) => m.role == 'assistant');
      expect(reply.content, contains('收到：你好 e2e'));
      expect(chat.error, isNull);
      await chat.disconnect();
      chat.dispose();
    });

    test('no error notification on connect (register_ack has error:"")', () async {
      if (skip) return markTestSkipped('python3 missing');
      final chat = ChatController(config: host.config(), session: session);
      await chat.connect();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final shows = notifications.where((c) => c.method == 'show').toList();
      expect(shows, isEmpty, reason: shows.map((c) => c.arguments).join('\n'));
      await chat.disconnect();
      chat.dispose();
    });

    test('cancel stops an active run', () async {
      if (skip) return markTestSkipped('python3 missing');
      final chat = ChatController(config: host.config(), session: session);
      await chat.connect();
      await chat.send('请写一段很长的回复 ' * 20);
      await waitFor(() => chat.runActive, reason: 'run started');
      await chat.cancelRun();
      await waitFor(() => !chat.runActive, reason: 'run ended after cancel');
      await waitFor(() => chat.messages.any((m) => m.content.contains('cancelled')),
          reason: 'host confirmed the cancel');
      final shows = notifications.where((c) => c.method == 'show').map((c) => '${c.arguments}').toList();
      expect(shows.where((s) => s.contains('任务完成')), isEmpty,
          reason: 'a user-cancelled run must not say "任务完成"');
      await chat.disconnect();
      chat.dispose();
    });

    test('mode / model switch via slash command is reflected by the host', () async {
      if (skip) return markTestSkipped('python3 missing');
      final chat = ChatController(config: host.config(), session: session);
      await chat.connect();
      await chat.sendSlash('/mode plan');
      await waitFor(() => chat.messages.any((m) => m.content.contains('mode set to: plan')));
      await chat.sendSlash('/model mock-codex');
      await waitFor(() => chat.messages.any((m) => m.content.contains('model set to: mock-codex')));
      await chat.reloadTranscript();
      expect(chat.mode, 'plan');
      expect(chat.model, 'mock-codex');
      await chat.disconnect();
      chat.dispose();
    });

    for (final action in ['allow', 'deny', 'allow_all']) {
      test('permission card → $action', () async {
        if (skip) return markTestSkipped('python3 missing');
        final chat = ChatController(config: host.config(), session: session);
        await chat.connect();
        await chat.send('/perm');
        await waitFor(() => chat.messages.any((m) => m.role == 'permission'), reason: 'permission card');
        final card = chat.messages.lastWhere((m) => m.role == 'permission');
        expect(card.meta['buttons'], isNotEmpty);
        // A permission request must raise a notification so a backgrounded
        // user can come back and answer it.
        expect(notifications.where((c) => c.method == 'show' && '${c.arguments}'.contains('需要权限')), isNotEmpty);
        await chat.respondPermission('perm:demo:$action');
        final expected = {'allow': 'allowed: mock ran', 'deny': 'Permission denied', 'allow_all': 'allowed_all'}[action]!;
        await waitFor(() => chat.messages.any((m) => m.role == 'assistant' && m.content.contains(expected)),
            reason: 'permission result');
        await chat.disconnect();
        chat.dispose();
      });
    }

    test('transcript reload hydrates history from the host', () async {
      if (skip) return markTestSkipped('python3 missing');
      final chat = ChatController(config: host.config(), session: session);
      await chat.connect();
      await chat.send('记住这一句');
      await waitFor(() => !chat.runActive && chat.messages.any((m) => m.role == 'assistant'));
      await chat.disconnect();
      chat.dispose();
      final fresh = ChatController(config: host.config(), session: session);
      await fresh.reloadTranscript();
      expect(fresh.messages.any((m) => m.content.contains('记住这一句')), isTrue);
      fresh.dispose();
    });
  });

  group('terminal channel', () {
    test('open → input → output → resize → close', () async {
      if (skip) return markTestSkipped('python3 missing');
      final frames = <Map<String, dynamic>>[];
      final b = BridgeClient(config: host.config(), onMessage: frames.add);
      await b.connect();
      const sk = 'huanhermes-app:e2e:term';
      b.terminalOpen(sessionKey: sk, streamId: 'st-1', cols: 100, rows: 30);
      await waitFor(() => frames.any((f) => f['type'] == 'terminal_open_ack'));
      b.terminalInput(sessionKey: sk, data: 'echo hello-e2e\n', streamId: 'st-1');
      await waitFor(() => frames.any((f) => f['type'] == 'terminal_out' && '${f['data']}'.contains('hello-e2e')),
          reason: 'echo output');
      b.terminalResize(sessionKey: sk, cols: 120, rows: 40, streamId: 'st-1');
      await waitFor(() => frames.any((f) => f['type'] == 'terminal_ack' && f['cols'] == 120));
      b.terminalClose(sessionKey: sk, streamId: 'st-1');
      await waitFor(() => frames.any((f) => f['type'] == 'terminal_exit'));
      await b.close();
    });

    test('bad bridge token → AuthError/Disconnected, not a hang', () async {
      if (skip) return markTestSkipped('python3 missing');
      final b = BridgeClient(config: host.config().copyWith(bridgeToken: 'nope-nope-nope-nope'));
      final sw = Stopwatch()..start();
      await expectLater(
        b.connect(timeout: const Duration(seconds: 8)),
        throwsA(isA<AuthError>()),
      );
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)),
          reason: 'a refused upgrade must fail fast, not wait for register timeout');
      await b.close();
    });
  });

  group('notifications', () {
    test('task-complete notification uses the kept monochrome icon and opens the session', () async {
      if (skip) return markTestSkipped('python3 missing');
      notifications.clear();
      await NotificationService.instance.showTaskComplete(
          sessionKey: 'sk-1', sessionName: '会话', summary: '完成');
      final init = notifications.firstWhere((c) => c.method == 'initialize', orElse: () => const MethodCall('none'));
      if (init.method == 'initialize') {
        expect('${init.arguments}', contains('ic_stat_notify'));
      }
      final show = notifications.lastWhere((c) => c.method == 'show');
      expect('${show.arguments}', contains('任务完成：会话'));
      expect('${show.arguments}', contains('session:sk-1'));
    });
  });
}
