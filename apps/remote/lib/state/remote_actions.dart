import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:remote_core/remote_core.dart';

/// Every user action the remote screens can raise, in one object.
///
/// Keeping the callbacks together means the screens stay pure widgets and the
/// controller is wired in exactly one place.
class RemoteActions {
  const RemoteActions({
    required this.discover,
    required this.connectHost,
    required this.connectDevice,
    required this.disconnect,
    required this.forget,
    required this.volumeUp,
    required this.volumeDown,
    required this.setVolume,
    required this.toggleMute,
    required this.beginVolumeHold,
    required this.endVolumeHold,
    required this.refreshVolume,
    required this.press,
    required this.powerOff,
  });

  final VoidCallback discover;
  final void Function(String host, int? port) connectHost;
  final void Function(DiscoveredTv tv) connectDevice;
  final VoidCallback disconnect;
  final VoidCallback forget;
  final VoidCallback volumeUp;
  final VoidCallback volumeDown;
  final void Function(int volume) setVolume;
  final VoidCallback toggleMute;
  final void Function({required bool up}) beginVolumeHold;
  final VoidCallback endVolumeHold;
  final VoidCallback refreshVolume;
  final void Function(RemoteKey key) press;
  final VoidCallback powerOff;
}
