import 'package:mock_webos_tv/mock_webos_tv.dart';
import 'package:test/test.dart';
import 'package:webos_ssap/webos_ssap.dart';

import 'support.dart';

PairingController controllerFor(
  CredentialStore store, {
  SsapTimeouts timeouts = fastTimeouts,
  SsapLogger logger = const SsapLogger(),
}) =>
    PairingController(
      service: PairingService(
        transports: ioTransport,
        store: store,
        logger: logger,
        timeouts: timeouts,
      ),
    );

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('pairs, stores the key and publishes each phase in order', () async {
    final tv = await startTv(MockTvConfig());
    final store = MemoryCredentialStore();
    final controller = controllerFor(store);
    addTearDown(controller.dispose);

    final phases = <PairingPhase>[];
    final subscription = controller.states.listen((s) => phases.add(s.phase));
    addTearDown(subscription.cancel);

    final paired = await controller.connect(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
    );
    await settle();

    expect(paired, isNotNull);
    expect(controller.current.phase, PairingPhase.paired);
    expect(controller.current.credential?.clientKey, tv.issuedClientKey);
    expect((await store.read('127.0.0.1'))?.clientKey, tv.issuedClientKey);
    expect(tv.pairingPrompts, 1);
    expect(phases, <PairingPhase>[
      PairingPhase.connecting,
      PairingPhase.awaitingApproval,
      PairingPhase.paired,
    ]);
  });

  test('a relaunch restores the stored key without prompting again', () async {
    final tv = await startTv(MockTvConfig());
    final store = MemoryCredentialStore();

    final first = controllerFor(store);
    await first.connect(host: '127.0.0.1', port: tv.port, secure: false);
    await first.dispose();

    final second = controllerFor(store);
    addTearDown(second.dispose);

    // No port or scheme: the stored credential must supply both.
    final restored = await second.connect(host: '127.0.0.1');
    await settle();

    expect(restored, isNotNull);
    expect(restored!.credential.port, tv.port);
    expect(restored.credential.secure, isFalse);
    expect(second.current.phase, PairingPhase.paired);
    expect(tv.pairingPrompts, 1, reason: 'restore must not prompt again');
  });

  test('a revoked key is cleared and the TV is re-paired automatically',
      () async {
    final tv = await startTv(MockTvConfig());
    final store = MemoryCredentialStore();

    final first = controllerFor(store);
    final paired = await first.connect(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
    );
    final oldKey = paired!.credential.clientKey;
    await first.dispose();

    tv.revokeClientKeys();

    final second = controllerFor(store);
    addTearDown(second.dispose);
    final phases = <PairingPhase>[];
    final subscription = second.states.listen((s) => phases.add(s.phase));
    addTearDown(subscription.cancel);

    final repaired = await second.connect(host: '127.0.0.1');
    await settle();

    expect(repaired, isNotNull);
    expect(second.current.phase, PairingPhase.paired);
    expect(tv.pairingPrompts, 2,
        reason: 'revocation earns exactly one new prompt');
    expect(repaired!.credential.clientKey, isNot(oldKey));
    expect(
      (await store.read('127.0.0.1'))?.clientKey,
      repaired.credential.clientKey,
      reason: 'the replacement key must be persisted',
    );
    expect(
      phases,
      containsAllInOrder(<PairingPhase>[
        PairingPhase.connecting,
        PairingPhase.revoked,
        PairingPhase.awaitingApproval,
        PairingPhase.paired,
      ]),
    );
  });

  test('a denial ends in denied and stores no key', () async {
    final tv = await startTv(MockTvConfig(pairing: PairingBehaviour.deny));
    final store = MemoryCredentialStore();
    final controller = controllerFor(store);
    addTearDown(controller.dispose);

    final result = await controller.connect(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
    );

    expect(result, isNull);
    expect(controller.current.phase, PairingPhase.denied);
    expect(controller.current.error?.code, 'pairing_denied');
    expect(await store.readAll(), isEmpty);
  });

  test('an unanswered prompt ends in timedOut instead of hanging', () async {
    final tv = await startTv(
      MockTvConfig(pairing: PairingBehaviour.ignorePrompt),
    );
    final store = MemoryCredentialStore();
    final controller = controllerFor(
      store,
      timeouts: const SsapTimeouts(pairing: Duration(milliseconds: 150)),
    );
    addTearDown(controller.dispose);

    final result = await controller.connect(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
    );

    expect(result, isNull);
    expect(controller.current.phase, PairingPhase.timedOut);
    expect(controller.current.error?.code, 'pairing_timeout');
    expect(await store.readAll(), isEmpty);
  });

  test('an unreachable TV ends in failed with a typed error', () async {
    final controller = controllerFor(MemoryCredentialStore());
    addTearDown(controller.dispose);

    final result = await controller.connect(
      host: '127.0.0.1',
      port: 1,
      secure: false,
    );

    expect(result, isNull);
    expect(controller.current.phase, PairingPhase.failed);
    expect(controller.current.error, isNotNull);
  });

  test('two concurrent connects put a single prompt on the TV', () async {
    final tv = await startTv(MockTvConfig());
    final controller = controllerFor(MemoryCredentialStore());
    addTearDown(controller.dispose);

    final first = controller.connect(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
    );
    final second = controller.connect(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
    );

    expect(identical(first, second), isTrue);
    final results = await Future.wait(<Future<PairedTv?>>[first, second]);

    expect(results.whereType<PairedTv>(), hasLength(2));
    expect(tv.pairingPrompts, 1);
  });

  test('a competing host is ignored while an attempt is in flight', () async {
    final tv = await startTv(MockTvConfig());
    final controller = controllerFor(MemoryCredentialStore());
    addTearDown(controller.dispose);

    final first = controller.connect(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
    );
    final competing = await controller.connect(
      host: '192.0.2.55',
      port: tv.port,
      secure: false,
    );

    expect(competing, isNull);
    expect(await first, isNotNull);
    expect(tv.pairingPrompts, 1);
  });

  test('forget drops the stored key and closes the session', () async {
    final tv = await startTv(MockTvConfig());
    final store = MemoryCredentialStore();
    final controller = controllerFor(store);
    addTearDown(controller.dispose);

    final paired = await controller.connect(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
    );

    await controller.forget('127.0.0.1');

    expect(controller.current.phase, PairingPhase.idle);
    expect(controller.activeTv, isNull);
    expect(await store.read('127.0.0.1'), isNull);
    expect(paired!.session.isOpen, isFalse);
  });

  test('an unreadable credential does not block a fresh pairing', () async {
    final tv = await startTv(MockTvConfig());
    final controller = controllerFor(_ThrowingReadStore());
    addTearDown(controller.dispose);

    final result = await controller.connect(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
    );

    expect(result, isNotNull);
    expect(controller.current.phase, PairingPhase.paired);
  });

  test('keys never reach diagnostics strings or the log sink', () async {
    final tv = await startTv(MockTvConfig());
    final store = MemoryCredentialStore();
    final lines = <String>[];
    final logger = SsapLogger(enabled: true, sink: lines.add);
    final controller = controllerFor(store, logger: logger);
    addTearDown(controller.dispose);

    final paired = await controller.connect(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
    );
    final key = paired!.credential.clientKey;

    logger.debug('{"type":"registered","payload":{"client-key":"$key"}}');

    expect(lines.single, isNot(contains(key)));
    expect(controller.current.toString(), isNot(contains(key)));
    expect(controller.current.credential.toString(), isNot(contains(key)));
    expect(paired.credential.toString(), isNot(contains(key)));
    expect(lines.where((line) => line.contains(key)), isEmpty);
  });
}

class _ThrowingReadStore implements CredentialStore {
  @override
  Future<TvCredential?> read(String host) =>
      Future<TvCredential?>.error(StateError('keystore unavailable'));

  @override
  Future<void> write(TvCredential credential) async {}

  @override
  Future<void> delete(String host) async {}

  @override
  Future<List<TvCredential>> readAll() async => const <TvCredential>[];
}
