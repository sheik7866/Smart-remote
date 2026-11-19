import 'dart:async';

import 'errors.dart';
import 'frame.dart';
import 'logger.dart';
import 'register_outcome.dart';
import 'transport.dart';

/// Time budgets for the different SSAP interactions.
class SsapTimeouts {
  const SsapTimeouts({
    this.request = const Duration(seconds: 5),
    this.pairing = const Duration(seconds: 75),
    this.subscription = const Duration(seconds: 5),
  });

  /// One request → response round trip.
  final Duration request;

  /// Whole pairing interaction. Covers the TV's on-screen prompt (~60 s) plus
  /// the `registered` frame, so it must be longer than the prompt window.
  final Duration pairing;

  /// Time allowed for the TV to acknowledge a subscription.
  final Duration subscription;
}

class _Pending {
  _Pending(this.completer, this.uri);

  final Completer<Map<String, dynamic>> completer;
  final String uri;
}

/// A live subscription. SSAP has no unsubscribe verb that is reliable across
/// generations, so [cancel] stops delivery locally and the TV's pushes are
/// dropped.
class SsapSubscription {
  SsapSubscription({
    required this.uri,
    required this.id,
    required Stream<Map<String, dynamic>> updates,
    required Future<void> Function() onCancel,
  })  : _updates = updates,
        _onCancel = onCancel;

  final String uri;
  final String id;
  final Stream<Map<String, dynamic>> _updates;
  final Future<void> Function() _onCancel;

  Stream<Map<String, dynamic>> get updates => _updates;

  Future<void> cancel() => _onCancel();
}

/// One multiplexed SSAP connection: register, requests, subscriptions.
///
/// All calls fail with [SsapError]; nothing leaks a raw socket exception.
class SsapSession {
  SsapSession({
    required this.transport,
    SsapLogger logger = const SsapLogger(),
    this.timeouts = const SsapTimeouts(),
  }) : _logger = logger;

  final SsapTransport transport;
  final SsapTimeouts timeouts;
  final SsapLogger _logger;

  final Map<String, _Pending> _pending = <String, _Pending>{};
  final Map<String, StreamController<Map<String, dynamic>>> _subscriptions =
      <String, StreamController<Map<String, dynamic>>>{};
  final StreamController<SsapFrame> _frames =
      StreamController<SsapFrame>.broadcast();

  StreamSubscription<String>? _wire;
  Completer<RegisterOutcome>? _register;
  String? _registerId;
  String? _providedKey;
  bool _promptSeen = false;
  bool _open = false;
  int _counter = 0;

  /// Frames dropped because they were not valid SSAP JSON.
  int droppedFrames = 0;

  /// Responses whose request had already timed out.
  int lateResponses = 0;

  bool get isOpen => _open;
  int get pendingRequests => _pending.length;
  int get activeSubscriptions => _subscriptions.length;

  /// Every decoded frame, for diagnostics and tests. Broadcast: no buffering.
  Stream<SsapFrame> get frames => _frames.stream;

  String _nextId(String prefix) {
    _counter += 1;
    return '${prefix}_$_counter';
  }

  Future<void> connect() async {
    if (_open) return;
    await transport.connect();
    _open = true;
    _wire = transport.messages.listen(
      _onMessage,
      onError: (Object error) {
        _logger.debug('transport error: ${SsapLogger.redact('$error')}');
      },
      onDone: _failAllPending,
    );
  }

  /// Sends `register` and waits for the TV's decision.
  ///
  /// Passing [clientKey] requests a silent restore; the TV either accepts it
  /// (`restored`) or rejects it (`keyRevoked`). Without a key the TV shows its
  /// approval prompt and the outcome is `paired` or `denied`.
  Future<RegisterOutcome> register({
    required Map<String, dynamic> manifest,
    String? clientKey,
    String pairingType = 'PROMPT',
  }) async {
    if (!_open) {
      throw SsapError.closed();
    }
    final completer = Completer<RegisterOutcome>();
    _register = completer;
    _registerId = _nextId('register');
    _providedKey = clientKey;
    _promptSeen = false;

    final timer = Timer(timeouts.pairing, () {
      if (completer.isCompleted) return;
      _register = null;
      completer.complete(RegisterOutcome(
        status: RegisterStatus.timeout,
        error: SsapError(
          SsapErrorKind.auth,
          'pairing_timeout',
          'The TV did not confirm pairing in time.',
        ),
      ));
    });

    try {
      await transport.send(SsapFrame.encodeRegister(
        id: _registerId!,
        manifest: manifest,
        clientKey: clientKey,
        pairingType: pairingType,
      ));
      return await completer.future;
    } on TransportException catch (e) {
      _register = null;
      return RegisterOutcome(
        status: RegisterStatus.failed,
        error: SsapError(SsapErrorKind.transport, e.kind.name, e.message),
      );
    } finally {
      timer.cancel();
    }
  }

  Future<Map<String, dynamic>> request(
    String uri, {
    Map<String, dynamic>? payload,
    Duration? timeout,
  }) async {
    if (!_open) {
      throw SsapError.closed(uri: uri);
    }
    final limit = timeout ?? timeouts.request;
    final id = _nextId('request');
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = _Pending(completer, uri);

    final timer = Timer(limit, () {
      final pending = _pending.remove(id);
      if (pending == null || pending.completer.isCompleted) return;
      pending.completer.completeError(SsapError.timeout(uri, limit));
    });

    try {
      await transport.send(
        SsapFrame.encodeRequest(id: id, uri: uri, payload: payload),
      );
      return await completer.future;
    } on TransportException catch (e) {
      throw SsapError(SsapErrorKind.network, e.kind.name, e.message, uri: uri);
    } finally {
      timer.cancel();
      _pending.remove(id);
    }
  }

