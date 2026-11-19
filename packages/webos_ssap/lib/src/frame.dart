import 'dart:convert';

/// Thrown when a wire message cannot be understood as an SSAP frame.
class FrameFormatException implements Exception {
  FrameFormatException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'FrameFormatException: $message';
}

/// The `type` field of an SSAP message.
enum SsapMessageType {
  register,
  registered,
  request,
  response,
  error,
  subscribe,
  unknown,
}

/// A decoded SSAP frame.
///
/// Frames are single JSON objects in WebSocket text frames. There is no binary
/// framing and no length prefix (see docs/protocol-notes.md).
class SsapFrame {
  const SsapFrame({
    required this.type,
    this.id,
    this.uri,
    this.payload = const <String, dynamic>{},
    this.rawType,
    this.error,
  });

  final SsapMessageType type;
  final String? id;
  final String? uri;
  final Map<String, dynamic> payload;
  final String? rawType;

  /// Top-level `error` string used by some firmwares instead of payload fields.
  final String? error;

  String? get errorText =>
      payload['errorText'] as String? ?? error;

  String? get errorCode => payload['errorCode']?.toString();

  bool get returnValue => payload['returnValue'] != false;

  static SsapFrame decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw FrameFormatException('Message is not valid JSON', cause: e);
    }
    if (decoded is! Map<String, dynamic>) {
      throw FrameFormatException('Message is not a JSON object');
    }
    final typeName = decoded['type'];
    if (typeName is! String) {
      throw FrameFormatException('Message has no string "type" field');
    }
    final rawPayload = decoded['payload'];
    final payload = rawPayload is Map<String, dynamic>
        ? rawPayload
        : <String, dynamic>{};
    final rawId = decoded['id'];
    return SsapFrame(
      type: parseType(typeName),
      id: rawId?.toString(),
      uri: decoded['uri'] as String?,
      payload: payload,
      rawType: typeName,
      error: decoded['error'] as String?,
    );
  }

  static SsapMessageType parseType(String name) => switch (name) {
        'register' => SsapMessageType.register,
        'registered' => SsapMessageType.registered,
        'request' => SsapMessageType.request,
        'response' => SsapMessageType.response,
        'error' => SsapMessageType.error,
        'subscribe' => SsapMessageType.subscribe,
        _ => SsapMessageType.unknown,
      };

  static String encodeRequest({
    required String id,
    required String uri,
    Map<String, dynamic>? payload,
  }) =>
      jsonEncode(<String, dynamic>{
        'id': id,
        'type': 'request',
        'uri': uri,
        if (payload != null && payload.isNotEmpty) 'payload': payload,
      });

  static String encodeSubscribe({
    required String id,
    required String uri,
    Map<String, dynamic>? payload,
  }) =>
      jsonEncode(<String, dynamic>{
        'id': id,
        'type': 'subscribe',
        'uri': uri,
        'payload': <String, dynamic>{'subscribe': true, ...?payload},
      });

  static String encodeRegister({
    required String id,
    required Map<String, dynamic> manifest,
    String? clientKey,
    String pairingType = 'PROMPT',
    bool forcePairing = false,
  }) =>
      jsonEncode(<String, dynamic>{
        'id': id,
        'type': 'register',
        'payload': <String, dynamic>{
          'forcePairing': forcePairing,
          'pairingType': pairingType,
          'manifest': manifest,
          if (clientKey != null) 'client-key': clientKey,
        },
      });
}
