// Widget-level end-to-end pass over every screen against the real Python
// Mock Host (loopback HTTP + WebSocket, no network fakes). Each screen is
// pumped with the same providers the app uses, given time for real I/O, and
// must render real host data without exceptions or error states.
@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/app.dart';
import 'package:huanhermes_app/models/connection_config.dart';
import 'package:huanhermes_app/models/session_info.dart';
import 'package:huanhermes_app/screens/activity_screen.dart';
import 'package:huanhermes_app/screens/agents_screen.dart';
import 'package:huanhermes_app/screens/audit_screen.dart';
import 'package:huanhermes_app/screens/chat_screen.dart';
import 'package:huanhermes_app/screens/cron_screen.dart';
import 'package:huanhermes_app/screens/diff_screen.dart';
import 'package:huanhermes_app/screens/host_dashboard_screen.dart';
import 'package:huanhermes_app/screens/logs_screen.dart';
import 'package:huanhermes_app/screens/mcp_screen.dart';
import 'package:huanhermes_app/screens/memory_screen.dart';
import 'package:huanhermes_app/screens/pairing_screen.dart';
import 'package:huanhermes_app/screens/permissions_screen.dart';
import 'package:huanhermes_app/screens/sessions_screen.dart';
import 'package:huanhermes_app/screens/settings_screen.dart';
import 'package:huanhermes_app/screens/skills_screen.dart';
import 'package:huanhermes_app/screens/status_screen.dart';
import 'package:huanhermes_app/screens/terminal_screen.dart';
import 'package:huanhermes_app/screens/tools_hub_screen.dart';
import 'package:huanhermes_app/screens/workspace_screen.dart';
import 'package:huanhermes_app/services/app_settings_controller.dart';
import 'package:huanhermes_app/services/audit_log.dart';
import 'package:huanhermes_app/services/chat_controller.dart';
import 'package:huanhermes_app/services/connection_controller.dart';
import 'package:huanhermes_app/services/mgmt_client.dart';
import 'package:huanhermes_app/services/session_controller.dart';
import 'package:huanhermes_app/services/theme_controller.dart';
import 'package:huanhermes_app/widgets/console_widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../connection_controller_test.dart' show MemoryConfigStore;
import 'mock_host_harness.dart';

late MockHost host;
var skipAll = false;

/// Lets real sockets make progress between frames.
Future<void> settle(WidgetTester tester, {int rounds = 8, int ms = 120}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<ConnectionController> readyConnection(WidgetTester tester) async {
  final c = ConnectionController(store: MemoryConfigStore());
  c.updateDraft(host.config());
  final ok = await tester.runAsync(() => c.testAndSave());
  expect(ok, isTrue, reason: c.lastError);
  c.stopHealthHeartbeat();
  return c;
}

Future<void> pumpWithProviders(
  WidgetTester tester,
  Widget child, {
  ConnectionController? connection,
  SessionController? sessions,
  ThemeController? theme,
}) async {
  final conn = connection ?? await readyConnection(tester);
  final sc = sessions ?? SessionController(config: conn.saved!);
  final th = theme ?? ThemeController();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ConnectionController>.value(value: conn),
        ChangeNotifierProvider<SessionController>.value(value: sc),
        ChangeNotifierProvider<ThemeController>.value(value: th),
        ChangeNotifierProvider<AppSettingsController>(create: (_) => AppSettingsController()),
      ],
      child: MaterialApp(home: child),
    ),
  );
}

void expectHealthy(WidgetTester tester, String screen) {
  final ex = tester.takeException();
  expect(ex, isNull, reason: '$screen threw: $ex');
  final err = find.byType(ConsoleErrorState);
  if (err.evaluate().isNotEmpty) {
    final texts = find
        .descendant(of: err.first, matching: find.byType(Text))
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .join(' | ');
    fail('$screen shows an error state: $texts');
  }
}

