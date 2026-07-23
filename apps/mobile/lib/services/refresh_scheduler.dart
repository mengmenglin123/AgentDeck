import 'dart:async';

typedef RefreshTask = FutureOr<void> Function();

class RefreshScheduler {
  RefreshScheduler({required RefreshTask onTick}) : _onTick = onTick;

  final RefreshTask _onTick;
  Timer? _timer;
  Duration? _interval;
  bool _enabled = false;
  bool _running = false;
  bool _disposed = false;

  bool get active => _timer?.isActive == true;
  bool get running => _running;
  bool get enabled => _enabled;
  Duration? get interval => _interval;

  void configure({required bool enabled, required Duration interval}) {
    if (_disposed) return;
    final shouldRun = enabled && interval > Duration.zero;
    if (_enabled == shouldRun &&
        _interval == interval &&
        (shouldRun ? active : !active)) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _enabled = shouldRun;
    _interval = interval;
    if (shouldRun) {
      _timer = Timer.periodic(interval, (_) => unawaited(runNow()));
    }
  }

  Future<void> runNow() async {
    if (_disposed || _running) return;
    _running = true;
    try {
      await _onTick();
    } finally {
      _running = false;
    }
  }

  void pause() {
    configure(enabled: false, interval: _interval ?? Duration.zero);
  }

  void dispose() {
    _disposed = true;
    _enabled = false;
    _timer?.cancel();
    _timer = null;
  }
}
