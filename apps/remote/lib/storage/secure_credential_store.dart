import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webos_ssap/webos_ssap.dart';

/// The tiny key/value surface the store needs.
///
/// Kept separate from the plugin so the encoding, corruption handling and key
/// naming can be tested without a platform channel.
abstract class SecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  Future<Map<String, String>> readAll();
}

/// [SecureKeyValueStore] over `flutter_secure_storage`.
///
/// iOS/macOS use a Keychain generic-password item that is this-device-only,
/// readable after the first unlock and never synchronised to iCloud. Android
/// uses AES-GCM under a Keystore-held key. Linux (desktop development only)
/// falls back to libsecret.
///
/// Browsers are refused here on purpose: architecture §6.3 and §8 require the
/// web client to keep keys in memory for the page's lifetime only.
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  factory FlutterSecureKeyValueStore({FlutterSecureStorage? storage}) {
    if (kIsWeb) {
      throw UnsupportedError(
        'TV keys must not be persisted in a browser; use MemoryCredentialStore.',
      );
    }
    return FlutterSecureKeyValueStore._(
      storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
              synchronizable: false,
            ),
          ),
    );
  }

  FlutterSecureKeyValueStore._(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}

/// [CredentialStore] that keeps one JSON record per TV in platform storage.
///
/// The UI never sees the raw record: the key stays inside the encrypted store
/// and only [TvCredential] objects cross this boundary.
class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore(this.backend);

  final SecureKeyValueStore backend;

  /// Namespace for the records, so unrelated secure-storage entries are ignored.
  static const String keyPrefix = 'lg_tv_credential.';

  static String storageKey(String host) => '$keyPrefix$host';

  @override
  Future<TvCredential?> read(String host) async {
    final raw = await backend.read(storageKey(host));
    if (raw == null) return null;
    return _decode(raw);
  }

  @override
  Future<void> write(TvCredential credential) async {
    await backend.write(
      storageKey(credential.host),
      jsonEncode(_encode(credential)),
    );
  }

  @override
  Future<void> delete(String host) => backend.delete(storageKey(host));

  /// Corrupt or partially written records are skipped rather than thrown: a
  /// lost credential must degrade to a fresh pairing, never to a crash.
  @override
  Future<List<TvCredential>> readAll() async {
    final stored = await backend.readAll();
    final credentials = <TvCredential>[];
    for (final entry in stored.entries) {
      if (!entry.key.startsWith(keyPrefix)) continue;
      final credential = _decode(entry.value);
      if (credential != null) credentials.add(credential);
    }
    return credentials;
  }

  Map<String, dynamic> _encode(TvCredential credential) => <String, dynamic>{
        'host': credential.host,
        'port': credential.port,
        'secure': credential.secure,
        'clientKey': credential.clientKey,
        if (credential.modelName != null) 'modelName': credential.modelName,
        if (credential.fingerprint != null) 'fingerprint': credential.fingerprint,
        if (credential.lastSeen != null)
          'lastSeen': credential.lastSeen!.toUtc().toIso8601String(),
      };

  TvCredential? _decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final host = decoded['host'];
    final port = decoded['port'];
    final secure = decoded['secure'];
    final clientKey = decoded['clientKey'];
    if (host is! String || host.isEmpty) return null;
    if (port is! int || port <= 0 || port > 65535) return null;
    if (secure is! bool) return null;
    if (clientKey is! String || clientKey.isEmpty) return null;

    final modelName = decoded['modelName'];
    final fingerprint = decoded['fingerprint'];
    final lastSeen = decoded['lastSeen'];

    return TvCredential(
      host: host,
      port: port,
      secure: secure,
      clientKey: clientKey,
      modelName: modelName is String ? modelName : null,
      fingerprint: fingerprint is String ? fingerprint : null,
      lastSeen: lastSeen is String ? DateTime.tryParse(lastSeen) : null,
    );
  }
}

/// The store for the current platform.
///
/// Native builds get Keychain/Keystore. The browser gets session memory only,
/// which is the documented, honest limitation rather than a silent downgrade.
CredentialStore createCredentialStore() {
  if (kIsWeb) return MemoryCredentialStore();
  return SecureCredentialStore(FlutterSecureKeyValueStore());
}
