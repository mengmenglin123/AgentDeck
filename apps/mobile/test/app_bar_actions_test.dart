import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/widgets/app_bar_actions.dart';

void main() {
  testWidgets('many actions fit a 390dp toolbar via overflow menu', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    var tapped = '';
    final actions = [
      for (final n in ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'])
        IconButton(
          tooltip: '动作$n',
          onPressed: n == 'h' ? null : () => tapped = n,
          icon: const Icon(Icons.star),
        ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('标题很长的页面'), actions: compactAppBarActions(actions)),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(IconButton), findsNWidgets(4)); // 3 + overflow
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('动作e'), findsOneWidget);
    await tester.tap(find.text('动作e'));
    await tester.pumpAndSettle();
    expect(tapped, 'e');
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    final disabled = tester.widget<PopupMenuItem<int>>(
        find.ancestor(of: find.text('动作h'), matching: find.byType(PopupMenuItem<int>)));
    expect(disabled.enabled, isFalse);
  });

  test('few actions are left untouched', () {
    final a = [IconButton(tooltip: 'x', onPressed: () {}, icon: const Icon(Icons.add))];
    expect(compactAppBarActions(a), same(a));
  });
}
