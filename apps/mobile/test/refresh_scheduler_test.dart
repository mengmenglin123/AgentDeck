import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:huanhermes_app/services/refresh_scheduler.dart';

void main() {
  test('prevents overlapping async refresh tasks', () async {
    final first = Completer<void>();
    var calls = 0;
    final scheduler = RefreshScheduler(onTick: () async {
      calls++;
      await first.future;
    });

    final running = scheduler.runNow();
    await scheduler.runNow();
    expect(calls, 1);
    expect(scheduler.running, isTrue);
    first.complete();
    await running;
    expect(scheduler.running, isFalse);
    scheduler.dispose();
  });

  test('reconfigures interval and stops after pause', () async {
    var calls = 0;
    final scheduler = RefreshScheduler(onTick: () => calls++);
    scheduler.configure(
      enabled: true,
      interval: const Duration(milliseconds: 5),
    );
    await Future<void>.delayed(const Duration(milliseconds: 22));
    expect(calls, greaterThan(0));
    scheduler.pause();
    final pausedAt = calls;
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(calls, pausedAt);
    scheduler.dispose();
  });
}
