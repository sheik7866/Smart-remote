/// Why a transport-level operation failed.
enum TransportErrorKind {
  unreachable,
  timeout,
  tlsRejected,
  closed,
  unsupported,
}

class TransportException implements Exception {
  const TransportException(
    this.kind,
    this.message, {
    this.cause,
    this.endpoint,
  });

  final TransportErrorKind kind;
  final String message;
  final Object? cause;
  final Uri? endpoint;

  @override
  String toString() =>
      'TransportException(${kind.name}): $message${endpoint == null ? '' : ' [$endpoint]'}';
}

/// How the TV's TLS certificate is treated.
///
/// LG webOS serves `wss://:3001` with a self-signed certificate issued to an
/// internal hostname, so native clients must accept it. That is a deliberate,
/// documented weakening: the fingerprint is exposed for trust-on-first-use
/// diagnostics, and a strict policy exists for tests and for any future
/// bridge that terminates TLS properly.
class CertificatePolicy {
  const CertificatePolicy({this.acceptSelfSigned = true});

  final bool acceptSelfSigned;

  static const CertificatePolicy native = CertificatePolicy();
  static const CertificatePolicy strict =
      CertificatePolicy(acceptSelfSigned: false);
}

/// A bidirectional line of SSAP frames.
abstract class SsapTransport {
  Future<void> connect();

  Future<void> send(String frame);

  /// Decoded-by-nobody text frames. Single-subscriber; the session owns it.
  Stream<String> get messages;

  Future<void> close();

  bool get isConnected;

  Uri get endpoint;

  /// SHA-1 of the peer certificate when TLS was used, otherwise null.
  ///
  /// `dart:io` only exposes SHA-1 on [X509Certificate]; this is a diagnostic
  /// value for change detection, not a security guarantee.
  String? get certificateFingerprint;
}

/// Builds a transport for an endpoint. Injected so pairing and pointer input
/// can share policy without the caller knowing about `dart:io`.
typedef TransportFactory = SsapTransport Function(
  Uri endpoint, {
  CertificatePolicy policy,
});
