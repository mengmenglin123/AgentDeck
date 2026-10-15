// UI flows for SSH companion bootstrap and pairing import, with the SSH
// layer and the camera scanner replaced by fakes.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/screens/connect_screen.dart';
import 'package:huanhermes_app/screens/ssh_discovery_screen.dart';
import 'package:huanhermes_app/services/app_settings_controller.dart';
import 'package:huanhermes_app/services/connection_controller.dart';
import 'package:huanhermes_app/services/ssh_bootstrap_service.dart';
import 'package:huanhermes_app/services/ssh_discovery_service.dart';
import 'package:huanhermes_app/services/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_controller_test.dart' show MemoryConfigStore;
import 'ssh_fakes.dart';

String? _clipboard;

Future<ConnectionController> _pumpConnect(
  WidgetTester tester, {
  QrCodeScanner? scanner,
  FakeSshServer? ssh,
}) async {
  final conn = ConnectionController(store: MemoryConfigStore());
  conn.bootstrapEmpty();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ConnectionController>.value(value: conn),
      ChangeNotifierProvider<ThemeController>(create: (_) => ThemeController()),
      ChangeNotifierProvider<AppSettingsController>(
          create: (_) => AppSettingsController()),
    ],
    child: MaterialApp(
      home: ConnectScreen(
        qrScanner: scanner,
        sshDiscoveryService:
            ssh == null ? null : SshDiscoveryService(openSession: ssh.opener),
        sshBootstrapService: ssh == null
            ? null
            : SshBootstrapService(
                openSession: ssh.opener,
                assetLoader: (_) async => Uint8List.fromList([1, 2, 3]),
              ),
      ),
    ),
  ));
  await tester.pump();
  return conn;
}

