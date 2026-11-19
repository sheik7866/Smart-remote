/// The credential for one TV.
///
/// The transport is part of the identity: LG honours a client key only on the
/// transport (and port) it was issued over, so a key paired on `wss://:3001`
/// is useless on `ws://:3000`.
class TvCredential {
  const TvCredential({
    required this.host,
    required this.port,
    required this.secure,
    required this.clientKey,
    this.modelName,
    this.fingerprint,
    this.lastSeen,
  });

  final String host;
  final int port;
  final bool secure;
  final String clientKey;
  final String? modelName;

  /// Certificate fingerprint captured at pairing time, for diagnostics only.
  final String? fingerprint;
  final DateTime? lastSeen;

  Uri get endpoint => Uri(
        scheme: secure ? 'wss' : 'ws',
        host: host,
        port: port,
        path: '/',
      );

  TvCredential copyWith({
    String? host,
    int? port,
    bool? secure,
    String? clientKey,
    String? modelName,
    String? fingerprint,
    DateTime? lastSeen,
  }) =>
      TvCredential(
        host: host ?? this.host,
        port: port ?? this.port,
        secure: secure ?? this.secure,
        clientKey: clientKey ?? this.clientKey,
        modelName: modelName ?? this.modelName,
        fingerprint: fingerprint ?? this.fingerprint,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  /// Never includes the key: this object is safe to log.
  @override
  String toString() =>
      'TvCredential(${endpoint.toString().replaceAll(RegExp(r'/$'), '')}, '
      'key=<redacted>)';
}

/// Platform-secure storage. Native implementations use Keychain/Keystore;
/// the browser implementation is intentionally absent (see architecture §8).
abstract class CredentialStore {
  Future<TvCredential?> read(String host);

  Future<void> write(TvCredential credential);

  Future<void> delete(String host);

  Future<List<TvCredential>> readAll();
}
