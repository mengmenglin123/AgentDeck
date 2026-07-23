import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:huanhermes_app/screens/connect_screen.dart';
import 'package:huanhermes_app/services/connection_controller.dart';
import 'package:huanhermes_app/services/connection_store.dart';
import 'package:huanhermes_app/models/connection_config.dart';
import 'package:huanhermes_app/models/server_profile.dart';

class _MemStore implements ConnectionStore {
  @override
  Future<void> init() async {}
  @override
  Future<void> save(ConnectionConfig config) async {}
  @override
  Future<ConnectionConfig?> load() async => null;
  @override
  Future<void> clear() async {}
  @override
  Future<List<ServerProfile>> listProfiles() async => [];
  @override
  Future<String?> activeProfileId() async => null;
  @override
  Future<void> setActiveProfileId(String id) async {}
  @override
  Future<void> upsertProfile(ServerProfile profile, {bool setActive = true}) async {}
  @override
  Future<void> deleteProfile(String id) async {}
}

void main() {
  testWidgets('连接页显示中文主文案', (tester) async {
    final controller = ConnectionController(store: _MemStore());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: ConnectScreen()),
      ),
    );
    expect(find.text('连接服务器'), findsOneWidget);
    expect(find.text('连接 Host 控制台'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('测试并连接'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('测试并连接'), findsOneWidget);
  });
}
