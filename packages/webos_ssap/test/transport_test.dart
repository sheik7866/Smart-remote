import 'dart:io';

import 'package:mock_webos_tv/mock_webos_tv.dart';
import 'package:test/test.dart';
import 'package:webos_ssap/webos_ssap.dart';

import 'support.dart';

void main() {
  test('native policy accepts the self-signed certificate', () async {
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
    final transport = IoWebSocketTransport(tv.wsUri);
    addTearDown(transport.close);

    await transport.connect();

    expect(transport.isConnected, isTrue);
    expect(transport.certificateFingerprint, isNotNull);
  });

  test('strict policy rejects the self-signed certificate', () async {
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
    final transport = IoWebSocketTransport(
      tv.wsUri,
      policy: CertificatePolicy.strict,
    );
    addTearDown(transport.close);

    await expectLater(
      transport.connect(),
      throwsA(isA<TransportException>()
          .having((e) => e.kind, 'kind', TransportErrorKind.tlsRejected)),
    );
  });

  test('a closed port is reported as unreachable', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final transport = IoWebSocketTransport(
      Uri.parse('ws://127.0.0.1:$port'),
      connectTimeout: const Duration(seconds: 1),
    );
    addTearDown(transport.close);

    await expectLater(
      transport.connect(),
      throwsA(isA<TransportException>().having(
        (e) => e.kind,
        'kind',
        anyOf(TransportErrorKind.unreachable, TransportErrorKind.timeout),
      )),
    );
  });
}
