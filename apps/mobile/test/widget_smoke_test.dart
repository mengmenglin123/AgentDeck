
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:huanhermes_app/screens/connect_screen.dart';
import 'package:huanhermes_app/services/connection_controller.dart';
import 'package:huanhermes_app/services/connection_store.dart';
import 'package:huanhermes_app/models/connection_config.dart';

class _MemStore implements ConnectionStore {
  @override
  Future<void> init() async {}
  @override
  Future<void> save(ConnectionConfig config) async {}
  @override
  Future<ConnectionConfig?> load() async => null;
  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('Connect screen shows Test & Save', (tester) async {
    final controller = ConnectionController(store: _MemStore());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: ConnectScreen()),
      ),
    );
    expect(find.text('Connect to Host'), findsOneWidget);
    expect(find.text('Test & Save'), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
  });
}
