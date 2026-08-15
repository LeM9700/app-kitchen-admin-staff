import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/admin_users/data/admin_users_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('list users parses paginated backend response and query filters',
      () async {
    late RequestOptions seenOptions;
    final repository = _repository((options) {
      seenOptions = options;
      return _jsonResponse({
        'items': [
          {
            'id': 2,
            'email': 'staff@test.com',
            'full_name': 'Staff Test',
            'role': 'staff',
            'permissions': ['orders:read'],
            'is_active': true,
            'email_verified': true,
            'created_at': '2026-08-10T10:00:00Z',
            'must_change_password': true,
          },
        ],
        'total': 1,
        'page': 1,
        'page_size': 50,
        'pages': 1,
      });
    });

    final page = await repository.listUsers(
      const AdminUsersQuery(role: 'staff', isActive: true),
    );

    expect(seenOptions.path, ApiEndpoints.adminUsers);
    expect(seenOptions.queryParameters['role'], 'staff');
    expect(seenOptions.queryParameters['is_active'], true);
    expect(page.items.single.email, 'staff@test.com');
    expect(page.items.single.mustChangePassword, isTrue);
  });

  test('create user returns temporary password once', () async {
    late Map<String, dynamic> body;
    final repository = _repository((options) {
      body = Map<String, dynamic>.from(options.data as Map);
      return _jsonResponse(
        {
          'id': 3,
          'email': 'new@test.com',
          'role': 'staff',
          'temporary_password': 'Temp123',
        },
        statusCode: 201,
      );
    });

    final created = await repository.createUser(
      const AdminUserCreateDraft(
        email: 'new@test.com',
        role: 'staff',
        permissions: ['orders:read'],
      ),
    );

    expect(body['email'], 'new@test.com');
    expect(body['role'], 'staff');
    expect(created.temporaryPassword, 'Temp123');
  });

  test('email conflict is exposed as ConflictException', () async {
    final repository = _repository((options) {
      return _jsonResponse(
        {
          'code': 'EMAIL_EXISTS',
          'detail': 'Email already registered',
          'field': 'email',
        },
        statusCode: 409,
      );
    });

    await expectLater(
      repository.createUser(
        const AdminUserCreateDraft(email: 'dupe@test.com', role: 'staff'),
      ),
      throwsA(isA<ConflictException>()),
    );
  });

  test('permissions update uses backend permissions route', () async {
    late RequestOptions seenOptions;
    final repository = _repository((options) {
      seenOptions = options;
      return _jsonResponse({
        'id': 4,
        'email': 'staff@test.com',
        'full_name': null,
        'role': 'staff',
        'permissions': ['orders:read', 'stock:read'],
        'is_active': true,
        'email_verified': true,
        'created_at': '2026-08-10T10:00:00Z',
        'must_change_password': false,
      });
    });

    final updated = await repository.updatePermissions(
      4,
      ['orders:read', 'stock:read'],
    );

    expect(seenOptions.path, ApiEndpoints.adminUserPermissions(4));
    expect(updated.permissions, contains('stock:read'));
  });
}

AdminUsersRepository _repository(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = _FakeAdapter(handler);
  return AdminUsersRepository(
    ApiClient(
      dio,
      _MemoryTokenStore(),
    ),
  );
}

ResponseBody _jsonResponse(
  Map<String, dynamic> body, {
  int statusCode = 200,
}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _MemoryTokenStore extends TokenStore {
  _MemoryTokenStore() : super(const FlutterSecureStorage());

  @override
  Future<String?> readAccessToken() async => 'access';

  @override
  Future<String?> readRefreshToken() async => 'refresh';

  @override
  Future<String?> readTenantSlug() async => 'pizza';
}
