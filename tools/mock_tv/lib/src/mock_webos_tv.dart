import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// How the mock answers the pairing prompt.
enum PairingBehaviour {
  /// Send the PROMPT response, then `registered` with a fresh key.
  accept,

  /// Answer with a 403, as if the user pressed Deny.
  deny,

  /// Show the prompt and never finish, so the client hits its own timeout.
  ignorePrompt,
}

/// How the mock reports volume.
enum VolumeMode {
  /// Normal TV: volume 0-100, absolute control works.
  absolute,

  /// ARC/eARC soundbar: the TV reports volume -1 and absolute control fails.
  arcExternal,
}

class MockTvConfig {
  MockTvConfig({
    this.pairing = PairingBehaviour.accept,
    this.volume = VolumeMode.absolute,
    this.secure = false,
    this.certificatePath,
    this.privateKeyPath,
    this.promptDelay = const Duration(milliseconds: 20),
    this.registrationDelay = Duration.zero,
    this.closeOnTurnOff = false,
    this.knownClientKey,
  });

  final PairingBehaviour pairing;
  final VolumeMode volume;
  final bool secure;
  final String? certificatePath;
  final String? privateKeyPath;

  /// Delay between the PROMPT response and `registered`.
  final Duration promptDelay;

  /// Delay before answering `register` at all.
  final Duration registrationDelay;

  /// Close all sockets when `system/turnOff` is received.
  final bool closeOnTurnOff;

  /// A key the TV already trusts.
  final String? knownClientKey;
}

class _ClientConnection {
  _ClientConnection(this.socket);

  final WebSocket socket;
  bool registered = false;
  String? clientKey;
  final Map<String, String> subscriptions = <String, String>{};
}

/// A fake LG webOS TV speaking just enough SSAP to exercise the client.
///
/// Every received frame is recorded in [requests] so tests can assert the exact
/// URIs and payloads that went over the wire.
class MockWebOsTv {
  MockWebOsTv(this.config);

  final MockTvConfig config;

  final List<Map<String, dynamic>> requests = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> pointerEvents = <Map<String, dynamic>>[];

  /// URIs that produce no response at all (client-side timeouts).
  final Set<String> silentUris = <String>{};

  /// URIs answered with 404.
  final Set<String> unsupportedUris = <String>{};

  /// Answer every command (not register) with 401.
  bool denyPermissions = false;

  /// Reply to the pointer-socket request without a `socketPath`.
  bool omitPointerSocket = false;

  int pairingPrompts = 0;
  int turnOffCount = 0;
  String? issuedClientKey;

  final List<_ClientConnection> _clients = <_ClientConnection>[];
  final List<WebSocket> _pointerSockets = <WebSocket>[];
  HttpServer? _server;
  String? _knownKey;
  bool _rejectStoredKeys = false;
  int _keyCounter = 0;
  int _volume = 12;
  bool _muted = false;

  int get port => _server?.port ?? 0;

  String get host => '127.0.0.1';

  bool get isSecure => config.secure;

  String get scheme => config.secure ? 'wss' : 'ws';

  String get wsEndpoint => '$scheme://$host:$port';

  Uri get wsUri => Uri.parse(wsEndpoint);

  List<String> get uris => <String>[
        for (final request in requests)
          if (request['uri'] is String) request['uri'] as String,
      ];

  /// Forgets every key: the next register with a stored key gets a 403.
  void revokeClientKeys() {
    _rejectStoredKeys = true;
    _knownKey = null;
  }

  Future<void> start({int port = 0}) async {
    if (config.secure) {
      final context = SecurityContext()
        ..useCertificateChain(config.certificatePath!)
        ..usePrivateKey(config.privateKeyPath!);
      _server = await HttpServer.bindSecure(host, port, context);
    } else {
      _server = await HttpServer.bind(host, port);
    }
    _server!.listen(_handleRequest);
    _knownKey = config.knownClientKey;
  }