String _fieldText(WidgetTester tester, String label) {
  final f = find.ancestor(
    of: find.text(label),
    matching: find.byType(TextField),
  );
  return tester.widget<TextField>(f.first).controller!.text;
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  // Lists build lazily: scroll until the target exists, then fully show it.
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 200,
        scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await tester.pumpAndSettle();
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _clipboard = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return _clipboard == null ? null : {'text': _clipboard};
        }
        return null;
      },
    );
    binding.platformDispatcher.views.first.physicalSize =
        const Size(1170, 2532);
    binding.platformDispatcher.views.first.devicePixelRatio = 3; // 390x844dp
  });
  tearDown(() {
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  group('pairing import', () {
    testWidgets('QR scan fills host/ports/TLS and keeps the connect screen',
        (tester) async {
      var scans = 0;
      final conn = await _pumpConnect(tester, scanner: (_) async {
        scans++;
        return 'huanhermes://connect?host=192.168.1.20&bridge=19810&mgmt=19820&tls=1';
      });
      await tester.tap(find.byTooltip('导入配对 URI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('扫描二维码'));
      await tester.pumpAndSettle();
      expect(scans, 1);
      expect(tester.takeException(), isNull);
      expect(find.byType(ConnectScreen), findsOneWidget);
      expect(find.textContaining('二维码导入成功'), findsOneWidget);
      expect(conn.draft.host, '192.168.1.20');
      expect(conn.draft.bridgePort, 19810);
      expect(conn.draft.mgmtPort, 19820);
      expect(conn.draft.useTls, isTrue);
      expect(_fieldText(tester, '主机地址'), '192.168.1.20');
    });

    testWidgets('unreadable QR shows an error and changes nothing',
        (tester) async {
      final conn = await _pumpConnect(tester, scanner: (_) async => 'hello');
      final before = conn.draft.host;
      await tester.tap(find.byTooltip('导入配对 URI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('扫描二维码'));
      await tester.pumpAndSettle();
      expect(find.text('无法解析二维码'), findsOneWidget);
      expect(conn.draft.host, before);
    });

    testWidgets('cancelled scan is a no-op', (tester) async {
      final conn = await _pumpConnect(tester, scanner: (_) async => null);
      final before = conn.draft.host;
      await tester.tap(find.byTooltip('导入配对 URI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('扫描二维码'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsNothing);
      expect(conn.draft.host, before);
    });

    testWidgets('clipboard URI is prefilled; tokens in the URI are imported',
        (tester) async {
      _clipboard =
          'huanhermes://connect?host=h.example&bridge=9810&mgmt=9820&tls=0&bridge_token=b-tok-1234567890&mgmt_token=m-tok-1234567890';
      final conn = await _pumpConnect(tester);
      await tester.tap(find.byTooltip('导入配对 URI'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.descendant(
                of: find.byType(AlertDialog), matching: find.byType(TextField)))
            .controller!
            .text,
        _clipboard,
      );
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(conn.draft.host, 'h.example');
      expect(conn.draft.bridgeToken, 'b-tok-1234567890');
      expect(conn.draft.mgmtToken, 'm-tok-1234567890');
      expect(find.textContaining('令牌已导入'), findsOneWidget);
    });

    testWidgets('garbage pasted URI is rejected', (tester) async {
      await _pumpConnect(tester);
      await tester.tap(find.byTooltip('导入配对 URI'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(TextField)),
          'not a uri');
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(find.text('无法解析配对 URI'), findsOneWidget);
    });
  });

  group('SSH companion bootstrap UI', () {
    Future<void> discover(WidgetTester tester, {bool acceptKey = true}) async {
      await tester.enterText(
          find.ancestor(
              of: find.text('SSH 主机'), matching: find.byType(TextField)),
          '10.1.2.3');
      await tester.enterText(
          find.ancestor(of: find.text('用户名'), matching: find.byType(TextField)),
          'u');
      await tester.enterText(
          find.ancestor(
              of: find.text('SSH 密码（不会保存）'), matching: find.byType(TextField)),
          'pw');
      final btn = find.text('连接并自动识别 Agent');
      await tester.ensureVisible(btn);
      await tester.pump();
      await tester.tap(btn);
      // Busy spinner animates forever: pump fixed steps, not pumpAndSettle.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('确认 SSH 主机指纹'), findsOneWidget);
      expect(find.textContaining('SHA256:AAAAfakeHostKeyFingerprint0001'),
          findsWidgets);
      // A careful user takes a minute to compare the fingerprint; that must
      // not count against the 20 s connect timeout.
      await tester.pump(const Duration(seconds: 60));
      await tester.tap(find.text(acceptKey ? '指纹正确，继续' : '拒绝'));
      await tester.pumpAndSettle();
      expect(find.textContaining('超时'), findsNothing);
    }

    testWidgets(
        'discover → install → configure → apply backfills host, ports and tokens',
        (tester) async {
      final ssh = happyServer();
      final conn = await _pumpConnect(tester, ssh: ssh);
      await tester.tap(find.byTooltip('SSH 自动发现 Agent'));
      await tester.pumpAndSettle();
      expect(find.byType(SshDiscoveryScreen), findsOneWidget);

      await discover(tester);
      expect(find.text('发现 2 个 Agent'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _tapText(tester, '安装服务器 Companion');
      expect(find.text('安装服务器 Companion？'), findsOneWidget);
      await tester.tap(find.text('确认安装'));
      await tester.pumpAndSettle();
      // Same host key as discovery: no second fingerprint prompt.
      expect(find.text('确认 SSH 主机指纹'), findsNothing);
      expect(find.text('Companion 0.1.204 已安装'), findsOneWidget);
      expect(find.textContaining('服务尚未自动启动'), findsOneWidget);

      await _tapText(tester, '初始化 Host 配置并生成令牌');
      expect(find.text('Host 配置已生成'), findsOneWidget);
      // Tokens are never rendered.
      expect(find.textContaining('bt-0123456789abcdef0123'), findsNothing);

      await _tapText(tester, '应用主机地址并继续配置 Host');
      expect(find.byType(SshDiscoveryScreen), findsNothing);
      expect(_fieldText(tester, '主机地址'), '10.1.2.3');
      expect(_fieldText(tester, '桥接令牌'), 'bt-0123456789abcdef0123');
      expect(_fieldText(tester, '管理令牌'), 'mt-0123456789abcdef0123');
      expect(find.textContaining('Host 令牌已安全回填'), findsOneWidget);
      expect(ssh.opened, 3, reason: 'discover, install, configure');
      expect(ssh.closed, 3);
      expect(conn.saved, isNull, reason: 'nothing saved before 测试并连接');
      expect(tester.takeException(), isNull);
    });

    testWidgets('host key change between discovery and install aborts install',
        (tester) async {
      final ssh = happyServer();
      await _pumpConnect(tester, ssh: ssh);
      await tester.tap(find.byTooltip('SSH 自动发现 Agent'));
      await tester.pumpAndSettle();
      await discover(tester);
      ssh.fingerprint = 'SHA256:EVILevilEVILevil';
      await _tapText(tester, '安装服务器 Companion');
      await tester.tap(find.text('确认安装'));
      await tester.pumpAndSettle();
      expect(find.text(_SshMsgs.mismatch), findsOneWidget);
      expect(ssh.commands.where(isInstall), isEmpty);
      expect(ssh.uploads, isEmpty);
      expect(find.textContaining('已安装'), findsNothing);
    });

    testWidgets('rejecting the fingerprint shows why and runs nothing',
        (tester) async {
      final ssh = happyServer();
      await _pumpConnect(tester, ssh: ssh);
      await tester.tap(find.byTooltip('SSH 自动发现 Agent'));
      await tester.pumpAndSettle();
      await discover(tester, acceptKey: false);
      expect(find.textContaining('指纹未被确认'), findsOneWidget);
      expect(ssh.commands, isEmpty);
      expect(find.textContaining('个 Agent'), findsNothing);
    });

    testWidgets('install failure keeps discovery results and shows stderr',
        (tester) async {
      final ssh = FakeSshServer()
        ..on(isDiscovery, (_) => ok(discoveryOutput))
        ..on(isDownload, (_) => ok())
        ..on(isInstall, (_) => failed(1, 'python3: not found'));
      await _pumpConnect(tester, ssh: ssh);
      await tester.tap(find.byTooltip('SSH 自动发现 Agent'));
      await tester.pumpAndSettle();
      await discover(tester);
      await _tapText(tester, '安装服务器 Companion');
      await tester.tap(find.text('确认安装'));
      await tester.pumpAndSettle();
      expect(find.textContaining('python3: not found'), findsOneWidget);
      expect(find.text('发现 2 个 Agent'), findsOneWidget);
      expect(find.text('初始化 Host 配置并生成令牌'), findsNothing);
    });
  });
}

abstract final class _SshMsgs {
  static const mismatch = 'SSH 主机指纹与之前确认的不一致，已中止连接（可能存在中间人攻击）。';
}
