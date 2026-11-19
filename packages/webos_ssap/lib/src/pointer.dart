import 'dart:convert';

import 'client.dart';
import 'errors.dart';
import 'logger.dart';
import 'transport.dart';

/// Button names accepted by the webOS pointer socket.
///
/// Exact support varies by model and generation; every name here still needs a
/// hardware checklist row before it is described as working.
abstract final class PointerButtons {
  static const String up = 'UP';
  static const String down = 'DOWN';
  static const String left = 'LEFT';
  static const String right = 'RIGHT';
  static const String enter = 'ENTER';
  static const String back = 'BACK';
  static const String home = 'HOME';
  static const String exit = 'EXIT';
  static const String info = 'INFO';
  static const String menu = 'MENU';
  static const String pause = 'PAUSE';
  static const String play = 'PLAY';
  static const String rewind = 'REWIND';
  static const String fastForward = 'FASTFORWARD';
}

/// Second WebSocket used for D-pad navigation, pointer moves and scrolling.
///
/// The socket path comes from `getPointerInputSocket` and is invalidated when
/// the main session drops, so [open] must be called again after every
/// reconnect.
class PointerInputChannel {
  PointerInputChannel({
    required this.client,
    required this.transports,
    this.policy = CertificatePolicy.native,
    this.logger = const SsapLogger(),
  });

  final SsapClient client;
  final TransportFactory transports;
  final CertificatePolicy policy;
  final SsapLogger logger;

  SsapTransport? _transport;

  bool get isOpen => _transport?.isConnected ?? false;

  Future<void> open({Uri? endpointOverride}) async {
    if (isOpen) return;
    final Map<String, dynamic> payload;
    try {
      payload = await client.requestPointerSocket();
    } on SsapError {
      rethrow;
    }
    final path = payload['socketPath'];
    if (path is! String || path.isEmpty) {
      throw const SsapError(
        SsapErrorKind.capability,
        'pointer_unsupported',
        'This TV did not provide a pointer input socket.',
        recoverable: false,
      );
    }
    final endpoint = endpointOverride ?? Uri.parse(path);
    final transport = transports(endpoint, policy: policy);
    await transport.connect();
    _transport = transport;
    logger.debug('pointer socket open');
  }

  Future<void> press(String button) => _send(<String, dynamic>{
        'type': 'button',
        'name': button,
      });

  Future<void> move({int dx = 0, int dy = 0}) => _send(<String, dynamic>{
        'type': 'move',
        'dx': dx,
        'dy': dy,
      });

  Future<void> scroll({int dx = 0, int dy = 0}) => _send(<String, dynamic>{
        'type': 'scroll',
        'dx': dx,
        'dy': dy,
      });

  Future<void> click() => _send(<String, dynamic>{'type': 'click'});

  Future<void> _send(Map<String, dynamic> message) async {
    final transport = _transport;
    if (transport == null || !transport.isConnected) {
      throw const SsapError(
        SsapErrorKind.closed,
        'pointer_closed',
        'The navigation channel is not open.',
      );
    }
    try {
      await transport.send(_encode(message));
    } on TransportException catch (e) {
      throw SsapError(
        SsapErrorKind.network,
        e.kind.name,
        e.message,
      );
    }
  }

  String _encode(Map<String, dynamic> message) => jsonEncode(message);

  Future<void> close() async {
    final transport = _transport;
    _transport = null;
    await transport?.close();
  }
}