  Future<void> stop() async {
    for (final socket in _pointerSockets) {
      await socket.close();
    }
    _pointerSockets.clear();
    for (final client in _clients) {
      await client.socket.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
  }

  /// Drops every client socket, simulating the TV going away.
  Future<void> dropClients() async {
    for (final client in _clients.toList(growable: false)) {
      await client.socket.close(WebSocketStatus.goingAway);
    }
    _clients.clear();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path == '/pointer') {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      _pointerSockets.add(socket);
      socket.listen(
        (dynamic data) {
          if (data is! String) return;
          try {
            final decoded = jsonDecode(data);
            if (decoded is Map<String, dynamic>) pointerEvents.add(decoded);
          } on FormatException {
            // ignore malformed pointer input
          }
        },
        onDone: () => _pointerSockets.remove(socket),
      );
      return;
    }

    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..headers.contentType = ContentType.html
        ..write('<html><body><h1>Mock LG webOS TV</h1></body></html>');
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    final client = _ClientConnection(socket);
    _clients.add(client);
    socket.listen(
      (dynamic data) {
        unawaited(_onFrame(client, data));
      },
      onDone: () {
        _clients.remove(client);
        for (final pointer in _pointerSockets) {
          unawaited(pointer.close());
        }
        _pointerSockets.clear();
      },
    );
  }

  Future<void> _onFrame(_ClientConnection client, dynamic data) async {
    if (data is! String) return;
    final Map<String, dynamic> frame;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      frame = decoded;
    } on FormatException {
      _sendError(client, null, '400 malformed frame', code: '400');
      return;
    }

    requests.add(frame);
    final id = frame['id']?.toString();
    final type = frame['type'];

    if (type == 'register') {
      final rawPayload = frame['payload'];
      await _handleRegister(
        client,
        id,
        rawPayload is Map<String, dynamic> ? rawPayload : <String, dynamic>{},
      );
      return;
    }

    if (!client.registered) {
      _sendError(client, id, '403 not registered', code: '403');
      return;
    }

    if (type == 'request' || type == 'subscribe') {
      _handleCommand(client, id, frame, subscribe: type == 'subscribe');
      return;
    }

