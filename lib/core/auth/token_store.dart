import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) {
  return const TokenStore(FlutterSecureStorage());
});

class StoredTokens {
  const StoredTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.tenantSlug,
    required this.sessionId,
  });

  final String accessToken;
  final String refreshToken;
  final String tenantSlug;
  final int sessionId;
}

class TokenStore {
  const TokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'admin_staff_access_token';
  static const _refreshTokenKey = 'admin_staff_refresh_token';
  static const _tenantSlugKey = 'admin_staff_tenant_slug';
  static const _sessionIdKey = 'admin_staff_session_id';

  Future<StoredTokens?> read() async {
    final access = await _storage.read(key: _accessTokenKey);
    final refresh = await _storage.read(key: _refreshTokenKey);
    final tenant = await _storage.read(key: _tenantSlugKey);
    final sessionId = int.tryParse(
      await _storage.read(key: _sessionIdKey) ?? '',
    );
    if (access == null ||
        refresh == null ||
        tenant == null ||
        sessionId == null) {
      return null;
    }
    return StoredTokens(
      accessToken: access,
      refreshToken: refresh,
      tenantSlug: tenant,
      sessionId: sessionId,
    );
  }

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<String?> readTenantSlug() => _storage.read(key: _tenantSlugKey);

  Future<void> write(StoredTokens tokens) async {
    await _storage.write(key: _accessTokenKey, value: tokens.accessToken);
    await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
    await _storage.write(key: _tenantSlugKey, value: tokens.tenantSlug);
    await _storage.write(
      key: _sessionIdKey,
      value: tokens.sessionId.toString(),
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _tenantSlugKey);
    await _storage.delete(key: _sessionIdKey);
  }
}
