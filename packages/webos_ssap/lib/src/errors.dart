import 'frame.dart';

/// Broad failure category, mapped to user-facing copy by the app layer.
enum SsapErrorKind {
  network,
  transport,
  auth,
  protocol,
  capability,
  timeout,
  closed,
  malformed,
  unknown,
}

/// A typed protocol failure. Nothing in this package throws raw exceptions
/// across the API boundary; callers get an [SsapError] with a stable code.
class SsapError implements Exception {
  const SsapError(
    this.kind,
    this.code,
    this.message, {
    this.uri,
    this.recoverable = true,
  });

  final SsapErrorKind kind;

  /// Stable machine code, e.g. `pairing_denied`, `key_revoked`, `unknown_uri`.
  final String code;
  final String message;
  final String? uri;
  final bool recoverable;

  static SsapError closed({String? uri}) => SsapError(
        SsapErrorKind.closed,
        'closed',
        'The connection to the TV is closed.',
        uri: uri,
      );

  static SsapError timeout(String uri, Duration limit) => SsapError(
        SsapErrorKind.timeout,
        'timeout',
        'The TV did not answer $uri within ${limit.inMilliseconds} ms.',
        uri: uri,
      );

  /// Maps a TV `error` frame. LG firmware is inconsistent: the reason may live
  /// in `payload.errorCode`, `payload.errorText` or a top-level `error`.
  factory SsapError.fromFrame(SsapFrame frame, {String? uri}) {
    final code = frame.errorCode ?? '';
    final text = frame.errorText ?? 'The TV returned an error.';
    final haystack = '$code $text'.toLowerCase();

    if (haystack.contains('403') || haystack.contains('cancel')) {
      return SsapError(
        SsapErrorKind.auth,
        'pairing_denied',
        'The TV declined the request.',
        uri: uri,
        recoverable: true,
      );
    }
    if (haystack.contains('401') || haystack.contains('permission')) {
      return SsapError(
        SsapErrorKind.protocol,
        'permission_denied',
        'This app is not permitted to control that on this TV.',
        uri: uri,
        recoverable: false,
      );
    }
    if (haystack.contains('404') ||
        haystack.contains('no such') ||
        haystack.contains('not exist')) {
      return SsapError(
        SsapErrorKind.capability,
        'unknown_uri',
        'This TV does not support that command.',
        uri: uri,
        recoverable: false,
      );
    }
    if (haystack.contains('500') || haystack.contains('application error')) {
      return SsapError(
        SsapErrorKind.protocol,
        'tv_error',
        'The TV reported an internal error.',
        uri: uri,
        recoverable: true,
      );
    }
    return SsapError(
      SsapErrorKind.protocol,
      'tv_error',
      text,
      uri: uri,
    );
  }

  @override
  String toString() => 'SsapError($kind/$code): $message';
}