    _sendError(client, id, '400 unknown message type', code: '400');
  }

  Future<void> _handleRegister(
    _ClientConnection client,
    String? id,
    Map<String, dynamic> payload,
  ) async {
    final provided = payload['client-key'];
    final key = provided is String ? provided : null;

    if (config.registrationDelay > Duration.zero) {
      await Future<void>.delayed(config.registrationDelay);
    }

    if (_rejectStoredKeys && key != null) {
      _sendError(client, id, '403 client key rejected', code: '403');
      return;
    }

    if (key != null && key == _knownKey) {
      client
        ..registered = true
        ..clientKey = key;
      _send(client, <String, dynamic>{
        'type': 'registered',
        'payload': <String, dynamic>{'client-key': key},
      });
      return;
    }

    switch (config.pairing) {
      case PairingBehaviour.deny:
        _sendError(client, id, '403 cancelled by user', code: '403');
      case PairingBehaviour.ignorePrompt:
        pairingPrompts += 1;
        _send(client, <String, dynamic>{
          'type': 'response',
          'id': id,
          'payload': <String, dynamic>{
            'pairingType': 'PROMPT',
            'returnValue': true,
          },
        });
      case PairingBehaviour.accept:
        pairingPrompts += 1;
        _send(client, <String, dynamic>{
          'type': 'response',
          'id': id,
          'payload': <String, dynamic>{
            'pairingType': 'PROMPT',
            'returnValue': true,
          },
        });
        if (config.promptDelay > Duration.zero) {
          await Future<void>.delayed(config.promptDelay);
        }
        if (client.socket.readyState != WebSocket.open) return;
        final newKey = 'mock-key-${++_keyCounter}';
        _knownKey = newKey;
        issuedClientKey = newKey;
        client
          ..registered = true
          ..clientKey = newKey;
        _send(client, <String, dynamic>{
          'type': 'registered',
          'payload': <String, dynamic>{'client-key': newKey},
        });
    }
  }

  void _handleCommand(
    _ClientConnection client,
    String? id,
    Map<String, dynamic> frame, {
    required bool subscribe,
  }) {
    final uri = frame['uri'];
    if (uri is! String) {
      _sendError(client, id, '400 missing uri', code: '400');
      return;
    }
    final rawPayload = frame['payload'];
    final payload =
        rawPayload is Map<String, dynamic> ? rawPayload : <String, dynamic>{};

    if (denyPermissions) {
      _sendError(client, id, '401 insufficient permissions', code: '401');
      return;
    }
    if (unsupportedUris.contains(uri) || silentUris.contains(uri)) {
      if (silentUris.contains(uri)) return;
      _sendError(client, id, '404 no such service or method', code: '404');
      return;
    }

    switch (uri) {
      case 'ssap://api/getServiceList':
        _send(client, <String, dynamic>{
          'type': 'response',
          'id': id,
          'payload': <String, dynamic>{
            'returnValue': true,
            'services': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'com.webos.service.networkinput',
                'version': '1.0.0',
              },
              <String, dynamic>{'name': 'tv', 'version': '1.0.0'},
              <String, dynamic>{
                'name': 'com.webos.service.tvpower',
                'version': '1.0.0',
              },
              <String, dynamic>{
                'name': 'com.webos.service.mediacontroller',
                'version': '1.0.0',
              },
            ],
          },
        });
        return;

      case 'ssap://audio/getVolume':
        if (subscribe) client.subscriptions[id!] = uri;
        _send(client, <String, dynamic>{
          'type': 'response',
          'id': id,
          'payload': <String, dynamic>{
            'returnValue': true,
            if (subscribe) 'subscribed': true,
            'volume': _reportedVolume,
            'muted': _muted,
            'changed': <String>[],
          },
        });
        return;

      case 'ssap://audio/volumeUp':
        _stepVolume(client, id, 1);
        return;

      case 'ssap://audio/volumeDown':
        _stepVolume(client, id, -1);
        return;

      case 'ssap://audio/setVolume':
        if (config.volume == VolumeMode.arcExternal) {
          _send(client, <String, dynamic>{
            'type': 'response',
            'id': id,
            'payload': <String, dynamic>{
              'returnValue': false,
              'errorText': 'volume is controlled by an external device',
            },
          });
          return;
        }
        final target = payload['volume'];
        if (target is num) _volume = target.toInt().clamp(0, 100);
        _sendOk(client, id);
        _notifyVolume();
        return;

      case 'ssap://audio/setMute':
        _muted = payload['mute'] == true;
        _sendOk(client, id);
        _notifyVolume();
        return;

      case 'ssap://system/turnOff':
        turnOffCount += 1;
        _sendOk(client, id);
        return;

      case 'ssap://com.webos.service.networkinput/getPointerInputSocket':
        _send(client, <String, dynamic>{
          'type': 'response',
          'id': id,
          'payload': <String, dynamic>{
            'returnValue': true,
            if (!omitPointerSocket)
              'socketPath': '$scheme://$host:$port/pointer',
          },
        });
        return;

      case 'ssap://tv/channelUp':
      case 'ssap://tv/channelDown':
      case 'ssap://system.launcher/launch':
      case 'ssap://media.controls/play':
      case 'ssap://media.controls/pause':
      case 'ssap://media.controls/stop':
        _sendOk(client, id);
        return;

      default:
        _sendError(client, id, '404 no such service or method', code: '404');
    }
  }

  int get _reportedVolume =>
      config.volume == VolumeMode.arcExternal ? -1 : _volume;

  void _stepVolume(_ClientConnection client, String? id, int delta) {
    if (config.volume == VolumeMode.absolute) {
      _volume = (_volume + delta).clamp(0, 100);
    }
    _sendOk(client, id);
    _notifyVolume();
  }

  void _notifyVolume() {
    for (final client in _clients) {
      client.subscriptions.forEach((subscriptionId, uri) {
        if (uri != 'ssap://audio/getVolume') return;
        _send(client, <String, dynamic>{
          'type': 'response',
          'id': subscriptionId,
          'payload': <String, dynamic>{
            'returnValue': true,
            'volume': _reportedVolume,
            'muted': _muted,
            'changed': <String>['volumeUp'],
          },
        });
      });
    }
  }

  void _sendOk(_ClientConnection client, String? id) {
    _send(client, <String, dynamic>{
      'type': 'response',
      'id': id,
      'payload': <String, dynamic>{'returnValue': true},
    });
  }

  void _sendError(_ClientConnection client, String? id, String message,
      {String? code}) {
    _send(client, <String, dynamic>{
      'type': 'error',
      'id': id,
      'error': message,
      'payload': <String, dynamic>{
        'errorText': message,
        if (code != null) 'errorCode': code,
      },
    });
  }

  void _send(_ClientConnection client, Map<String, dynamic> message) {
    if (client.socket.readyState == WebSocket.open) {
      client.socket.add(jsonEncode(message));
    }
  }
}
