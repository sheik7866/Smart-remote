import 'package:material_ui/material_ui.dart';
import 'package:remote_core/remote_core.dart';

import '../../state/remote_actions.dart';
import '../../widgets/status_chip.dart';
import '../connect/connect_screen.dart';
import '../limitations/limitations_screen.dart';
import '../remote/remote_screen.dart';

enum _MenuAction { limitations, disconnect, forget, about }

/// Chooses between the pairing experience and the connected remote, and owns
/// the app-level menu.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.snapshot,
    required this.actions,
    required this.discoverySupported,
    this.discoveryUnsupportedReason,
    this.webLimitations = false,
  });

  final RemoteSnapshot snapshot;
  final RemoteActions actions;
  final bool discoverySupported;
  final String? discoveryUnsupportedReason;
  final bool webLimitations;

  bool get _showRemote =>
      snapshot.device != null &&
      snapshot.status != RemoteStatus.awaitingApproval &&
      snapshot.status != RemoteStatus.error &&
      snapshot.status != RemoteStatus.idle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Remote'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: StatusChip(snapshot: snapshot)),
          ),
          PopupMenuButton<_MenuAction>(
            key: const Key('menu-button'),
            tooltip: 'More options',
            onSelected: (action) => _onMenu(context, action),
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<_MenuAction>>[
                  if (snapshot.device != null)
                    const PopupMenuItem<_MenuAction>(
                      value: _MenuAction.forget,
                      child: Text('Forget this TV'),
                    ),
                  if (snapshot.isConnected)
                    const PopupMenuItem<_MenuAction>(
                      value: _MenuAction.disconnect,
                      child: Text('Disconnect'),
                    ),
                  const PopupMenuItem<_MenuAction>(
                    value: _MenuAction.limitations,
                    child: Text('Browser limitations'),
                  ),
                  const PopupMenuItem<_MenuAction>(
                    value: _MenuAction.about,
                    child: Text('About'),
                  ),
                ],
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _showRemote
              ? RemoteScreen(
                  key: const ValueKey<String>('remote'),
                  snapshot: snapshot,
                  onVolumeUp: actions.volumeUp,
                  onVolumeDown: actions.volumeDown,
                  onSetVolume: actions.setVolume,
                  onToggleMute: actions.toggleMute,
                  onBeginVolumeHold: actions.beginVolumeHold,
                  onEndVolumeHold: actions.endVolumeHold,
                  onRefreshVolume: actions.refreshVolume,
                  onPress: actions.press,
                  onPowerOff: actions.powerOff,
                )
              : ConnectScreen(
                  key: const ValueKey<String>('connect'),
                  snapshot: snapshot,
                  onDiscover: actions.discover,
                  onCancelDiscovery: actions.cancelDiscovery,
                  onConnectHost: actions.connectHost,
                  onConnectDevice: actions.connectDevice,
                  onStopWaiting: actions.disconnect,
                  discoverySupported: discoverySupported,
                  discoveryUnsupportedReason: discoveryUnsupportedReason,
                  webLimitations: webLimitations,
                ),
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, _MenuAction action) async {
    switch (action) {
      case _MenuAction.limitations:
        actions.cancelDiscovery();
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => const LimitationsScreen(),
          ),
        );
      case _MenuAction.disconnect:
        actions.disconnect();
      case _MenuAction.forget:
        await _confirmForget(context);
      case _MenuAction.about:
        await _showAbout(context);
    }
  }

  Future<void> _confirmForget(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const Key('forget-confirm-dialog'),
        title: const Text('Forget this TV?'),
        content: const Text(
          'The pairing key stored on this device will be deleted. You will '
          'need to approve a new prompt on the TV next time.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('forget-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed == true) actions.forget();
  }

  Future<void> _showAbout(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Smart Remote'),
        content: const Text(
          'A local-only LG webOS remote.\n\n'
          '• Control packets go straight to the TV; there is no cloud relay.\n'
          '• Pairing keys stay in the device keystore.\n'
          '• Unsupported controls are disabled with a reason.\n\n'
          'Commands proven against the mock TV are not claimed to work on '
          'hardware until the physical-TV checklist is signed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
