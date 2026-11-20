import 'package:mock_webos_tv/mock_webos_tv.dart';
import 'package:test/test.dart';
import 'package:webos_ssap/webos_ssap.dart';

import 'support.dart';

void main() {
  test('pairs after the on-screen prompt and returns the key', () async {
    final tv = await startTv(MockTvConfig());
    final store = MemoryCredentialStore();
    final service = PairingService(transports: ioTransport, store: store);
    addTearDown(() async {});

    final pairedTv = await service.pair(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
    );
    addTearDown(pairedTv.dispose);

    expect(tv.pairingPrompts, 1);
    expect(pairedTv.credential.clientKey, tv.issuedClientKey);
    expect(pairedTv.credential.secure, isFalse);
    expect(pairedTv.credential.port, tv.port);
    expect((await store.read('127.0.0.1'))?.clientKey, tv.issuedClientKey);
  });

  test('a stored key restores the session without a prompt', () async {
    final tv = await startTv(MockTvConfig());
    final service = PairingService(transports: ioTransport);

    final first = await service.pair(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
    );
    final key = first.credential.clientKey;
    await first.dispose();

    final second = await service.pair(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
      knownClientKey: key,
    );
    addTearDown(second.dispose);

    expect(second.credential.clientKey, key);
    expect(tv.pairingPrompts, 1, reason: 'restore must not prompt again');
  });

  test('a denied prompt surfaces as pairing_denied', () async {
    final tv = await startTv(MockTvConfig(pairing: PairingBehaviour.deny));
    final service = PairingService(transports: ioTransport);

    await expectLater(
      service.pair(host: '127.0.0.1', port: tv.port, secure: false),
      throwsA(isA<SsapError>()
          .having((e) => e.code, 'code', 'pairing_denied')
          .having((e) => e.kind, 'kind', SsapErrorKind.auth)),
    );
  });

  test('an ignored prompt times out instead of hanging', () async {
    final tv = await startTv(
      MockTvConfig(pairing: PairingBehaviour.ignorePrompt),
    );
    final service = PairingService(
      transports: ioTransport,
      timeouts: const SsapTimeouts(pairing: Duration(milliseconds: 150)),
    );

    await expectLater(
      service.pair(host: '127.0.0.1', port: tv.port, secure: false),
      throwsA(isA<SsapError>().having((e) => e.code, 'code', 'pairing_timeout')),
    );
  });

  test('a revoked key is reported as key_revoked, not as a new pairing',
      () async {
    final tv = await startTv(MockTvConfig());
    final service = PairingService(transports: ioTransport);

    final first = await service.pair(
      host: '127.0.0.1',
      port: tv.port,
      secure: false,
    );
    final key = first.credential.clientKey;
    await first.dispose();

    tv.revokeClientKeys();

    await expectLater(
      service.pair(
        host: '127.0.0.1',
        port: tv.port,
        secure: false,
        knownClientKey: key,
      ),
      throwsA(isA<SsapError>().having((e) => e.code, 'code', 'key_revoked')),
    );
  });

  test('falls back from secure to plain when wss is refused', () async {
    final tv = await startTv(MockTvConfig());
    final service = PairingService(
      transports: ioTransport,
      securePort: 1,
      plainPort: tv.port,
    );

    final pairedTv = await service.pair(host: '127.0.0.1');
    addTearDown(pairedTv.dispose);

    expect(pairedTv.credential.secure, isFalse);
    expect(pairedTv.credential.port, tv.port);
  });

  test('connects over wss and records the certificate fingerprint', () async {
    final certificate = await selfSignedCertificate();
    if (certificate == null) {
      markTestSkipped('openssl unavailable');
      return;
    }

    final tv = await startTv(MockTvConfig(
      secure: true,
      certificatePath: certificate.cert,
      privateKeyPath: certificate.key,
    ));
    final service = PairingService(
      transports: ioTransport,
      securePort: tv.port,
      plainPort: 1,
    );

    final pairedTv = await service.pair(host: '127.0.0.1');
    addTearDown(pairedTv.dispose);

    expect(pairedTv.credential.secure, isTrue);
    expect(pairedTv.credential.fingerprint, isNotNull);
  });
}
