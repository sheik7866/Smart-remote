import 'dart:math';

import 'package:remote_core/remote_core.dart';
import 'package:test/test.dart';

void main() {
  test('grows exponentially and caps at max', () {
    final backoff = BackoffStrategy(
      base: const Duration(milliseconds: 500),
      max: const Duration(seconds: 3),
      factor: 2,
      jitter: 0,
    );
    expect(backoff.delayFor(0), const Duration(milliseconds: 500));
    expect(backoff.delayFor(1), const Duration(milliseconds: 1000));
    expect(backoff.delayFor(2), const Duration(milliseconds: 2000));
    expect(backoff.delayFor(3), const Duration(seconds: 3));
    expect(
      backoff.delayFor(10),
      const Duration(seconds: 3),
      reason: 'a long outage must not grow the delay without bound',
    );
  });

  test('jitter stays inside the documented bounds', () {
    final backoff = BackoffStrategy(
      base: const Duration(milliseconds: 1000),
      max: const Duration(seconds: 30),
      factor: 2,
      jitter: 0.2,
      random: Random(7),
    );
    for (var attempt = 0; attempt < 8; attempt++) {
      final nominal = min(1000 * pow(2, attempt), 30000);
      final delay = backoff.delayFor(attempt).inMilliseconds;
      expect(delay, greaterThanOrEqualTo((nominal * 0.8).floor()));
      expect(delay, lessThanOrEqualTo((nominal * 1.2).ceil()));
    }
  });

  test('a negative attempt is treated as the first retry', () {
    final backoff = BackoffStrategy(
      base: const Duration(milliseconds: 250),
      jitter: 0,
    );
    expect(backoff.delayFor(-3), const Duration(milliseconds: 250));
  });

  test('jitter never produces a negative delay', () {
    final backoff = BackoffStrategy(
      base: const Duration(milliseconds: 1),
      jitter: 1,
      random: Random(1),
    );
    expect(backoff.delayFor(0).inMilliseconds, greaterThanOrEqualTo(0));
  });
}
