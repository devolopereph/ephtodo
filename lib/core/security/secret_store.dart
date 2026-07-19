import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> clearSyncSecrets();
}

final class WindowsSecretStore implements SecretStore {
  const WindowsSecretStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const _prefix = 'ephtodo.sync.';
  static const _knownKeys = {
    'passwordVerifier',
    'tlsCertificate',
    'tlsPrivateKey',
  };

  @override
  Future<String?> read(String key) {
    _checkKey(key);
    return _storage.read(key: '$_prefix$key');
  }

  @override
  Future<void> write(String key, String value) {
    _checkKey(key);
    return _storage.write(key: '$_prefix$key', value: value);
  }

  @override
  Future<void> delete(String key) {
    _checkKey(key);
    return _storage.delete(key: '$_prefix$key');
  }

  @override
  Future<void> clearSyncSecrets() async {
    for (final key in _knownKeys) {
      await _storage.delete(key: '$_prefix$key');
    }
  }

  static void _checkKey(String key) {
    if (!_knownKeys.contains(key)) {
      throw ArgumentError.value(key, 'key', 'Unknown sync secret key');
    }
  }
}

final class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String>? seed]) : _values = {...?seed};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> clearSyncSecrets() async => _values.clear();
}
