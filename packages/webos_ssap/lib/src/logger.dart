/// Minimal logger that never emits secrets.
///
/// Disabled by default. When a sink is supplied (tests, debug builds) every
/// message passes through [redact]: client keys, IPv4 addresses and long hex
/// strings are replaced before they can reach a file, console or crash report.
class SsapLogger {
  const SsapLogger({this.enabled = false, this.sink});

  final bool enabled;
  final void Function(String message)? sink;

  static final RegExp _clientKey = RegExp(r'"client-key"\s*:\s*"[^"]*"');
  static final RegExp _ipv4 = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b');
  static final RegExp _longHex = RegExp(r'\b[a-fA-F0-9]{32,}\b');

  void debug(String message) {
    if (!enabled) return;
    sink?.call(redact(message));
  }

  static String redact(String input) => input
      .replaceAll(_clientKey, '"client-key":"<redacted>"')
      .replaceAll(_ipv4, '<ip>')
      .replaceAll(_longHex, '<secret>');
}
