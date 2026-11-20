/// Opt-in, local-only command latency tracking.
///
/// Nothing is uploaded and nothing identifies the TV or the user; this exists
/// so QA can record a number for checklist row 3.11. It is off by default and
/// only the last and worst samples are kept, in memory.
class LatencyTracker {
  LatencyTracker({this.enabled = false});

  bool enabled;

  int samples = 0;
  int? lastMs;
  int? worstMs;

  Future<T> measure<T>(Future<T> Function() action) async {
    if (!enabled) return action();
    final watch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      watch.stop();
      samples += 1;
      lastMs = watch.elapsedMilliseconds;
      final worst = worstMs;
      if (worst == null || watch.elapsedMilliseconds > worst) {
        worstMs = watch.elapsedMilliseconds;
      }
    }
  }

  void reset() {
    samples = 0;
    lastMs = null;
    worstMs = null;
  }
}
