import 'dart:async';
import 'dart:io';

import 'package:mock_webos_tv/mock_webos_tv.dart';
import 'package:remote_core/remote_core.dart';
import 'package:test/test.dart';
import 'package:webos_ssap/webos_ssap.dart';

const SsapTimeouts testTimeouts = SsapTimeouts(
  request: Duration(seconds: 2),
  pairing: Duration(seconds: 2),
  subscription: Duration(seconds: 2),
);

SsapTransport ioTransport(
  Uri endpoint, {
  CertificatePolicy policy = CertificatePolicy.native,
}) =>
    IoWebSocketTransport(endpoint, policy: policy);

class TestHarness {
  TestHarness({
    required this.tv,
    required this.store,
    required this.controller,
  });

  final MockWebOsTv tv;
  final CredentialStore store;
  final RemoteController controller;

  int get port => tv.port;
}

Future<TestHarness> harness({
  MockTvConfig? config,
  RemoteDiscovery discovery = const UnsupportedDiscovery(),
  CredentialStore? store,
  bool reconnect = true,
  bool latency = false,
}) async {
  final tv = MockWebOsTv(
    config ?? MockTvConfig(promptDelay: Duration.zero),
  );
  await tv.start();
  addTearDown(tv.stop);

  final credentialStore = store ?? MemoryCredentialStore();
  final service = PairingService(
    transports: ioTransport,
    store: credentialStore,
    timeouts: testTimeouts,
  );
  final pairing = PairingController(service: service, store: credentialStore);
  final controller = RemoteController(
    pairing: pairing,
    transports: ioTransport,
    discovery: discovery,
    backoff: BackoffStrategy(
      base: const Duration(milliseconds: 20),
      max: const Duration(milliseconds: 60),
      jitter: 0,
    ),
    latency: LatencyTracker(enabled: latency),
    reconnectEnabled: reconnect,
  );
  addTearDown(controller.dispose);

  return TestHarness(tv: tv, store: credentialStore, controller: controller);
}

Future<void> connectHarness(TestHarness harness) =>
    harness.controller.connectHost('127.0.0.1', port: harness.port);

/// Polls until [predicate] holds, failing with the current snapshot when the
/// deadline passes. Avoids fixed sleeps that make reconnect tests flaky.
Future<void> until(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 4),
  String describe = 'condition',
  Object? Function()? current,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $describe; current: ${current?.call()}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A discovery implementation with scripted results, so controller state can be
/// tested without multicast.
class FakeDiscovery implements RemoteDiscovery {
  FakeDiscovery({this.results = const <DiscoveredTv>[], this.failure});

  List<DiscoveredTv> results;
  String? failure;
  int searches = 0;

  @override
  bool get isSupported => true;

  @override
  String? get unsupportedReason => null;

  @override
  Future<List<DiscoveredTv>> search({
    Duration timeout = const Duration(seconds: 4),
    DiscoveryCancellation? cancel,
  }) async {
    searches += 1;
    final message = failure;
    if (message != null) throw DiscoveryFailure(message);
    return results;
  }
}

/// A raw socket is not opened in tests; this only checks the platform factory
/// resolves and the interface is implemented.
bool get hasIoDiscovery => Platform.isLinux;
