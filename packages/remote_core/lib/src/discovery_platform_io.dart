import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'discovery.dart';
import 'models.dart';

/// Discovery for native platforms over SSDP multicast.
///
/// Platform caveats this Dart implementation cannot fix on its own:
/// * Android may drop multicast replies unless a `WifiManager.MulticastLock`
///   is held for the sweep; the app's `lg_discovery` plugin does that around
///   each sweep.
/// * iOS only returns raw multicast with the `com.apple.developer.networking
///   .multicast` entitlement. Bonjour `_lg-mrt._tcp` is the entitlement-free
///   path and lives in the same plugin.
///
/// When both find nothing, the bounded subnet probe below is the last resort.
/// Manual IP entry remains available even then.
RemoteDiscovery createPlatformDiscovery({
  Future<void> Function()? onSweepStart,
  Future<void> Function()? onSweepEnd,
}) =>
    SsdpDiscovery(onSweepStart: onSweepStart, onSweepEnd: onSweepEnd);

/// The last-resort probe used after SSDP and Bonjour return no devices.
///
/// Scans the private /24 around each IPv4 interface for the TV's WebSocket
/// ports. A successful TCP connection only suggests a TV, so the results are
/// marked as probed and the UI asks the user to confirm.
RemoteDiscovery createSubnetProbeDiscovery() => SubnetProbeDiscovery(
      subnetPrefixes: _privateSubnetPrefixes,
      probe: _isPortOpen,
    );

Future<bool> _isPortOpen(String host, int port) async {
  final Socket socket;
  try {
    socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(milliseconds: 200),
    );
  } on Object {
    return false;
  }
  socket.destroy();
  return true;
}

Future<List<String>> _privateSubnetPrefixes() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return privateSubnetPrefixes(<String>[
      for (final interface in interfaces)
        for (final address in interface.addresses) address.address,
    ]);
  } on Object {
    return const <String>[];
  }
}

class SsdpDiscovery implements RemoteDiscovery {
  SsdpDiscovery({
    this.descriptionTimeout = const Duration(seconds: 1),
    this.onSweepStart,
    this.onSweepEnd,
  });

  /// Time allowed per UPnP description fetch; names are a nicety, never a
  /// reason to lose a discovered TV.
  final Duration descriptionTimeout;

  /// Hooks around the multicast sweep, used by the app to hold the Android
  /// multicast lock for exactly as long as it is needed.
  final Future<void> Function()? onSweepStart;
  final Future<void> Function()? onSweepEnd;

  @override
  bool get isSupported => true;

  @override
  String? get unsupportedReason => null;

  @override
  Future<List<DiscoveredTv>> search({
    Duration timeout = const Duration(seconds: 4),
    DiscoveryCancellation? cancel,
  }) async {
    await _runHook(onSweepStart);
    try {
      if (cancel?.isCancelled ?? false) return const <DiscoveredTv>[];
      return await _sweep(timeout, cancel);
    } finally {
      await _runHook(onSweepEnd);
    }
  }

  /// A lock that cannot be acquired must not prevent the sweep; the manual
  /// entry path is always available.
  Future<void> _runHook(Future<void> Function()? hook) async {
    if (hook == null) return;
    try {
      await hook();
    } on Object {
      // Best effort only.
    }
  }

  Future<List<DiscoveredTv>> _sweep(
    Duration timeout,
    DiscoveryCancellation? cancel,
  ) async {
    final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
    } on SocketException catch (error) {
      throw DiscoveryFailure(
        'Could not open a discovery socket (${error.osError?.message ?? 'socket error'}). '
        'Check that the device is on Wi-Fi and that local-network access is allowed.',
      );
    }
    socket.broadcastEnabled = true;

    final found = <String, DiscoveredTv>{};
    final subscription = socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true);
        final response = SsdpResponse.tryParse(
          text,
          senderAddress: datagram.address.address,
        );
        if (response == null || !response.looksLikeWebOs) return;
        final tv = response.toDiscoveredTv();
        found[tv.host] = tv;
      },
      onError: (Object _) {
        // A single malformed datagram must not abort the sweep.
      },
    );

    try {
      final requests = <String>[
        SsdpSearch.build(),
        SsdpSearch.build(searchTarget: 'ssdp:all'),
      ];
      for (final request in requests) {
        try {
          socket.send(
            utf8.encode(request),
            InternetAddress(SsdpSearch.multicastAddress),
            SsdpSearch.multicastPort,
          );
        } on SocketException {
          // Multicast send can fail on some networks; manual entry remains.
        }
      }
      final delay = Future<void>.delayed(timeout);
      if (cancel == null) {
        await delay;
      } else {
        await Future.any(<Future<void>>[delay, cancel.whenCancelled]);
      }
    } finally {
      await subscription.cancel();
      socket.close();
    }

    if (cancel?.isCancelled ?? false) return const <DiscoveredTv>[];

    final devices = found.values.toList()
      ..sort((a, b) => a.host.compareTo(b.host));
    final enriched = await Future.wait(devices.map(_withDescription));
    return enriched;
  }

  Future<DiscoveredTv> _withDescription(DiscoveredTv tv) async {
    final location = tv.location;
    if (location == null) return tv;
    final uri = Uri.tryParse(location);
    if (uri == null || !uri.hasScheme) return tv;

    final client = HttpClient()..connectionTimeout = descriptionTimeout;
    try {
      final request = await client.getUrl(uri).timeout(descriptionTimeout);
      final response = await request.close().timeout(descriptionTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(descriptionTimeout);
      return DiscoveredTv(
        host: tv.host,
        location: location,
        name: _tag(body, 'friendlyName') ?? tv.name,
        modelName: _tag(body, 'modelName') ?? tv.modelName,
        source: tv.source,
      );
    } on Object {
      // The TV answered SSDP; a failed description fetch only costs the name.
      return tv;
    } finally {
      client.close(force: true);
    }
  }

  String? _tag(String xml, String tag) {
    final match = RegExp(
      '<$tag[^>]*>(.*?)</$tag>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(xml);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }
}
