import 'package:flutter_test/flutter_test.dart';
import 'package:smart_remote/storage/secure_credential_store.dart';
import 'package:webos_ssap/webos_ssap.dart';

class FakeSecureStorage implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};
  int writes = 0;

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.of(values);

  @override
  Future<void> write(String key, String value) async {
    writes += 1;
    values[key] = value;
  }
}

void main() {
  final credential = TvCredential(
    host: '192.168.1.42',
    port: 3001,
    secure: true,
    clientKey: 'client-key-secret',
    modelName: 'OLED55C1',
    fingerprint: 'AA:BB:CC:DD',
    lastSeen: DateTime.utc(2026, 11, 19, 12, 30),
  );

  late FakeSecureStorage backend;
  late SecureCredentialStore store;

  setUp(() {
    backend = FakeSecureStorage();
    store = SecureCredentialStore(backend);
  });

  test('round-trips every credential field', () async {
    await store.write(credential);

    final restored = await store.read('192.168.1.42');

    expect(restored, isNotNull);
    expect(restored!.host, credential.host);
    expect(restored.port, credential.port);
    expect(restored.secure, credential.secure);
    expect(restored.clientKey, credential.clientKey);
    expect(restored.modelName, credential.modelName);
    expect(restored.fingerprint, credential.fingerprint);
    expect(restored.lastSeen, credential.lastSeen);
    expect(restored.lastSeen!.isUtc, isTrue);
  });

  test('namespaces the storage key and never embeds the client key', () async {
    await store.write(credential);

    expect(backend.values.keys.single, 'lg_tv_credential.192.168.1.42');
    expect(
      backend.values.keys.single,
      isNot(contains(credential.clientKey)),
      reason: 'the key belongs in the value, never in an indexable name',
    );
  });

  test('overwrites the record for the same host', () async {
    await store.write(credential);
    await store.write(credential.copyWith(
      clientKey: 'second-key',
      port: 3000,
      secure: false,
    ));

    expect(backend.values, hasLength(1));
    final restored = await store.read('192.168.1.42');
    expect(restored!.clientKey, 'second-key');
    expect(restored.port, 3000);
    expect(restored.secure, isFalse);
  });

  test('delete removes only the requested TV', () async {
    await store.write(credential);
    await store.write(credential.copyWith(host: '192.168.1.43'));

    await store.delete('192.168.1.42');

    expect(await store.read('192.168.1.42'), isNull);
    expect(await store.read('192.168.1.43'), isNotNull);
  });

  test('readAll returns every TV and ignores foreign entries', () async {
    await store.write(credential);
    await store.write(credential.copyWith(host: '192.168.1.43'));
    backend.values['some_other_setting'] = '{"hello":"world"}';

    final all = await store.readAll();

    expect(
      all.map((c) => c.host),
      unorderedEquals(<String>['192.168.1.42', '192.168.1.43']),
    );
  });

  test('a truncated record reads as missing instead of throwing', () async {
    backend.values[SecureCredentialStore.storageKey('192.168.1.42')] =
        '{"host":"192.168.1.42",';

    expect(await store.read('192.168.1.42'), isNull);
  });

  test('a record missing the client key is rejected', () async {
    backend.values[SecureCredentialStore.storageKey('192.168.1.42')] =
        '{"host":"192.168.1.42","port":3001,"secure":true}';

    expect(await store.read('192.168.1.42'), isNull);
  });
}
