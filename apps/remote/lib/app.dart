import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:remote_core/remote_core.dart';

import 'features/home/home_screen.dart';
import 'state/remote_actions.dart';
import 'theme/remote_theme.dart';
import 'wiring.dart';

/// App root. Owns the controller (unless one is injected for tests), tracks the
/// app lifecycle for reconnect pauses, and hands plain snapshots to the UI.
class SmartRemoteApp extends StatefulWidget {
  const SmartRemoteApp({super.key, this.controller, this.webLimitations});

  final RemoteController? controller;

  /// Overridden in tests; defaults to [kIsWeb].
  final bool? webLimitations;

  @override
  State<SmartRemoteApp> createState() => _SmartRemoteAppState();
}

class _SmartRemoteAppState extends State<SmartRemoteApp>
    with WidgetsBindingObserver {
  late final RemoteController _controller;
  late final bool _ownsController;
  late RemoteSnapshot _snapshot;
  StreamSubscription<RemoteSnapshot>? _subscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? createRemoteController();
    _snapshot = _controller.snapshot;
    _subscription = _controller.states.listen((RemoteSnapshot snapshot) {
      if (mounted) setState(() => _snapshot = snapshot);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    if (_ownsController) unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.setForeground(state == AppLifecycleState.resumed);
  }

  RemoteActions get _actions => RemoteActions(
    discover: () => unawaited(_controller.discover()),
    cancelDiscovery: _controller.cancelDiscovery,
    connectHost: (String host, int? port) =>
        unawaited(_controller.connectHost(host, port: port)),
    connectDevice: (DiscoveredTv tv) => unawaited(_controller.connect(tv)),
    disconnect: () => unawaited(_controller.disconnect()),
    forget: () => unawaited(_controller.forget()),
    volumeUp: () => unawaited(_controller.volumeUp()),
    volumeDown: () => unawaited(_controller.volumeDown()),
    setVolume: (int volume) => unawaited(_controller.setVolume(volume)),
    toggleMute: () => unawaited(_controller.toggleMute()),
    beginVolumeHold: ({required bool up}) =>
        _controller.beginVolumeHold(up: up),
    endVolumeHold: _controller.endVolumeHold,
    refreshVolume: () => unawaited(_controller.refreshVolume()),
    press: (RemoteKey key) => unawaited(_controller.press(key)),
    powerOff: () => unawaited(_controller.powerOff()),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Remote',
      debugShowCheckedModeBanner: false,
      theme: buildRemoteTheme(),
      home: HomeScreen(
        snapshot: _snapshot,
        actions: _actions,
        discoverySupported: _controller.discoverySupported,
        discoveryUnsupportedReason: _controller.discoveryUnsupportedReason,
        webLimitations: widget.webLimitations ?? kIsWeb,
      ),
    );
  }
}