  Future<SsapSubscription> subscribe(
    String uri, {
    Map<String, dynamic>? payload,
    Duration? timeout,
  }) async {
    if (!_open) {
      throw SsapError.closed(uri: uri);
    }
    final limit = timeout ?? timeouts.subscription;
    final id = _nextId('sub');
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    final completer = Completer<Map<String, dynamic>>();
    _subscriptions[id] = controller;
    _pending[id] = _Pending(completer, uri);

    final timer = Timer(limit, () {
      final pending = _pending.remove(id);
      if (pending == null || pending.completer.isCompleted) return;
      pending.completer.completeError(SsapError.timeout(uri, limit));
    });

    try {
      await transport.send(
        SsapFrame.encodeSubscribe(id: id, uri: uri, payload: payload),
      );
      await completer.future;
      return SsapSubscription(
        uri: uri,
        id: id,
        updates: controller.stream,
        onCancel: () async {
          _subscriptions.remove(id);
          if (!controller.isClosed) await controller.close();
        },
      );
    } on TransportException catch (e) {
      throw SsapError(SsapErrorKind.network, e.kind.name, e.message, uri: uri);
    } catch (_) {
      _pending.remove(id);
      _subscriptions.remove(id);
      if (!controller.isClosed) await controller.close();
      rethrow;
    } finally {
      timer.cancel();
    }
  }

  void _onMessage(String raw) {
    final SsapFrame frame;
    try {
      frame = SsapFrame.decode(raw);
    } on FrameFormatException catch (e) {
      droppedFrames += 1;
      _logger.debug('dropped malformed frame: ${e.message}');
      return;
    }
    _frames.add(frame);

    switch (frame.type) {
      case SsapMessageType.registered:
        _onRegistered(frame);
      case SsapMessageType.response:
        _onResponse(frame);
      case SsapMessageType.error:
        _onError(frame);
      default:
        _logger.debug('ignored frame type ${frame.rawType}');
    }
  }

  void _onRegistered(SsapFrame frame) {
    final completer = _register;
    if (completer == null || completer.isCompleted) {
      _logger.debug('registered frame with no pending register');
      return;
    }
    _register = null;
    final key = frame.payload['client-key'] as String?;
    final restored = _providedKey != null && !_promptSeen;
    completer.complete(RegisterOutcome(
      status: restored ? RegisterStatus.restored : RegisterStatus.paired,
      clientKey: key,
    ));
  }

  void _onResponse(SsapFrame frame) {
    final id = frame.id;
    if (id == null) return;

    // The prompt notification arrives as a response before `registered`.
    if (frame.payload['pairingType'] == 'PROMPT') {
      _promptSeen = true;
      return;
    }

    final pending = _pending.remove(id);
    if (pending != null) {
      if (!pending.completer.isCompleted) {
        pending.completer.complete(frame.payload);
      }
      return;
    }

    final subscription = _subscriptions[id];
    if (subscription != null && !subscription.isClosed) {
      subscription.add(frame.payload);
      return;
    }

    lateResponses += 1;
    _logger.debug('late response for $id dropped');
  }

  void _onError(SsapFrame frame) {
    final id = frame.id;
    final pending = id == null ? null : _pending.remove(id);
    if (pending != null) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          SsapError.fromFrame(frame, uri: pending.uri),
        );
      }
      return;
    }

    final register = _register;
    if (register != null && !register.isCompleted && id == _registerId) {
      _register = null;
      final revoked = _providedKey != null;
      final error = revoked
          ? const SsapError(
              SsapErrorKind.auth,
              'key_revoked',
              'The TV no longer recognises this client. Pair again.',
            )
          : SsapError.fromFrame(frame);
      register.complete(RegisterOutcome(
        status:
            revoked ? RegisterStatus.keyRevoked : RegisterStatus.denied,
        error: error,
      ));
      return;
    }

    final subscription = id == null ? null : _subscriptions[id];
    if (subscription != null && !subscription.isClosed) {
      subscription.addError(SsapError.fromFrame(frame));
      return;
    }
    _logger.debug('unhandled error frame for $id');
  }

  void _failAllPending() {
    _open = false;
    final pending = _pending.values.toList(growable: false);
    _pending.clear();
    for (final entry in pending) {
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(SsapError.closed(uri: entry.uri));
      }
    }

    final register = _register;
    _register = null;
    if (register != null && !register.isCompleted) {
      register.complete(RegisterOutcome(
        status: RegisterStatus.failed,
        error: SsapError.closed(),
      ));
    }

    for (final controller in _subscriptions.values) {
      if (!controller.isClosed) {
        controller.addError(SsapError.closed());
        controller.close();
      }
    }
    _subscriptions.clear();
    if (!_frames.isClosed) _frames.close();
  }

  Future<void> close() async {
    if (_open) _failAllPending();
    await _wire?.cancel();
    _wire = null;
    await transport.close();
    if (!_frames.isClosed) await _frames.close();
  }
}
