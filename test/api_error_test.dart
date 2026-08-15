import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps 403 forbidden with backend code and request id', () {
    final error = _map(
      403,
      {'code': 'FORBIDDEN', 'detail': 'Nope', 'field': 'role'},
    );

    expect(error, isA<ForbiddenException>());
    expect(error.code, 'FORBIDDEN');
    expect(error.field, 'role');
    expect(error.requestId, 'req-123');
  });

  test('maps 409 conflict', () {
    expect(_map(409, {'code': 'CONFLICT'}), isA<ConflictException>());
  });

  test('maps 422 custom AppError', () {
    final error = _map(
      422,
      {'code': 'VALIDATION_ERROR', 'detail': 'Bad field', 'field': 'email'},
    );

    expect(error, isA<ValidationException>());
    expect(error.code, 'VALIDATION_ERROR');
    expect(error.field, 'email');
  });

  test('maps 422 FastAPI validation detail', () {
    final error = _map(
      422,
      {
        'detail': [
          {
            'loc': ['body', 'email'],
            'msg': 'value is not a valid email',
            'type': 'value_error',
          },
        ],
      },
    );

    expect(error, isA<ValidationException>());
    expect(error.code, 'value_error');
    expect(error.field, 'email');
  });

  test('maps 429 with retry after', () {
    final error = _map(
      429,
      {'detail': 'Too many'},
      headers: {
        'retry-after': ['12'],
      },
    );

    expect(error, isA<RateLimitException>());
    expect(error.retryAfterSeconds, 12);
  });

  test('maps 503 and other 5xx as server exceptions', () {
    expect(_map(503, {'detail': 'Down'}), isA<ServerException>());
    expect(_map(500, {'detail': 'Boom'}), isA<ServerException>());
  });
}

AppException _map(
  int statusCode,
  Object data, {
  Map<String, List<String>> headers = const {},
}) {
  return appExceptionFromDio(
    DioException(
      requestOptions: RequestOptions(
        path: '/test',
        headers: {'X-Request-ID': 'req-fallback'},
      ),
      response: Response<Object>(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: statusCode,
        data: data,
        headers: Headers.fromMap({
          'x-request-id': ['req-123'],
          ...headers,
        }),
      ),
    ),
  );
}
