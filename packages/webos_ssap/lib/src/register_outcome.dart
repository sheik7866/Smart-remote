import 'errors.dart';

/// Result of the `register` handshake.
enum RegisterStatus {
  /// No previous key: the user approved the prompt on the TV and we got a new key.
  paired,

  /// A stored key was accepted without a prompt.
  restored,

  /// The user declined the prompt.
  denied,

  /// A stored key was rejected; the TV no longer recognises this client.
  keyRevoked,

  /// The TV never answered the prompt in time.
  timeout,

  /// Transport or protocol failure before pairing completed.
  failed,
}

class RegisterOutcome {
  const RegisterOutcome({
    required this.status,
    this.clientKey,
    this.error,
  });

  final RegisterStatus status;
  final String? clientKey;
  final SsapError? error;

  bool get isSuccess =>
      status == RegisterStatus.paired || status == RegisterStatus.restored;

  @override
  String toString() =>
      'RegisterOutcome(${status.name}${clientKey == null ? '' : ', key=<redacted>'})';
}
