import 'dart:math';

/// Exponential backoff with jitter for reconnects.
///
/// Jitter is symmetric and bounded, so a room full of phones that lost the same
/// access point does not retry in lockstep. [delayFor] is pure apart from the
/// injected [Random], which makes the bounds testable without a clock.
class BackoffStrategy {
  BackoffStrategy({
    this.base = const Duration(milliseconds: 500),
    this.max = const Duration(seconds: 30),
    this.factor = 2.0,
    this.jitter = 0.2,
    Random? random,
  }) : _random = random ?? Random();

  final Duration base;
  final Duration max;
  final double factor;

  /// Fraction of the delay that may be added or removed, 0..1.
  final double jitter;
  final Random _random;

  /// Delay before attempt [attempt], where 0 is the first retry.
  Duration delayFor(int attempt) {
    final exponent = attempt < 0 ? 0 : attempt;
    final raw = base.inMilliseconds * pow(factor, exponent);
    final capped = min(raw.toDouble(), max.inMilliseconds.toDouble());
    final spread = capped * jitter.clamp(0, 1);
    final delta = (_random.nextDouble() * 2 - 1) * spread;
    final millis = (capped + delta).round();
    return Duration(milliseconds: millis < 0 ? 0 : millis);
  }
}
