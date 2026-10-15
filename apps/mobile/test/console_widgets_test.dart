import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/theme/app_theme.dart';
import 'package:huanhermes_app/widgets/console_widgets.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('error state shows message and retries', (tester) async {
    var retries = 0;
    await tester.pumpWidget(_host(
      ConsoleErrorState(message: 'HTTP 502', onRetry: () => retries++),
    ));
    expect(find.text('加载失败'), findsOneWidget);
    expect(find.text('HTTP 502'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retries, 1);
  });

  testWidgets('error state hides retry without a callback', (tester) async {
    await tester.pumpWidget(_host(const ConsoleErrorState(message: 'x')));
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('inline error uses error container colours in dark mode',
      (tester) async {
    var retries = 0;
    final theme = AppTheme.dark();
    await tester.pumpWidget(_host(
      ConsoleInlineError(message: '会话加载失败', onRetry: () => retries++),
      theme: theme,
    ));
    final text = tester.widget<Text>(find.text('会话加载失败'));
    expect(text.style?.color, theme.colorScheme.onErrorContainer);
    await tester.tap(find.text('重试'));
    expect(retries, 1);
  });

  testWidgets('loading shows optional label', (tester) async {
    await tester.pumpWidget(_host(const ConsoleLoading(label: '加载中…')));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('加载中…'), findsOneWidget);
  });
}
