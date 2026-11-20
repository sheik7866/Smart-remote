import 'dart:async';

import 'package:webos_ssap/webos_ssap.dart';

import 'backoff.dart';
import 'discovery.dart';
import 'latency.dart';
import 'models.dart';

/// Buttons the remote can send.
///
/// The protocol's button names stay inside this package: the UI asks for
/// [RemoteKey.ok], never for the string `ENTER`.
enum RemoteKey {
  up,
  down,
  left,
  right,
  ok,
  back,
  home,
  info,
  menu,
  play,
  pause,
  rewind,
  fastForward,
  exit,
}

/// Drives one TV: discovery, pairing, capabilities, commands and reconnects.
///
/// The UI consumes [states] and never imports the protocol package. Every
/// failure is reported through the snapshot instead of thrown, so a screen
/// always has something true to say.
class RemoteController {
  RemoteController({
    required this.pairing,
    required this.transports,
    required this.discovery,
    BackoffStrategy? backoff,
    LatencyTracker? latency,
    this.reconnectEnabled = true,
  })  : _backoff = backoff ?? BackoffStrategy(),
        latency = latency ?? LatencyTracker() {
    _pairingSubscription = pairing.states.listen(_onPairingState);
  }

  final PairingController pairing;

  /// Used to open the pointer socket, which lives on its own connection.
  final TransportFactory transports;

  final RemoteDiscovery discovery;
  final LatencyTracker latency;

  /// When false, a dropped connection is reported but not retried.
  final bool reconnectEnabled;

  final BackoffStrategy _backoff;
  final StreamController<RemoteSnapshot> _states =
      StreamController<RemoteSnapshot>.broadcast();

  RemoteSnapshot _current = const RemoteSnapshot();
  PairedTv? _tv;
  TvDevice? _desired;
  StreamSubscription<PairingSnapshot>? _pairingSubscription;
  StreamSubscription<SsapFrame>? _framesSubscription;
  SsapSubscription? _volumeSubscription;
  StreamSubscription<Map<String, dynamic>>? _volumeUpdates;
  PointerInputChannel? _pointer;

  Timer? _reconnectTimer;
  Timer? _holdTimer;
  bool _holdInFlight = false;
  int _holdDirection = 0;
  int _reconnectAttempts = 0;
  bool _connecting = false;
  bool _foreground = true;
  bool _manualDisconnect = false;
  bool _wantConnection = false;
  bool _disposed = false;

  /// Every state change, starting with the initial idle snapshot.
  Stream<RemoteSnapshot> get states => _states.stream;

  RemoteSnapshot get snapshot => _current;

  bool get isForeground => _foreground;

  bool get discoverySupported => discovery.isSupported;

  String? get discoveryUnsupportedReason => discovery.unsupportedReason;

