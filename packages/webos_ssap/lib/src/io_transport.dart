import 'dart:async';
import 'dart:io';

import 'logger.dart';
import 'transport.dart';

/// `dart:io` WebSocket transport for native platforms.
class IoWebSocketTransport implements SsapTransport {
  IoWebSocketTransport(
    Uri endpoint, {
    CertificatePolicy policy = const CertificatePolicy(),
    this.connectTimeout = const Duration(seconds: 8),
    SsapLogger logger = const SsapLogger(),
  })  : _endpoint = endpoint,
        _policy = policy,
        _logger = logger;

  final Uri _endpoint;
  final CertificatePolicy _policy;
  final Duration connectTimeout;
  final SsapLogger _logger;

  final StreamController<String> _messages = StreamController<String>();
  WebSocket? _socket;
  HttpClient? _client;
  String? _fingerprint;

  @override
  Uri get endpoint => _endpoint;

  @override
  String? get certificateFingerprint => _fingerprint;

  @override
  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> connect() async {
    if (isConnected) return;
    if (_endpoint.scheme != 'ws' && _endpoint.scheme != 'wss') {
      throw TransportException(
        TransportErrorKind.unsupported,
        'Unsupported URL scheme "${_endpoint.scheme}".',
        endpoint: _endpoint,
      );
    }

    final client = HttpClient()..connectionTimeout = connectTimeout;
    if (_endpoint.scheme == 'wss' && _policy.acceptSelfSigned) {
      client.badCertificateCallback = (cert, host, port) {
        _fingerprint = _hex(cert.sha1);
        _logger.debug('accepted self-signed certificate for $host:$port');
        return true;
      };
    }
    _client = client;

    try {
      final socket = await WebSocket.connect(
        _endpoint.toString(),
        customClient: client,
        compression: CompressionOptions.compressionOff,
      ).timeout(connectTimeout);
      _socket = socket;
      socket.listen(
        (dynamic data) {
          if (data is String) {
            _messages.add(data);
          } else {
            _logger.debug('ignored non-text frame');
          }
        },
        onError: (Object error) {
          _logger.debug('websocket error: $error');
          if (!_messages.isClosed) {
            _messages.addError(TransportException(
              TransportErrorKind.closed,
              'The socket failed.',
              cause: error,
              endpoint: _endpoint,
            ));
          }
        },
        onDone: () {
          _socket = null;
          // Not awaited: a single-subscription controller with no listener
          // never completes its close future, which would deadlock callers.
          if (!_messages.isClosed) unawaited(_messages.close());
        },
        cancelOnError: false,
      );
    } on TimeoutException catch (e) {
      client.close(force: true);
      throw TransportException(
        TransportErrorKind.timeout,
        'Connecting to the TV timed out.',
        cause: e,
        endpoint: _endpoint,
      );
    } on HandshakeException catch (e) {
      client.close(force: true);
      throw TransportException(
        TransportErrorKind.tlsRejected,
        "The TV's certificate was rejected.",
        cause: e,
        endpoint: _endpoint,
      );
    } on SocketException catch (e) {
      client.close(force: true);
      throw TransportException(
        TransportErrorKind.unreachable,
        'The TV is not reachable on this network.',
        cause: e,
        endpoint: _endpoint,
      );
    } on WebSocketException catch (e) {
      client.close(force: true);
      throw TransportException(
        TransportErrorKind.unreachable,
        'The TV refused the WebSocket connection.',
        cause: e,
        endpoint: _endpoint,
      );
    }
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  @override
  Future<void> send(String frame) async {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw TransportException(
        TransportErrorKind.closed,
        'The connection to the TV is closed.',
        endpoint: _endpoint,
      );
    }
    socket.add(frame);
  }

  @override
  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    await socket?.close(WebSocketStatus.normalClosure);
    if (!_messages.isClosed) unawaited(_messages.close());
    _client?.close(force: true);
  }
}
