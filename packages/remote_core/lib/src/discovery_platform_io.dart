import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'discovery.dart';
import 'models.dart';

/// Discovery for native platforms over SSDP multicast.
///
/// Platform caveats that this Dart implementation cannot fix on its own:
/// * Android may drop multicast replies unless a `WifiManager.MulticastLock`
///   is held for the sweep. The manifest declares the permission; the lock
///   needs a native plugin and is still outstanding.
/// * iOS only returns raw multicast with the `com.apple.developer.networking
///   .multicast` entitlement. Bonjour `_lg-mrt._tcp` is the fallback that needs
///   no entitlement and is not implemented yet.
///
/// Manual IP entry is always available, which is why this gap is documented
/// rather than hidden.
RemoteDiscovery createPlatformDiscovery() => SsdpDiscovery();

class SsdpDiscovery implements RemoteDiscovery {
  SsdpDiscovery({this.descriptionTimeout = const Duration(seconds: 1)});

  /// Time allowed per UPnP description fetch; names are a nicety, never a
  /// reason to lose a discovered TV.
  final Duration descriptionTimeout;

  @override
  bool get isSupported => true;

  @override
  String? get unsupportedReason => null;

  @override
  Future<List<DiscoveredTv>> search({
    Duration timeout = const Duration(seconds: 4),
  }) async {
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
      await Future<void>.delayed(timeout);
    } finally {
      await subscription.cancel();
      socket.close();
    }

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
