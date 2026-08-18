import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final kitchenRemoteSessionStoreProvider =
    Provider<KitchenRemoteSessionStore>((ref) {
  return const KitchenRemoteSessionStore(FlutterSecureStorage());
});

class KitchenRemoteSessionStore {
  const KitchenRemoteSessionStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _sessionTokenKey = 'kds_remote_session_token';

  Future<void> saveToken(String token) async {
    await _storage.write(key: _sessionTokenKey, value: token);
  }

  Future<String?> readToken() async {
    final token = await _storage.read(key: _sessionTokenKey);
    if (token == null || token.trim().isEmpty) {
      return null;
    }
    return token;
  }

  Future<void> clearToken() async {
    await _storage.delete(key: _sessionTokenKey);
  }
}
