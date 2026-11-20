import 'discovery.dart';

/// Discovery on platforms without `dart:io` (the browser).
///
/// The honest answer: UDP multicast is not available, so manual IP entry is the
/// only path. The architecture calls this out explicitly.
RemoteDiscovery createPlatformDiscovery({
  Future<void> Function()? onSweepStart,
  Future<void> Function()? onSweepEnd,
}) =>
    const UnsupportedDiscovery(
      'This browser cannot send multicast (SSDP), so TVs cannot be found '
      'automatically. Enter the TV address instead.',
    );
