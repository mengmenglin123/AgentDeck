class TerminalReconnectPolicy {
  const TerminalReconnectPolicy({
    this.maxAttempts = 5,
    this.maxDelay = const Duration(seconds: 15),
  }) : assert(maxAttempts >= 0);

  final int maxAttempts;
  final Duration maxDelay;

  bool canRetry(int completedAttempts) => completedAttempts < maxAttempts;

  Duration delayForAttempt(int attempt) {
    if (attempt <= 0) return Duration.zero;
    final exponent = (attempt - 1).clamp(0, 20).toInt();
    final seconds = 1 << exponent;
    final delay = Duration(seconds: seconds);
    return delay > maxDelay ? maxDelay : delay;
  }
}
