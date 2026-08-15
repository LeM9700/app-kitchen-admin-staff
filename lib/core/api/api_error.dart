import 'package:dio/dio.dart';

abstract class AppException implements Exception {
  const AppException({
    required this.message,
    this.code,
    this.statusCode,
    this.field,
    this.requestId,
    this.retryAfterSeconds,
  });

  final String message;
  final String? code;
  final int? statusCode;
  final String? field;
  final String? requestId;
  final int? retryAfterSeconds;

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  const NetworkException({
    required super.message,
    super.code,
    super.statusCode,
    super.field,
    super.requestId,
    super.retryAfterSeconds,
  });
}

class BusinessException extends AppException {
  const BusinessException({
    required super.message,
    super.code,
    super.statusCode,
    super.field,
    super.requestId,
    super.retryAfterSeconds,
  });
}

class UnauthorizedException extends BusinessException {
  const UnauthorizedException({
    required super.message,
    super.code,
    super.statusCode,
    super.field,
    super.requestId,
    super.retryAfterSeconds,
  });
}

class ForbiddenException extends BusinessException {
  const ForbiddenException({
    required super.message,
    super.code,
    super.statusCode,
    super.field,
    super.requestId,
    super.retryAfterSeconds,
  });
}

class ValidationException extends BusinessException {
  const ValidationException({
    required super.message,
    super.code,
    super.statusCode,
    super.field,
    super.requestId,
    super.retryAfterSeconds,
  });
}

class ConflictException extends BusinessException {
  const ConflictException({
    required super.message,
    super.code,
    super.statusCode,
    super.field,
    super.requestId,
    super.retryAfterSeconds,
  });
}

class RateLimitException extends BusinessException {
  const RateLimitException({
    required super.message,
    super.code,
    super.statusCode,
    super.field,
    super.requestId,
    super.retryAfterSeconds,
  });
}

class ServerException extends AppException {
  const ServerException({
    required super.message,
    super.code,
    super.statusCode,
    super.field,
    super.requestId,
    super.retryAfterSeconds,
  });
}

class ApiError extends BusinessException {
  const ApiError({
    required super.message,
    super.code,
    super.statusCode,
    super.field,
    super.requestId,
    super.retryAfterSeconds,
  });

  factory ApiError.fromDio(DioException error) {
    final mapped = appExceptionFromDio(error);
    return ApiError(
      message: mapped.message,
      code: mapped.code,
      statusCode: mapped.statusCode,
      field: mapped.field,
      requestId: mapped.requestId,
      retryAfterSeconds: mapped.retryAfterSeconds,
    );
  }
}

AppException appExceptionFromDio(DioException error) {
  final response = error.response;
  final statusCode = response?.statusCode;
  final retryAfter = int.tryParse(response?.headers.value('retry-after') ?? '');
  final requestId = response?.headers.value('x-request-id') ??
      response?.requestOptions.headers['X-Request-ID']?.toString();

  if (response == null) {
    return NetworkException(
      message: error.message ?? 'Erreur reseau',
      requestId: requestId,
    );
  }

  final payload = _errorPayload(response.data, fallback: error.message);
  final message = statusCode == 429 && retryAfter != null
      ? '${payload.message} Reessaye dans ${retryAfter}s.'
      : payload.message;

  final args = _ExceptionArgs(
    message: message,
    code: payload.code,
    statusCode: statusCode,
    field: payload.field,
    requestId: requestId,
    retryAfterSeconds: retryAfter,
  );

  switch (statusCode) {
    case 401:
      return UnauthorizedException(
        message: args.message,
        code: args.code,
        statusCode: args.statusCode,
        field: args.field,
        requestId: args.requestId,
        retryAfterSeconds: args.retryAfterSeconds,
      );
    case 403:
      return ForbiddenException(
        message: args.message,
        code: args.code,
        statusCode: args.statusCode,
        field: args.field,
        requestId: args.requestId,
        retryAfterSeconds: args.retryAfterSeconds,
      );
    case 409:
      return ConflictException(
        message: args.message,
        code: args.code,
        statusCode: args.statusCode,
        field: args.field,
        requestId: args.requestId,
        retryAfterSeconds: args.retryAfterSeconds,
      );
    case 422:
      return ValidationException(
        message: args.message,
        code: args.code,
        statusCode: args.statusCode,
        field: args.field,
        requestId: args.requestId,
        retryAfterSeconds: args.retryAfterSeconds,
      );
    case 429:
      return RateLimitException(
        message: args.message,
        code: args.code,
        statusCode: args.statusCode,
        field: args.field,
        requestId: args.requestId,
        retryAfterSeconds: args.retryAfterSeconds,
      );
    case 503:
      return ServerException(
        message: args.message,
        code: args.code,
        statusCode: args.statusCode,
        field: args.field,
        requestId: args.requestId,
        retryAfterSeconds: args.retryAfterSeconds,
      );
  }
  if (statusCode != null && statusCode >= 500) {
    return ServerException(
      message: args.message,
      code: args.code,
      statusCode: args.statusCode,
      field: args.field,
      requestId: args.requestId,
      retryAfterSeconds: args.retryAfterSeconds,
    );
  }
  return BusinessException(
    message: args.message,
    code: args.code,
    statusCode: args.statusCode,
    field: args.field,
    requestId: args.requestId,
    retryAfterSeconds: args.retryAfterSeconds,
  );
}

class _ErrorPayload {
  const _ErrorPayload({
    required this.message,
    this.code,
    this.field,
  });

  final String message;
  final String? code;
  final String? field;
}

_ErrorPayload _errorPayload(Object? data, {String? fallback}) {
  if (data is Map<String, dynamic>) {
    final detail = data['detail'];
    if (detail is List) {
      return _pydanticValidationPayload(detail, fallback: fallback);
    }
    return _ErrorPayload(
      message:
          (detail ?? data['message'] ?? fallback ?? 'Erreur API').toString(),
      code: data['code']?.toString(),
      field: data['field']?.toString(),
    );
  }
  if (data is Map) {
    return _errorPayload(Map<String, dynamic>.from(data), fallback: fallback);
  }
  return _ErrorPayload(message: fallback ?? 'Erreur API');
}

_ErrorPayload _pydanticValidationPayload(
  List<dynamic> detail, {
  String? fallback,
}) {
  if (detail.isEmpty) {
    return _ErrorPayload(message: fallback ?? 'Validation invalide');
  }
  final first = detail.first;
  if (first is Map) {
    final map = Map<String, dynamic>.from(first);
    final location = map['loc'];
    final field = location is List && location.isNotEmpty
        ? location.last.toString()
        : null;
    return _ErrorPayload(
      message: map['msg']?.toString() ?? fallback ?? 'Validation invalide',
      code: map['type']?.toString() ?? 'VALIDATION_ERROR',
      field: field,
    );
  }
  return _ErrorPayload(message: first.toString());
}

class _ExceptionArgs {
  const _ExceptionArgs({
    required this.message,
    this.code,
    this.statusCode,
    this.field,
    this.requestId,
    this.retryAfterSeconds,
  });

  final String message;
  final String? code;
  final int? statusCode;
  final String? field;
  final String? requestId;
  final int? retryAfterSeconds;
}
