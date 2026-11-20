import 'dart:async';
import 'dart:io';

import 'package:mock_webos_tv/mock_webos_tv.dart';
import 'package:remote_core/remote_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('connection', () {
    test('pairs, probes capabilities and reports TV volume', () async {
      final h = await harness();
      await connectHarness(h);

      final snapshot = h.controller.snapshot;
      expect(snapshot.status, RemoteStatus.connected);
      expect(snapshot.device?.host, '127.0.0.1');
      expect(snapshot.device?.port, h.port);
      expect(snapshot.volume, 12);
      expect(snapshot.muted, isFalse);
      expect(snapshot.capabilities.absoluteVolume, isTrue);
      expect(snapshot.capabilities.navigation, isTrue);
      expect(snapshot.error, isNull);
      expect(h.tv.pairingPrompts, 1);
    });

    test('restores a stored key without prompting again', () async {
      final h = await harness();
      await connectHarness(h);
      expect(h.tv.pairingPrompts, 1);

      await h.controller.disconnect();
      await h.controller.connectHost('127.0.0.1', port: h.port);

      expect(h.controller.snapshot.status, RemoteStatus.connected);
      expect(
        h.tv.pairingPrompts,
        1,
        reason: 'the stored key must be reused, not a second prompt',
      );
    });

    test('reports a denial with actionable copy', () async {
      final h = await harness(
        config: MockTvConfig(
          pairing: PairingBehaviour.deny,
          promptDelay: Duration.zero,
        ),
      );
      await connectHarness(h);

      final snapshot = h.controller.snapshot;
      expect(snapshot.status, RemoteStatus.error);
      expect(snapshot.error, contains('declined'));
      expect(h.controller.snapshot.isConnected, isFalse);
    });

    test('unreachable TV produces an error, not a hang', () async {
      final h = await harness();
      await h.controller.connectHost('127.0.0.1', port: 1);
      expect(h.controller.snapshot.status, RemoteStatus.error);
      expect(h.controller.snapshot.error, isNotNull);
    });
  });

  group('commands', () {
    test('volume steps reach the TV and the subscription updates state',
        () async {
      final h = await harness();
      await connectHarness(h);

      await h.controller.volumeUp();
      await h.controller.volumeUp();
      await until(
        () => h.controller.snapshot.volume == 14,
        describe: 'volume 14',
        current: () => h.controller.snapshot.volume,
      );

      await h.controller.toggleMute();
      await until(
        () => h.controller.snapshot.muted,
        describe: 'muted',
        current: () => h.controller.snapshot.muted,
      );

      expect(
        h.tv.uris,
        containsAll(<String>[
          'ssap://audio/volumeUp',
          'ssap://audio/setMute',
        ]),
      );
    });

    test('presses go over the pointer socket with protocol button names',
        () async {
      final h = await harness();
      await connectHarness(h);

      await h.controller.press(RemoteKey.up);
      await h.controller.press(RemoteKey.ok);
      await until(
        () => h.tv.pointerEvents.length >= 2,
        describe: 'two pointer events',
        current: () => h.tv.pointerEvents.length,
      );

      expect(h.tv.pointerEvents[0], <String, dynamic>{
        'type': 'button',
        'name': 'UP',
      });
      expect(h.tv.pointerEvents[1], <String, dynamic>{
        'type': 'button',
        'name': 'ENTER',
      });
    });

    test('ARC volume is degraded and the slider explains itself', () async {
      final h = await harness(
        config: MockTvConfig(
          volume: VolumeMode.arcExternal,
          promptDelay: Duration.zero,
        ),
      );
      await connectHarness(h);

      final snapshot = h.controller.snapshot;
      expect(snapshot.status, RemoteStatus.degraded);
      expect(snapshot.capabilities.externalAudio, isTrue);
      expect(snapshot.capabilities.absoluteVolume, isFalse);
      expect(
        snapshot.capabilities.reasonFor(RemoteControl.volumeSlider),
        contains('soundbar'),
      );

      await h.controller.setVolume(30);
      expect(h.controller.snapshot.commandError, contains('soundbar'));

      // Step commands still work when ARC owns absolute volume.
      await h.controller.volumeUp();
      expect(h.tv.uris, contains('ssap://audio/volumeUp'));
    });

    test('commands before connecting report a reason instead of throwing',
        () async {
      final h = await harness();
      await h.controller.volumeUp();
      expect(h.controller.snapshot.commandError, contains('Connect'));
    });

    test('hold coalesces volume steps and stops when released', () async {
      final h = await harness();
      await connectHarness(h);

      h.controller.beginVolumeHold(up: true);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      h.controller.endVolumeHold();

      final afterRelease = h.controller.snapshot.volume!;
      expect(afterRelease, greaterThan(12));

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        h.controller.snapshot.volume,
        afterRelease,
        reason: 'no queued presses may land after release',
      );
    });

    test('latency is recorded only when enabled', () async {
      final h = await harness(latency: true);
      await connectHarness(h);
      await h.controller.volumeUp();
      expect(h.controller.snapshot.latencyMs, isNotNull);
      expect(h.controller.latency.samples, greaterThan(0));
    });
  });

  group('reconnect', () {
    test('recovers after the TV drops the connection', () async {
      final h = await harness();
      await connectHarness(h);
      expect(h.tv.pairingPrompts, 1);

      await h.tv.dropClients();
      await until(
        () => h.controller.snapshot.status == RemoteStatus.connected,
        describe: 'reconnected',
        current: () => h.controller.snapshot,
      );
      expect(
        h.tv.pairingPrompts,
        1,
        reason: 'reconnect must use the stored key',
      );
      expect(h.controller.snapshot.error, isNull);
    });

    test('does not reconnect while backgrounded', () async {
      final h = await harness();
      await connectHarness(h);

      h.controller.setForeground(false);
      await h.tv.dropClients();
      await until(
        () => h.controller.snapshot.status == RemoteStatus.asleep,
        describe: 'asleep while backgrounded',
        current: () => h.controller.snapshot,
      );

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(h.controller.snapshot.status, RemoteStatus.asleep);

      h.controller.setForeground(true);
      await until(
        () => h.controller.snapshot.status == RemoteStatus.connected,
        describe: 'reconnected on foreground',
        current: () => h.controller.snapshot,
      );
    });
  });

  group('discovery', () {
    test('reports devices from the platform discovery', () async {
      final discovery = FakeDiscovery(
        results: const <DiscoveredTv>[
          DiscoveredTv(host: '192.168.1.20', name: 'Living room TV'),
        ],
      );
      final h = await harness(discovery: discovery);

      await h.controller.discover();

      expect(discovery.searches, 1);
      expect(h.controller.snapshot.discovered.single.displayName,
          'Living room TV');
      expect(h.controller.snapshot.status, RemoteStatus.idle);
      expect(h.controller.snapshot.error, isNull);
    });

    test('an empty sweep explains likely network causes', () async {
      final h = await harness(discovery: FakeDiscovery());
      await h.controller.discover();
      expect(h.controller.snapshot.hasSearched, isTrue);
      expect(h.controller.snapshot.error, contains('same network'));
    });

    test('unsupported discovery surfaces its reason', () async {
      final h = await harness();
      await h.controller.discover();
      expect(h.controller.snapshot.error, contains('multicast'));
      expect(h.controller.discoverySupported, isFalse);
    });

    test('a failed sweep does not leave a spinner', () async {
      final h = await harness(
        discovery: FakeDiscovery(failure: 'socket denied'),
      );
      await h.controller.discover();
      expect(h.controller.snapshot.status, RemoteStatus.idle);
      expect(h.controller.snapshot.error, 'socket denied');
    });

    test('cancelling a sweep stops it and discards late results', () async {
      final discovery = _SlowDiscovery();
      final h = await harness(discovery: discovery);

      final pending = h.controller.discover();
      await until(
        () => h.controller.snapshot.status == RemoteStatus.discovering,
        describe: 'the sweep to start',
      );

      h.controller.cancelDiscovery();

      expect(discovery.cancel?.isCancelled, isTrue);
      expect(h.controller.snapshot.status, RemoteStatus.idle);

      discovery.complete(const <DiscoveredTv>[
        DiscoveredTv(host: '192.168.1.20', name: 'Late TV'),
      ]);
      await pending;

      expect(h.controller.snapshot.discovered, isEmpty);
      expect(h.controller.snapshot.hasSearched, isFalse);
    });
  });

  group('forget', () {
    test('deletes the key and clears the device', () async {
      final h = await harness();
      await connectHarness(h);
      expect(await h.store.read('127.0.0.1'), isNotNull);

      await h.controller.forget();

      expect(h.controller.snapshot.status, RemoteStatus.idle);
      expect(h.controller.snapshot.device, isNull);
      expect(await h.store.read('127.0.0.1'), isNull);
    });
  });

  test('the platform discovery factory resolves on this host', () {
    final discovery = createPlatformDiscovery();
    expect(discovery, isA<RemoteDiscovery>());
    expect(discovery.isSupported, Platform.isLinux);
  });
}

/// A discovery sweep that waits until the test releases it, so cancellation can
/// be observed before any result exists.
class _SlowDiscovery implements RemoteDiscovery {
  final Completer<List<DiscoveredTv>> _result = Completer<List<DiscoveredTv>>();
  DiscoveryCancellation? cancel;

  @override
  bool get isSupported => true;

  @override
  String? get unsupportedReason => null;

  @override
  Future<List<DiscoveredTv>> search({
    Duration timeout = const Duration(seconds: 4),
    DiscoveryCancellation? cancel,
  }) {
    this.cancel = cancel;
    return _result.future;
  }

  void complete(List<DiscoveredTv> tvs) => _result.complete(tvs);
}
