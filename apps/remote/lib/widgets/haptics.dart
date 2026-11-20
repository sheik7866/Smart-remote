import 'package:flutter/services.dart';

/// Wraps a tap so every control gives the same light confirmation.
///
/// Haptics are best-effort: platforms without a vibrator simply ignore them,
/// and tests run without a platform channel. Failures never block the command.
void Function() withHaptic(void Function() action) {
  return () {
    HapticFeedback.selectionClick().catchError((Object _) {});
    action();
  };
}
