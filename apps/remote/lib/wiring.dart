import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:lg_discovery/lg_discovery.dart';
import 'package:remote_core/remote_core.dart';
import 'package:webos_ssap/webos_ssap.dart';

import 'discovery/bonjour_discovery.dart';
import 'storage/secure_credential_store.dart';

/// Composition root: the only place that knows both the protocol package and
/// the UI. Widgets below `features/` import `remote_core` only.
RemoteController createRemoteController() {
  final CredentialStore store = createCredentialStore();
  final TransportFactory transports = createTransportFactory();
  final service = PairingService(transports: transports, store: store);
  final pairing = PairingController(service: service, store: store);
  return RemoteController(
    pairing: pairing,
    transports: transports,
    discovery: createAppDiscovery(),
  );
}

/// Discovery for this platform.
///
/// * Android: SSDP with a multicast lock held for the sweep only.
/// * iOS: SSDP (only with the multicast entitlement) plus Bonjour, merged.
/// * Both: a bounded subnet probe only when the sweeps above find nothing.
/// * Web: unsupported, with the reason the UI shows.
RemoteDiscovery createAppDiscovery({
  LgDiscovery? native,
  RemoteDiscovery? subnetProbe,
}) {
  if (kIsWeb) return createPlatformDiscovery();

  final platform = native ?? LgDiscovery();
  final ssdp = createPlatformDiscovery(
    onSweepStart: platform.acquireMulticastLock,
    onSweepEnd: platform.releaseMulticastLock,
  );
  final probe = subnetProbe ?? createSubnetProbeDiscovery();
  if (!platform.supportsBonjour) {
    return CombinedDiscovery(<RemoteDiscovery>[ssdp], fallback: probe);
  }

  return CombinedDiscovery(<RemoteDiscovery>[
    ssdp,
    BonjourDiscovery(platform),
  ], fallback: probe);
}

/// Native builds get the real `dart:io` WebSocket transport. The browser gets
/// an explicit refusal instead of a silent failure.
TransportFactory createTransportFactory() {
  if (kIsWeb) {
    return (
      Uri endpoint, {
      CertificatePolicy policy = CertificatePolicy.native,
    }) => _BrowserTransport(endpoint);
  }
  return (
    Uri endpoint, {
    CertificatePolicy policy = CertificatePolicy.native,
  }) => IoWebSocketTransport(endpoint, policy: policy);
}

class _BrowserTransport implements SsapTransport {
  _BrowserTransport(this.endpoint);

  @override
  final Uri endpoint;

  @override
  Future<void> connect() async {
    throw TransportException(
      TransportErrorKind.unsupported,
      'This browser cannot open the TV connection. An https page cannot use '
      'ws://, and the TV’s wss:// certificate is self-signed. Use the '
      'native app, or serve the web client over http:// on the same LAN.',
      endpoint: endpoint,
    );
  }

  @override
  Stream<String> get messages => const Stream<String>.empty();

  @override
  Future<void> send(String frame) async {
    throw TransportException(
      TransportErrorKind.closed,
      'The browser transport is not connected.',
      endpoint: endpoint,
    );
  }

  @override
  Future<void> close() async {}

  @override
  bool get isConnected => false;

  @override
  String? get certificateFingerprint => null;
}
