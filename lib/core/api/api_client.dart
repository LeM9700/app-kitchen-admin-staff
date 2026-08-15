import 'dart:async';

import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/auth/session_events.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/core/config/env.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    Dio(
      BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
      ),
    ),
    ref.watch(tokenStoreProvider),
    onSessionExpired: () {
      ref.read(sessionInvalidationProvider.notifier).state++;
    },
  );
});

class ApiClient {
  ApiClient(
    this._dio,
    this._tokenStore, {
    FutureOr<void> Function()? onSessionExpired,
  }) : _onSessionExpired = onSessionExpired;

  final Dio _dio;
  final TokenStore _tokenStore;
  final FutureOr<void> Function()? _onSessionExpired;
  Future<bool>? _refreshFuture;

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    bool authenticated = true,
    ResponseType? responseType,
  }) {
    return _request(
      'GET',
      path,
      queryParameters: queryParameters,
      headers: headers,
      authenticated: authenticated,
      responseType: responseType,
    );
  }

  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    String? idempotencyKey,
    bool authenticated = true,
  }) {
    return _request(
      'POST',
      path,
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      idempotencyKey: idempotencyKey,
      authenticated: authenticated,
    );
  }

  Future<Response<dynamic>> patch(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    String? idempotencyKey,
    bool authenticated = true,
  }) {
    return _request(
      'PATCH',
      path,
      data: data,
      queryParameters: queryParameters,
      headers: headers,
      idempotencyKey: idempotencyKey,
      authenticated: authenticated,
    );
  }

  Future<Response<dynamic>> put(
    String path, {
    Object? data,
    Map<String, dynamic>? headers,
    String? idempotencyKey,
    bool authenticated = true,
  }) {
    return _request(
      'PUT',
      path,
      data: data,
      headers: headers,
      idempotencyKey: idempotencyKey,
      authenticated: authenticated,
    );
  }

  Future<Response<dynamic>> delete(
    String path, {
    Object? data,
    Map<String, dynamic>? headers,
    String? idempotencyKey,
    bool authenticated = true,
  }) {
    return _request(
      'DELETE',
      path,
      data: data,
      headers: headers,
      idempotencyKey: idempotencyKey,
      authenticated: authenticated,
    );
  }

  Future<String> getText(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    final response = await get(
      path,
      queryParameters: queryParameters,
      authenticated: authenticated,
      responseType: ResponseType.plain,
    );
    return response.data?.toString() ?? '';
  }

  Future<bool> refreshSession() {
    return _refresh();
  }

  Future<Response<dynamic>> _request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
    String? idempotencyKey,
    required bool authenticated,
    ResponseType? responseType,
    bool alreadyRetried = false,
  }) async {
    final requestHeaders = await _headersFor(
      authenticated: authenticated,
      headers: headers,
      idempotencyKey: idempotencyKey,
    );
    try {
      _logDev('$method $path requestId=${requestHeaders['X-Request-ID']}');
      return await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: requestHeaders,
          responseType: responseType,
        ),
      );
    } on DioException catch (error) {
      final isRefreshRequest = path == ApiEndpoints.authRefresh;
      if (!alreadyRetried &&
          authenticated &&
          !isRefreshRequest &&
          error.response?.statusCode == 401) {
        final refreshed = await _refresh();
        if (refreshed) {
          return _request(
            method,
            path,
            data: data,
            queryParameters: queryParameters,
            headers: headers,
            idempotencyKey: idempotencyKey,
            authenticated: authenticated,
            responseType: responseType,
            alreadyRetried: true,
          );
        }
      }
      throw appExceptionFromDio(error);
    }
  }

  Future<Map<String, dynamic>> _headersFor({
    required bool authenticated,
    Map<String, dynamic>? headers,
    String? idempotencyKey,
  }) async {
    final requestId =
        headers?['X-Request-ID']?.toString() ?? RequestIds.generate();
    final result = <String, dynamic>{
      ...?headers,
      'X-Request-ID': requestId,
    };
    if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty) {
      result['Idempotency-Key'] = idempotencyKey;
    }
    if (authenticated) {
      final token = await _tokenStore.readAccessToken();
      if (token != null) {
        result['Authorization'] = 'Bearer $token';
      }
    } else {
      result.remove('Authorization');
    }
    return result;
  }

  Future<bool> _refresh() async {
    final ongoingRefresh = _refreshFuture;
    if (ongoingRefresh != null) {
      return ongoingRefresh;
    }

    final refresh = _performRefresh();
    _refreshFuture = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshFuture, refresh)) {
        _refreshFuture = null;
      }
    }
  }

  Future<bool> _performRefresh() async {
    try {
      final refreshToken = await _tokenStore.readRefreshToken();
      final tenantSlug = await _tokenStore.readTenantSlug();
      if (refreshToken == null || tenantSlug == null) {
        await _expireSession();
        return false;
      }
      final requestId = RequestIds.generate();
      _logDev('refresh start requestId=$requestId');
      final response = await _dio.post<dynamic>(
        ApiEndpoints.authRefresh,
        data: {'refresh_token': refreshToken},
        options: Options(
          headers: {'X-Request-ID': requestId},
        ),
      );
      final tokens = AuthTokens.fromJson(response.data as Map<String, dynamic>);
      await _tokenStore.write(
        StoredTokens(
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          tenantSlug: tenantSlug,
          sessionId: tokens.sessionId,
        ),
      );
      _logDev('refresh success sessionId=${tokens.sessionId}');
      return true;
    } catch (_) {
      _logDev('refresh failed');
      await _expireSession();
      return false;
    }
  }

  Future<void> _expireSession() async {
    await _tokenStore.clear();
    await _onSessionExpired?.call();
  }

  void _logDev(String message) {
    if (kDebugMode) {
      debugPrint('[api] $message');
    }
  }
}

class RequestIds {
  RequestIds._();

  static int _counter = 0;

  static String generate() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    _counter = (_counter + 1) % 1000000;
    return 'req-$timestamp-$_counter';
  }
}
