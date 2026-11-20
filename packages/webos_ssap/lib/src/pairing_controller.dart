import 'dart:async';

import 'credential.dart';
import 'errors.dart';
import 'pairing.dart';

/// Step of the pairing flow.
///
/// [revoked] is transient: the stored key was rejected, it has been cleared,
/// and the controller immediately moves on to [awaitingApproval] and a fresh
/// prompt so the user is not stranded.
enum PairingPhase {
  /// Nothing attempted yet, or the credential was deliberately forgotten.
  idle,

  /// Opening the socket; with a stored key this is the silent restore attempt.
  connecting,

  /// `register` sent: the TV is showing (or about to show) its prompt.
  awaitingApproval,

  /// A live session backed by a stored key.
  paired,

  /// The user declined the prompt on the TV.
  denied,

  /// The TV did not answer the prompt in time.
  timedOut,

  /// The stored key was rejected by the TV; it has been deleted and re-pairing
  /// has started.
  revoked,

  /// Unreachable TV, transport failure or a protocol error.
  failed,
}

/// One immutable view of the pairing flow.
class PairingSnapshot {
  const PairingSnapshot(this.phase, {this.credential, this.error});

  final PairingPhase phase;

  /// Present from [PairingPhase.connecting] onwards when a credential exists,
  /// and on [PairingPhase.paired]. Never log [TvCredential.clientKey].
  final TvCredential? credential;

  /// Set for [PairingPhase.denied], [PairingPhase.timedOut],
  /// [PairingPhase.revoked] and [PairingPhase.failed].
  final SsapError? error;

  bool get isBusy =>
      phase == PairingPhase.connecting || phase == PairingPhase.awaitingApproval;

  /// Safe to log: neither the phase nor the credential rendering carries a key.
  @override
  String toString() =>
      'PairingSnapshot(${phase.name}${error == null ? '' : ', ${error!.code}'})';
}

/// Drives one TV through pairing, credential storage and key revocation.
///
/// Policy from architecture §6.1:
/// * a stored key is tried first and never prompts when the TV still knows it;
/// * a rejected key is deleted, the [PairingPhase.revoked] state is published,
///   and the TV is prompted once more automatically;
/// * a denial or timeout stores nothing;
/// * only one attempt runs at a time, so the TV never shows two prompts.
///
/// The controller owns the live [PairedTv]; call [forget] or [dispose] to close
/// it. Failures are reported through [current] rather than thrown, so the UI
/// can render the reason.
class PairingController {
  PairingController({required this.service, CredentialStore? store})
      : store = store ?? service.store ?? _missingStore();

  final PairingService service;

  /// Persistence for the key. Defaults to the store the service writes to, so
  /// reads, writes and deletes always address the same place.
  final CredentialStore store;

  final StreamController<PairingSnapshot> _states =
      StreamController<PairingSnapshot>.broadcast();

  PairingSnapshot _current = const PairingSnapshot(PairingPhase.idle);
  PairedTv? _active;
  Future<PairedTv?>? _attempt;
  String? _attemptHost;

  /// Every phase transition, starting before the first attempt.
  Stream<PairingSnapshot> get states => _states.stream;

  /// The latest transition.
  PairingSnapshot get current => _current;

  /// The connected TV, or null when not paired.
  PairedTv? get activeTv => _active;

  /// Connects to [host] and returns the live session, or null on failure.
  ///
  /// When no [port]/[secure] is supplied the stored credential decides the
  /// transport, because an LG key is only valid on the transport that issued
  /// it. While an attempt is in flight, a call for the same host returns that
  /// attempt; a call for a different host is ignored and returns null.
  Future<PairedTv?> connect({
    required String host,
    int? port,
    bool? secure,
  }) {
    final inFlight = _attempt;
    if (inFlight != null) {
      return _attemptHost == host
          ? inFlight
          : Future<PairedTv?>.value(null);
    }

    late final Future<PairedTv?> attempt;
    attempt = _connect(host: host, port: port, secure: secure).whenComplete(() {
      _attempt = null;
      _attemptHost = null;
    });
    _attempt = attempt;
    _attemptHost = host;
    return attempt;
  }

  Future<PairedTv?> _connect({
    required String host,
    int? port,
    bool? secure,
  }) async {
    TvCredential? stored;
    try {
      stored = await store.read(host);
    } on Object {
      // A broken keystore must not block pairing: fall back to a fresh prompt.
      // A failure to *write* after approval still surfaces as PairingPhase.failed.
      stored = null;
    }

    final resolvedPort = port ?? stored?.port;
    final resolvedSecure = secure ?? stored?.secure;

    _emit(PairingSnapshot(PairingPhase.connecting, credential: stored));

    try {
      if (stored == null) {
        _emit(const PairingSnapshot(PairingPhase.awaitingApproval));
        final tv = await service.pair(
          host: host,
          port: resolvedPort,
          secure: resolvedSecure,
        );
        return _paired(tv);
      }

      try {
        final tv = await service.pair(
          host: host,
          port: resolvedPort,
          secure: resolvedSecure,
          knownClientKey: stored.clientKey,
        );
        return _paired(tv);
      } on SsapError catch (error) {
        if (error.code != 'key_revoked') rethrow;

        // The TV forgot this remote. Clear the dead key before prompting, so a
        // crash mid-repair cannot leave a key that is known to be invalid.
        await store.delete(host);
        _emit(PairingSnapshot(PairingPhase.revoked, error: error));
        _emit(const PairingSnapshot(PairingPhase.awaitingApproval));
        final tv = await service.pair(
          host: host,
          port: resolvedPort,
          secure: resolvedSecure,
        );
        return _paired(tv);
      }
    } on SsapError catch (error) {
      _emit(PairingSnapshot(_phaseFor(error), error: error));
      return null;
    } on Object {
      _emit(const PairingSnapshot(
        PairingPhase.failed,
        error: SsapError(
          SsapErrorKind.unknown,
          'pairing_failed',
          'Pairing failed unexpectedly.',
        ),
      ));
      return null;
    }
  }

  PairedTv _paired(PairedTv tv) {
    _active = tv;
    _emit(PairingSnapshot(PairingPhase.paired, credential: tv.credential));
    return tv;
  }

  PairingPhase _phaseFor(SsapError error) {
    switch (error.code) {
      case 'pairing_denied':
        return PairingPhase.denied;
      case 'pairing_timeout':
        return PairingPhase.timedOut;
      case 'key_revoked':
        return PairingPhase.revoked;
      default:
        return error.kind == SsapErrorKind.auth
            ? PairingPhase.denied
            : PairingPhase.failed;
    }
  }

  /// Deletes the stored key, closes the session and returns to idle.
  ///
  /// Use for "forget this TV"; the next [connect] pairs from scratch.
  Future<void> forget(String host) async {
    await store.delete(host);
    final active = _active;
    _active = null;
    if (active != null) await active.dispose();
    _emit(const PairingSnapshot(PairingPhase.idle));
  }

  Future<void> dispose() async {
    final active = _active;
    _active = null;
    if (active != null) await active.dispose();
    await _states.close();
  }

  void _emit(PairingSnapshot snapshot) {
    _current = snapshot;
    if (!_states.isClosed) _states.add(snapshot);
  }
}

CredentialStore _missingStore() => throw ArgumentError.notNull('store');