Future<SessionInfo> newSession(String title, {String project = 'claude-code'}) async {
  return MgmtClient(config: host.config()).createSession(project: project, title: title);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // Plugins without a platform side in tests (secure storage, haptics,
    // notifications, clipboard) answer null.
    for (final ch in [
      'dexterous.com/flutter/local_notifications',
      'plugins.it_nomads.com/flutter_secure_storage',
    ]) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(ch), (c) async => null);
    }
    if (!await MockHost.pythonAvailable()) {
      skipAll = true;
      return;
    }
    host = await MockHost.start();
  });

  tearDownAll(() async {
    if (!skipAll) await host.stop();
  });

  setUp(() {
    binding.platformDispatcher.views.first.physicalSize = const Size(1080, 2340);
    binding.platformDispatcher.views.first.devicePixelRatio = 2.75;
  });
  tearDown(() {
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('connect → home shell, all four tabs', (tester) async {
    if (skipAll) return;
    final conn = ConnectionController(store: MemoryConfigStore());
    conn.bootstrapEmpty();
    conn.updateDraft(host.config());
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ConnectionController>.value(value: conn),
        ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
        ChangeNotifierProvider<AppSettingsController>(create: (_) => AppSettingsController()),
      ],
      child: const HuanHermesApp(),
    ));
    await tester.pump();
    expect(find.text('连接服务器'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('测试并连接'), 400,
        scrollable: find.byType(Scrollable).first);
    // Fields mirror the draft; tap the real button.
    await tester.tap(find.text('测试并连接'));
    await settle(tester);
    expect(conn.isReady, isTrue, reason: conn.lastError);
    conn.stopHealthHeartbeat();
    await settle(tester);
    expectHealthy(tester, 'HomeShell/sessions');
    final nav = find.byType(NavigationBar);
    expect(nav, findsOneWidget);
    final dests = find.descendant(of: nav, matching: find.byType(NavigationDestination));
    expect(dests, findsNWidgets(4));
    for (var i = 1; i < 4; i++) {
      await tester.tap(dests.at(i));
      await settle(tester, rounds: 5);
      expectHealthy(tester, 'HomeShell tab $i');
    }
    await tester.tap(dests.at(0));
    await settle(tester, rounds: 3);
    await conn.disconnect();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sessions screen lists host sessions and creates one', (tester) async {
    if (skipAll) return;
    await tester.runAsync(() => newSession('列表里的会话'));
    final conn = await readyConnection(tester);
    final sc = SessionController(config: conn.saved!);
    await tester.runAsync(() => sc.refresh());
    await pumpWithProviders(tester, const SessionsScreen(), connection: conn, sessions: sc);
    await settle(tester);
    expectHealthy(tester, 'Sessions');
    expect(find.text('列表里的会话'), findsWidgets);
    final before = sc.sessions.length;
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsWidgets, reason: 'new-session button');
    await tester.tap(fab.first);
    await settle(tester);
    // A title dialog may appear; confirm it if so.
    final dialogField = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    if (dialogField.evaluate().isNotEmpty) {
      await tester.enterText(dialogField.first, '新建 e2e');
      final ok = find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton));
      await tester.tap(ok.evaluate().isNotEmpty
          ? ok.first
          : find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextButton)).last);
      await settle(tester);
    }
    await tester.runAsync(() => sc.refresh());
    await settle(tester, rounds: 3);
    expect(sc.sessions.length, greaterThan(before));
    expectHealthy(tester, 'Sessions after create');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chat screen: send, stream reply, /perm approve', (tester) async {
    if (skipAll) return;
    final s = await tester.runAsync(() => newSession('聊天 e2e'));
    final conn = await readyConnection(tester);
    await pumpWithProviders(tester, ChatScreen(config: conn.saved!, session: s!), connection: conn);
    await settle(tester);
    expectHealthy(tester, 'Chat');
    final input = find.byType(TextField).last;
    await tester.enterText(input, '你好 屏幕');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settle(tester, rounds: 12);
    expectHealthy(tester, 'Chat after send');
    expect(find.textContaining('收到：你好 屏幕', findRichText: true), findsWidgets);
    await tester.enterText(find.byType(TextField).last, '/perm');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settle(tester, rounds: 8);
    expect(find.textContaining('allow?', findRichText: true), findsWidgets);
    final allow = find.widgetWithText(FilledButton, '允许');
    expect(allow, findsWidgets);
    await tester.tap(allow.first);
    await settle(tester, rounds: 8);
    expect(find.textContaining('allowed: mock ran', findRichText: true), findsWidgets);
    expectHealthy(tester, 'Chat after permission');
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });

  testWidgets('permissions screen renders a pending card', (tester) async {
    if (skipAll) return;
    final s = await tester.runAsync(() => newSession('权限 e2e'));
    final chat = ChatController(config: host.config(), session: s!);
    await tester.runAsync(() async {
      await chat.connect();
      await chat.send('/perm');
      await waitFor(() => chat.messages.any((m) => m.role == 'permission'));
    });
    await pumpWithProviders(tester, PermissionsScreen(chat: chat));
    await settle(tester, rounds: 3);
    expectHealthy(tester, 'Permissions');
    expect(find.textContaining('echo hello', findRichText: true), findsWidgets);
    final deny = find.widgetWithText(FilledButton, 'Deny');
    expect(deny, findsOneWidget);
    await tester.tap(deny);
    await settle(tester, rounds: 6);
    expect(chat.messages.any((m) => m.content.contains('Permission denied')), isTrue,
        reason: 'Deny must reach the host as a deny');
    await tester.runAsync(() => chat.disconnect());
    chat.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('terminal screen: open, run a command, see output', (tester) async {
    if (skipAll) return;
    final s = await tester.runAsync(() => newSession('终端 e2e'));
    final conn = await readyConnection(tester);
    await pumpWithProviders(tester, TerminalScreen(config: conn.saved!, session: s!), connection: conn);
    await settle(tester, rounds: 10);
    expectHealthy(tester, 'Terminal');
    final field = find.byType(TextField);
    expect(field, findsWidgets);
    await tester.enterText(field.last, 'echo term-ok');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settle(tester, rounds: 10);
    // Terminal may ask for a permission before opening a PTY; approve it.
    final allow = find.textContaining('允许');
    if (allow.evaluate().isNotEmpty) {
      await tester.tap(allow.first);
      await settle(tester, rounds: 6);
      await tester.enterText(find.byType(TextField).last, 'echo term-ok');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await settle(tester, rounds: 8);
    }
    expect(find.textContaining('term-ok', findRichText: true), findsWidgets);
    expectHealthy(tester, 'Terminal after command');
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  });

  final catalog = <String, Widget Function(ConnectionConfig c)>{
    'Agents': (c) => AgentsScreen(config: c),
    'Skills': (c) => SkillsScreen(config: c, project: 'claude-code'),
    'MCP': (c) => McpScreen(config: c, project: 'claude-code'),
    'Cron': (c) => CronScreen(config: c),
    'Memory': (c) => MemoryScreen(config: c),
    'Activity': (c) => ActivityScreen(config: c),
    'Logs': (c) => LogsScreen(config: c),
    'Diff': (c) => DiffScreen(config: c),
    'Workspace': (c) => WorkspaceScreen(config: c),
    'Pairing': (c) => PairingScreen(config: c),
    'Status': (c) => const StatusScreen(),
    'HostDashboard': (c) => const HostDashboardScreen(),
    'ToolsHub': (c) => const ToolsHubScreen(),
    'Audit': (c) => AuditScreen(audit: AuditLog()..add('e2e.event', detail: 'x')),
  };
  catalog.forEach((name, build) {
    testWidgets('$name screen loads host data without errors', (tester) async {
      if (skipAll) return;
      final conn = await readyConnection(tester);
      await pumpWithProviders(tester, build(conn.saved!), connection: conn);
      await settle(tester);
      expectHealthy(tester, name);
      expect(find.byType(ConsoleLoading), findsNothing, reason: '$name still loading');
      await tester.pumpWidget(const SizedBox());
      await settle(tester, rounds: 1);
    });
  });

  testWidgets('tools hub opens every tool', (tester) async {
    if (skipAll) return;
    final conn = await readyConnection(tester);
    await pumpWithProviders(tester, const ToolsHubScreen(), connection: conn);
    await settle(tester, rounds: 4);
    final tiles = find.byType(ConsoleToolTile);
    final n = tiles.evaluate().length;
    expect(n, greaterThanOrEqualTo(10));
    for (var i = 0; i < n; i++) {
      final tile = find.byType(ConsoleToolTile).at(i);
      await tester.scrollUntilVisible(tile, 200, scrollable: find.byType(Scrollable).first);
      final label = (tester.widget<ConsoleToolTile>(tile)).label;
      await tester.tap(tile);
      await settle(tester, rounds: 6);
      expectHealthy(tester, 'Tool "$label"');
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      if (nav.canPop()) {
        nav.pop();
        await settle(tester, rounds: 2);
      }
    }
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 1);
  });

  testWidgets('settings: theme switch applies', (tester) async {
    if (skipAll) return;
    final theme = ThemeController();
    await pumpWithProviders(tester, const SettingsScreen(), theme: theme);
    await settle(tester, rounds: 2);
    expectHealthy(tester, 'Settings');
    await tester.tap(find.byIcon(Icons.dark_mode).first);
    await tester.pump();
    expect(theme.mode, ThemeMode.dark);
    await tester.tap(find.byIcon(Icons.light_mode).first);
    await tester.pump();
    expect(theme.mode, ThemeMode.light);
    await tester.pumpWidget(const SizedBox());
  });
}
