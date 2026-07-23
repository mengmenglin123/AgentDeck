import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/services/terminal_output_batcher.dart';

void main() {
  test('coalesces frames into one flush', () async {
    final flushed = <String>[];
    final batcher = TerminalOutputBatcher(
      interval: const Duration(milliseconds: 1),
      onFlush: flushed.add,
    );
    batcher.add('a');
    batcher.add('b');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(flushed, ['ab']);
    batcher.dispose();
  });

  test('bounds pending output and can discard it', () {
    final flushed = <String>[];
    final batcher = TerminalOutputBatcher(
      maxPendingChars: 4,
      onFlush: flushed.add,
    );
    batcher.add('123456');
    expect(batcher.pendingLength, 4);
    batcher.clear();
    batcher.flushNow();

    expect(flushed, isEmpty);
    batcher.dispose();
  });
}
