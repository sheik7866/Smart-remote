import 'credential.dart';

/// Session-only [CredentialStore].
///
/// Used by tests and by the browser client: architecture §6.3 and §8 forbid
/// persisting a TV key in a browser, so the web build keeps it in memory for
/// the lifetime of the page and re-pairs on reload.
class MemoryCredentialStore implements CredentialStore {
  final Map<String, TvCredential> _data = <String, TvCredential>{};

  @override
  Future<TvCredential?> read(String host) async => _data[host];

  @override
  Future<void> write(TvCredential credential) async {
    _data[credential.host] = credential;
  }

  @override
  Future<void> delete(String host) async {
    _data.remove(host);
  }

  @override
  Future<List<TvCredential>> readAll() async =>
      _data.values.toList(growable: false);
}