  /// Runs one discovery sweep. Empty results are reported as guidance, never
  /// as an invisible failure.
  Future<void> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_disposed) return;
    if (!discovery.isSupported) {
      _set(_current.copyWith(
        status: RemoteStatus.idle,
        hasSearched: true,
        discovered: const <DiscoveredTv>[],
        error: discovery.unsupportedReason,
      ));
      return;
    }

    _set(_current.copyWith(
      status: RemoteStatus.discovering,
      clearError: true,
      clearCommandError: true,
    ));
    try {
      final devices = await discovery.search(timeout: timeout);
      if (_disposed) return;
      _set(_current.copyWith(
        status: RemoteStatus.idle,
        discovered: devices,
        hasSearched: true,
        error: devices.isEmpty
            ? 'No LG TV answered. Check that the TV is on, on the same '
                'network, and that your access point allows devices to see '
                'each other.'
            : null,
        clearError: devices.isNotEmpty,
      ));
    } on DiscoveryFailure catch (failure) {
      _set(_current.copyWith(
        status: RemoteStatus.idle,
        hasSearched: true,
        discovered: const <DiscoveredTv>[],
        error: failure.message,
      ));
    } on Object {
      _set(_current.copyWith(
        status: RemoteStatus.idle,
        hasSearched: true,
        discovered: const <DiscoveredTv>[],
        error: 'Discovery failed. Enter the TV address manually.',
      ));
    }
  }

  Future<void> connect(DiscoveredTv tv) => connectHost(
        tv.host,
        name: tv.displayName,
        modelName: tv.modelName,
      );

  /// Connects to [host], or restores the stored key for it.
  Future<void> connectHost(
    String host, {
    int? port,
    bool? secure,
    String? name,
    String? modelName,
  }) async {
    final trimmed = host.trim();
    if (trimmed.isEmpty) {
      _set(_current.copyWith(
        commandError: 'Enter the TV IP address first.',
      ));
      return;
    }

    _desired = TvDevice(
      host: trimmed,
      port: port,
      secure: secure,
      name: name,
      modelName: modelName,
    );
    _manualDisconnect = false;
    _wantConnection = true;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _connectOnce(_desired!);
  }

  /// Stops reconnecting and closes the session, keeping the stored key.
  Future<void> disconnect() async {
    _manualDisconnect = true;
    _wantConnection = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    await _closeSession();
    _set(_current.copyWith(
      status: RemoteStatus.idle,
      clearDevice: true,
      clearVolume: true,
      capabilities: const RemoteCapabilities(),
      clearError: true,
      clearCommandError: true,
      clearReconnectAttempt: true,
      assembling: false,
    ));
  }

  /// Deletes the stored key and returns to the no-TV state.
  Future<void> forget() async {
    final device = _current.device ?? _desired;
    _manualDisconnect = true;
    _wantConnection = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    if (device != null) {
      await pairing.forget(device.host);
    }
    await _closeSession();
    _set(_current.copyWith(
      status: RemoteStatus.idle,
      clearDevice: true,
      clearVolume: true,
      capabilities: const RemoteCapabilities(),
      clearError: true,
      clearCommandError: true,
      clearReconnectAttempt: true,
      assembling: false,
    ));
  }

  /// Pauses reconnect attempts while the app is backgrounded, and retries
  /// immediately on return.
  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (!value) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      return;
    }
    if (_wantConnection &&
        !_manualDisconnect &&
        _tv == null &&
        _desired != null) {
      _reconnectAttempts = 0;
      unawaited(_attemptReconnect());
    }
  }

  Future<void> volumeUp() => _clientCommand((client) => client.volumeUp());

  Future<void> volumeDown() => _clientCommand((client) => client.volumeDown());

  /// Sets an exact volume, or explains why it is unavailable on this TV.
  Future<void> setVolume(int volume) async {
    final reason = _current.capabilities.reasonFor(RemoteControl.volumeSlider);
    if (reason != null) {
      _set(_current.copyWith(commandError: reason));
      return;
    }
    await _clientCommand((client) => client.setVolume(volume));
  }

  /// Flips mute using the last known state and reconciles if the TV refuses.
  Future<void> toggleMute() async {
    final target = !_current.muted;
    _set(_current.copyWith(muted: target));
    final ok = await _clientCommand((client) => client.setMute(target));
    if (!ok) _set(_current.copyWith(muted: !target));
  }

  /// Sends a navigation button over the pointer socket.
  Future<void> press(RemoteKey key) async {
    final tv = _tv;
    if (tv == null) {
      _set(_current.copyWith(commandError: 'Connect to the TV first.'));
      return;
    }
    _set(_current.copyWith(clearCommandError: true));
    try {
      final channel = await _ensurePointer(tv);
      await latency.measure(() => channel.press(_buttonName(key)));
      if (latency.enabled) _set(_current.copyWith(latencyMs: latency.lastMs));
    } on SsapError catch (error) {
      _set(_current.copyWith(commandError: error.message));
      if (error.kind == SsapErrorKind.closed ||
          error.code == 'pointer_closed') {
        _pointer = null;
      }
    } on Object {
      _set(_current.copyWith(commandError: 'Navigation failed.'));
    }
  }

  Future<void> launchApp(String appId) =>
      _clientCommand((client) => client.launchApp(appId));

  /// Re-reads volume from the TV, for the pull-to-refresh gesture and after a
  /// reconnect.
  Future<void> refreshVolume() async {
    final tv = _tv;
    if (tv == null) return;
    try {
      final state = await tv.client.getVolume();
      _set(_current.copyWith(
        volume: state.volume >= 0 ? state.volume : null,
        muted: state.muted,
      ));
    } on SsapError {
      // The next subscription update or command will reconcile it.
    }
  }

  /// Starts press-and-hold volume. Requests are coalesced: a tick is skipped
  /// while the previous one is still in flight, so releasing never leaves a
  /// queue of stale presses.
  void beginVolumeHold({required bool up}) {
    if (_holdTimer != null) return;
    _holdDirection = up ? 1 : -1;
    unawaited(_holdTick());
    _holdTimer = Timer.periodic(
      const Duration(milliseconds: 240),
      (_) => unawaited(_holdTick()),
    );
  }

  void endVolumeHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdDirection = 0;
  }

  /// Powers the TV off, then leaves the remote disconnected. Callers must have
  /// confirmed with the user first.
  Future<void> powerOff() async {
    final tv = _tv;
    if (tv == null) {
      _set(_current.copyWith(commandError: 'Connect to the TV first.'));
      return;
    }
    _manualDisconnect = true;
    _wantConnection = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    try {
      await latency.measure(tv.client.turnOff);
    } on SsapError catch (error) {
      _set(_current.copyWith(commandError: error.message));
    }
    await _closeSession();
    _set(_current.copyWith(
      status: RemoteStatus.idle,
      clearDevice: true,
      clearVolume: true,
      muted: false,
      capabilities: const RemoteCapabilities(),
      clearError: true,
      clearCommandError: true,
      clearReconnectAttempt: true,
      assembling: false,
    ));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _manualDisconnect = true;
    _wantConnection = false;
    _reconnectTimer?.cancel();
    _holdTimer?.cancel();
    await _pairingSubscription?.cancel();
    await _closeSession();
    await pairing.dispose();
    await _states.close();
  }

  Future<void> _holdTick() async {
    if (_holdInFlight || _holdDirection == 0) return;
    _holdInFlight = true;
    try {
      if (_holdDirection > 0) {
        await volumeUp();
      } else {
        await volumeDown();
      }
    } finally {
      _holdInFlight = false;
    }
  }

  Future<bool> _clientCommand(
    Future<void> Function(SsapClient client) action,
  ) async {
    final tv = _tv;
    if (tv == null) {
      _set(_current.copyWith(commandError: 'Connect to the TV first.'));
      return false;
    }
    _set(_current.copyWith(assembling: true, clearCommandError: true));
    try {
      await latency.measure(() => action(tv.client));
      _set(_current.copyWith(
        assembling: false,
        latencyMs: latency.enabled ? latency.lastMs : null,
        clearCommandError: true,
      ));
      return true;
    } on SsapError catch (error) {
      _set(_current.copyWith(
        assembling: false,
        commandError: error.message,
      ));
      if (error.kind == SsapErrorKind.closed) {
        _handleDrop();
      }
      return false;
    } on Object {
      _set(_current.copyWith(
        assembling: false,
        commandError: 'The TV did not accept that command.',
      ));
      return false;
    }
  }

  Future<PointerInputChannel> _ensurePointer(PairedTv tv) async {
    final existing = _pointer;
    if (existing != null && existing.isOpen) return existing;
    await existing?.close();
    final channel = PointerInputChannel(
      client: tv.client,
      transports: transports,
    );
    await channel.open();
    _pointer = channel;
    return channel;
  }

  String _buttonName(RemoteKey key) {
    switch (key) {
      case RemoteKey.up:
        return PointerButtons.up;
      case RemoteKey.down:
        return PointerButtons.down;
      case RemoteKey.left:
        return PointerButtons.left;
      case RemoteKey.right:
        return PointerButtons.right;
      case RemoteKey.ok:
        return PointerButtons.enter;
      case RemoteKey.back:
        return PointerButtons.back;
      case RemoteKey.home:
        return PointerButtons.home;
      case RemoteKey.info:
        return PointerButtons.info;
      case RemoteKey.menu:
        return PointerButtons.menu;
      case RemoteKey.play:
        return PointerButtons.play;
      case RemoteKey.pause:
        return PointerButtons.pause;
      case RemoteKey.rewind:
        return PointerButtons.rewind;
      case RemoteKey.fastForward:
        return PointerButtons.fastForward;
      case RemoteKey.exit:
        return PointerButtons.exit;
    }
  }

  void _onPairingState(PairingSnapshot state) {
    if (_disposed) return;
    if (_connecting && state.phase == PairingPhase.awaitingApproval) {
      _set(_current.copyWith(status: RemoteStatus.awaitingApproval));
    }
  }

  Future<bool> _connectOnce(TvDevice device,
      {bool reconnecting = false}) async {
    if (_disposed || _connecting) return false;
    _connecting = true;
    await _closeSession();
    _set(_current.copyWith(
      status: RemoteStatus.connecting,
      device: device,
      clearError: true,
      clearCommandError: true,
      clearVolume: true,
      assembling: false,
      clearReconnectAttempt: !reconnecting,
      reconnectAttempt: reconnecting ? _reconnectAttempts : null,
    ));

    try {
      final tv = await latency.measure(
        () => pairing.connect(
          host: device.host,
          port: device.port,
          secure: device.secure,
        ),
      );
      if (_disposed) {
        await tv?.dispose();
        return false;
      }
      if (tv == null) {
        _set(_current.copyWith(
          status: RemoteStatus.error,
          error: _pairingFailureMessage(),
          clearReconnectAttempt: true,
        ));
        return false;
      }

      _tv = tv;
      _reconnectAttempts = 0;
      final resolved = TvDevice(
        host: tv.credential.host,
        port: tv.credential.port,
        secure: tv.credential.secure,
        name: device.name,
        modelName: tv.credential.modelName ?? device.modelName,
      );
      _desired = resolved;
      _watchForDrop(tv);
      _set(_current.copyWith(
        status: RemoteStatus.connected,
        device: resolved,
        clearError: true,
        clearCommandError: true,
        clearReconnectAttempt: true,
      ));
      await _syncAfterConnect(tv);
      return true;
    } on SsapError catch (error) {
      _set(_current.copyWith(
        status: RemoteStatus.error,
        error: error.message,
        clearReconnectAttempt: true,
      ));
      return false;
    } on Object {
      _set(_current.copyWith(
        status: RemoteStatus.error,
        error: 'Could not reach the TV. Check that it is on and on the same '
            'network.',
        clearReconnectAttempt: true,
      ));
      return false;
    } finally {
      _connecting = false;
    }
  }

  Future<void> _syncAfterConnect(PairedTv tv) async {
    var capabilities = const RemoteCapabilities();
    try {
      capabilities = RemoteCapabilities.fromTv(
        await CapabilityProbe(tv.client).probe(),
      );
    } on Object {
      // Capabilities stay unknown; every gated control explains itself.
    }

    int? volume;
    var muted = false;
    try {
      final state = await tv.client.getVolume();
      volume = state.volume >= 0 ? state.volume : null;
      muted = state.muted;
    } on SsapError {
      // Leave volume unknown; step commands still work.
    }

    if (_disposed || !identical(_tv, tv)) return;

    await _cancelVolumeSubscription();
    try {
      final subscription = await tv.client.subscribeVolume();
      _volumeSubscription = subscription;
      _volumeUpdates = subscription.updates.listen(
        _onVolumeUpdate,
        onError: (Object _) {},
      );
    } on SsapError {
      // Some firmware refuses subscriptions; commands still update the UI.
    }

    _set(_current.copyWith(
      status: capabilities.externalAudio
          ? RemoteStatus.degraded
          : RemoteStatus.connected,
      capabilities: capabilities,
      volume: volume,
      clearVolume: volume == null,
      muted: muted,
    ));
  }

  void _onVolumeUpdate(Map<String, dynamic> payload) {
    final state = VolumeState.fromPayload(payload);
    _set(_current.copyWith(
      volume: state.volume >= 0 ? state.volume : null,
      clearVolume: state.volume < 0,
      muted: state.muted,
    ));
  }

  void _watchForDrop(PairedTv tv) {
    _framesSubscription = tv.session.frames.listen(
      (_) {},
      onError: (Object _) {},
      onDone: () {
        if (!_disposed && identical(_tv, tv) && !_manualDisconnect) {
          _handleDrop();
        }
      },
    );
  }

  void _handleDrop() {
    if (_disposed) return;
    _tv = null;
    _pointer = null;
    unawaited(_cancelVolumeSubscription());
    _set(_current.copyWith(
      status: RemoteStatus.asleep,
      error: 'The TV stopped responding. It may be off, in standby, or off '
          'the network.',
      clearReconnectAttempt: !reconnectEnabled,
      reconnectAttempt: reconnectEnabled && _foreground ? 0 : null,
    ));
    if (reconnectEnabled && _wantConnection) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed ||
        !_foreground ||
        !_wantConnection ||
        _manualDisconnect ||
        !reconnectEnabled) {
      return;
    }
    final desired = _desired;
    if (desired == null || _reconnectTimer != null) return;

    final delay = _backoff.delayFor(_reconnectAttempts);
    _set(_current.copyWith(
      status: RemoteStatus.asleep,
      reconnectAttempt: _reconnectAttempts,
    ));
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_attemptReconnect());
    });
  }

  Future<void> _attemptReconnect() async {
    if (_disposed || !_foreground || _manualDisconnect || !_wantConnection) {
      return;
    }
    final desired = _desired;
    if (desired == null) return;

    final ok = await _connectOnce(desired, reconnecting: true);
    if (!ok && !_disposed && _foreground && _wantConnection) {
      _reconnectAttempts += 1;
      _scheduleReconnect();
    }
  }

  Future<void> _cancelVolumeSubscription() async {
    final updates = _volumeUpdates;
    _volumeUpdates = null;
    await updates?.cancel();
    final subscription = _volumeSubscription;
    _volumeSubscription = null;
    await subscription?.cancel();
  }

  Future<void> _closeSession() async {
    await _cancelVolumeSubscription();
    final pointer = _pointer;
    _pointer = null;
    await pointer?.close();
    final frames = _framesSubscription;
    _framesSubscription = null;
    await frames?.cancel();
    final tv = _tv;
    _tv = null;
    await tv?.dispose();
  }

  String _pairingFailureMessage() {
    final state = pairing.current;
    final error = state.error?.message;
    switch (state.phase) {
      case PairingPhase.denied:
        return error ?? 'The TV declined the pairing request.';
      case PairingPhase.timedOut:
        return 'The TV did not confirm pairing in time. Try again and accept '
            'the prompt on the TV.';
      case PairingPhase.failed:
        return error ?? 'The TV could not be reached.';
      default:
        return error ?? 'Pairing did not complete.';
    }
  }

  void _set(RemoteSnapshot snapshot) {
    _current = snapshot;
    if (!_states.isClosed) _states.add(snapshot);
  }
}
