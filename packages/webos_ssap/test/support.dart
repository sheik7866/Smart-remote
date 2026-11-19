import 'dart:async';
import 'dart:io';

import 'package:mock_webos_tv/mock_webos_tv.dart';
import 'package:test/test.dart';
import 'package:webos_ssap/webos_ssap.dart';

const SsapTimeouts fastTimeouts = SsapTimeouts(
  request: Duration(milliseconds: 400),
  pairing: Duration(milliseconds: 600),
  subscription: Duration(milliseconds: 400),
);

SsapTransport ioTransport(
  Uri endpoint, {
  CertificatePolicy policy = CertificatePolicy.native,
}) =>
    IoWebSocketTransport(endpoint, policy: policy);

Future<MockWebOsTv> startTv(MockTvConfig config) async {
  final tv = MockWebOsTv(config);
  await tv.start();
  addTearDown(tv.stop);
  return tv;
}

Future<SsapSession> connected(
  MockWebOsTv tv, {
  SsapTimeouts timeouts = fastTimeouts,
  SsapLogger logger = const SsapLogger(),
}) async {
  final session = SsapSession(
    transport: ioTransport(tv.wsUri),
    timeouts: timeouts,
    logger: logger,
  );
  await session.connect();
  addTearDown(session.close);
  return session;
}

Future<SsapSession> paired(
  MockWebOsTv tv, {
  SsapTimeouts timeouts = fastTimeouts,
  SsapLogger logger = const SsapLogger(),
}) async {
  final session = await connected(tv, timeouts: timeouts, logger: logger);
  final outcome = await session.register(manifest: defaultManifest);
  expect(
    outcome.isSuccess,
    isTrue,
    reason: 'register failed: ${outcome.status} ${outcome.error}',
  );
  return session;
}

/// In-memory credential store for pairing tests.
class MemoryCredentialStore implements CredentialStore {
  final Map<String, TvCredential> data = <String, TvCredential>{};

  @override
  Future<void> delete(String host) async => data.remove(host);

  @override
  Future<TvCredential?> read(String host) async => data[host];

  @override
  Future<List<TvCredential>> readAll() async => data.values.toList();

  @override
  Future<void> write(TvCredential credential) async {
    data[credential.host] = credential;
  }
}

Future<({String cert, String key})?>? _certificate;

/// Generates a throwaway self-signed certificate, or null when openssl is
/// unavailable (the TLS tests then skip instead of failing).
Future<({String cert, String key})?> selfSignedCertificate() {
  return _certificate ??= _generate();
}

Future<({String cert, String key})?> _generate() async {
  final directory = await Directory.systemTemp.createTemp('mocktv-cert');
  final certPath = '${directory.path}/cert.pem';
  final keyPath = '${directory.path}/key.pem';
  try {
    final result = await Process.run('openssl', <String>[
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      keyPath,
      '-out',
      certPath,
      '-days',
      '1',
      '-subj',
      '/CN=lgwebostv.local',
    ]);
    if (result.exitCode != 0) return null;
  } on ProcessException {
    return null;
  }
  return (cert: certPath, key: keyPath);
}

/// A transport with no socket, for timeout and lifecycle tests.
class FakeTransport implements SsapTransport {
  final StreamController<String> _messages = StreamController<String>();
  final List<String> sent = <String>[];
  bool _connected = false;

  void deliver(String frame) {
    if (!_messages.isClosed) _messages.add(frame);
  }

  @override
  Future<void> connect() async {
    _connected = true;
  }

  @override
  Future<void> send(String frame) async {
    sent.add(frame);
  }

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> close() async {
    _connected = false;
    if (!_messages.isClosed) await _messages.close();
  }

  @override
  bool get isConnected => _connected;

  @override
  Uri get endpoint => Uri.parse('ws://fake-tv:3000');

  @override
  String? get certificateFingerprint => null;
}
