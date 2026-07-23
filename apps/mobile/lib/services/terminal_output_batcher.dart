import 'dart:async';

typedef TerminalOutputFlush = void Function(String output);

/// Coalesces high-frequency terminal frames before they reach the widget tree.
class TerminalOutputBatcher {
  TerminalOutputBatcher({
    required this.onFlush,
    this.interval = const Duration(milliseconds: 40),
    this.maxPendingChars = 65536,
  }) : assert(maxPendingChars > 0);

  final TerminalOutputFlush onFlush;
  final Duration interval;
  final int maxPendingChars;
  Timer? _timer;
  String _pending = '';

  int get pendingLength => _pending.length;

  void add(String output) {
    if (output.isEmpty) return;
    _pending += output;
    if (_pending.length > maxPendingChars) {
      _pending = _pending.substring(_pending.length - maxPendingChars);
    }
    _timer ??= Timer(interval, flushNow);
  }

  void flushNow() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final output = _pending;
    _pending = '';
    onFlush(output);
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending = '';
  }

  void dispose() {
    clear();
  }
}
