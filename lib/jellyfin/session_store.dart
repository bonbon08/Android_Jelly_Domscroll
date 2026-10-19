import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'jellyfin_models.dart';

/// Persists the Jellyfin session (server, token, user id) across app starts.
class SessionStore {
  static const _storage = FlutterSecureStorage();
  static const _keyServer = 'jf_server_url';
  static const _keyToken = 'jf_access_token';
  static const _keyUser = 'jf_user_id';

  static Future<void> save(JellyfinSession session) async {
    await _storage.write(key: _keyServer, value: session.serverUrl);
    await _storage.write(key: _keyToken, value: session.accessToken);
    await _storage.write(key: _keyUser, value: session.userId);
  }

  static Future<JellyfinSession?> load() async {
    final server = await _storage.read(key: _keyServer);
    final token = await _storage.read(key: _keyToken);
    final user = await _storage.read(key: _keyUser);
    if (server == null || token == null || user == null) return null;
    return JellyfinSession(serverUrl: server, accessToken: token, userId: user);
  }

  static const _keyDevice = 'jf_device_id';

  /// Returns the persisted device id, creating it with [create] on first use.
  /// Kept across logouts so the server keeps recognising this device.
  static Future<String> deviceId(String Function() create) async {
    final existing = await _storage.read(key: _keyDevice);
    if (existing != null) return existing;
    final id = create();
    await _storage.write(key: _keyDevice, value: id);
    return id;
  }

  static Future<void> clear() async {
    await _storage.delete(key: _keyServer);
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyUser);
  }
}
