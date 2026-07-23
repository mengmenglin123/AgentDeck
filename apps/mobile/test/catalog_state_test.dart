import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/services/catalog_state.dart';

void main() {
  test('stale catalog response cannot replace newer loader result', () async {
    final oldResult = Completer<String>();
    final newResult = Completer<String>();
    var loader = () => oldResult.future;
    final state = CatalogState<String>(loader: () => loader());

    final oldRefresh = state.refresh();
    state.updateLoader(() => newResult.future, refresh: true);
    newResult.complete('codex');
    await Future<void>.delayed(Duration.zero);
    oldResult.complete('claude');
    await oldRefresh;

    expect(state.value, 'codex');
    expect(state.loading, isFalse);
    state.dispose();
  });

  test('catalog error clears on successful retry', () async {
    var attempt = 0;
    final state = CatalogState<String>(
      loader: () async {
        attempt++;
        if (attempt == 1) throw StateError('temporary');
        return 'ready';
      },
      errorMapper: (error) => 'mapped:${error.runtimeType}',
    );

    await state.refresh();
    expect(state.error, 'mapped:StateError');
    await state.refresh();
    expect(state.error, isNull);
    expect(state.value, 'ready');
    state.dispose();
  });

  test('auto refresh stops after disable and dispose', () async {
    var calls = 0;
    final state = CatalogState<int>(
      loader: () async {
        calls++;
        return calls;
      },
      refreshInterval: const Duration(milliseconds: 5),
    );

    state.setAutoRefresh(true);
    await Future<void>.delayed(const Duration(milliseconds: 24));
    expect(calls, greaterThan(0));
    state.setAutoRefresh(false);
    final stoppedAt = calls;
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(calls, stoppedAt);
    state.dispose();
  });

  test('path snapshot stays atomic when an older path finishes late', () async {
    final oldPath = Completer<({String path, String index, String content})>();
    final newPath = Completer<({String path, String index, String content})>();
    final state = CatalogState<({String path, String index, String content})>(
      loader: () => oldPath.future,
    );

    final oldRefresh = state.refresh();
    state.updateLoader(() => newPath.future);
    newPath
        .complete((path: 'src/new.dart', index: 'new-index', content: 'new'));
    await Future<void>.delayed(Duration.zero);
    oldPath
        .complete((path: 'src/old.dart', index: 'old-index', content: 'old'));
    await oldRefresh;

    expect(state.value?.path, 'src/new.dart');
    expect(state.value?.index, 'new-index');
    expect(state.value?.content, 'new');
    state.dispose();
  });
}
