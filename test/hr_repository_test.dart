import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/hr/data/hr_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HR models parse backend responses', () {
    final employee = EmployeeProfile.fromJson({
      'id': 1,
      'user_id': 2,
      'establishment_id': 3,
      'hourly_rate_cents': 1500,
      'weekly_hours_contract': 35,
      'hire_date': '2026-08-01',
      'is_active': true,
      'created_at': '2026-08-10T10:00:00Z',
    });
    final shift = HrShift.fromJson(_shiftJson(id: 10));
    final entry = TimeClockEntry.fromJson(_entryJson(id: 20));
    final alert = HrAlert.fromJson({
      'id': 30,
      'employee_id': 1,
      'establishment_id': 3,
      'type': 'weekly_overtime',
      'severity': 'warning',
      'payload': {'hours_worked': 38},
      'triggered_at': '2026-08-10T10:00:00Z',
      'resolved_at': null,
    });

    expect(employee.hourlyRateCents, 1500);
    expect(shift.status, 'scheduled');
    expect(entry.isOpen, isTrue);
    expect(alert.payload['hours_worked'], 38);
  });

  test('shift validation requires end after start and non-negative break', () {
    final startsAt = DateTime(2026, 8, 10, 10);
    final invalidEnd = ShiftDraft(
      employeeId: 1,
      establishmentId: 1,
      startsAt: startsAt,
      endsAt: startsAt,
      breakMinutes: 0,
    );
    final invalidBreak = ShiftDraft(
      employeeId: 1,
      establishmentId: 1,
      startsAt: startsAt,
      endsAt: startsAt.add(const Duration(hours: 4)),
      breakMinutes: -1,
    );

    expect(invalidEnd.validate(), contains('fin'));
    expect(invalidBreak.validate(), contains('pause'));
  });

  test('list, create, update and cancel shifts use actual HR routes', () async {
    final seenPaths = <String>[];
    final repository = _repository((options) {
      seenPaths.add('${options.method} ${options.path}');
      if (options.method == 'GET') {
        return _jsonResponse([_shiftJson(id: 1)]);
      }
      if (options.path == ApiEndpoints.hrShift(1)) {
        return _jsonResponse(
          _shiftJson(
            id: 1,
            status: options.data.toString().contains('cancelled')
                ? 'cancelled'
                : 'scheduled',
          ),
        );
      }
      return _jsonResponse(_shiftJson(id: 2), statusCode: 201);
    });

    final query = HrShiftQuery(
      dateFrom: DateTime(2026, 8, 10),
      dateTo: DateTime(2026, 8, 17),
    );
    await repository.listShifts(query);
    await repository.createShift(_validShiftDraft());
    await repository.updateShift(1, _validShiftDraft());
    final cancelled = await repository.cancelShift(1);

    expect(seenPaths, contains('GET ${ApiEndpoints.hrShifts}'));
    expect(seenPaths, contains('POST ${ApiEndpoints.hrShifts}'));
    expect(seenPaths, contains('PATCH ${ApiEndpoints.hrShift(1)}'));
    expect(cancelled.status, 'cancelled');
  });

  test('timeclock clock-in, clock-out and correction use backend contract',
      () async {
    final seenPaths = <String>[];
    final repository = _repository((options) {
      seenPaths.add('${options.method} ${options.path}');
      return _jsonResponse(_entryJson(id: 5, status: 'closed'));
    });

    await repository.clockIn(
      const ClockInDraft(method: 'web', establishmentId: 1, shiftId: 2),
    );
    await repository.clockOut();
    await repository.correctTimeClockEntry(
      5,
      TimeClockCorrectionDraft(
        newClockInAt: DateTime(2026, 8, 10, 9),
        newClockOutAt: DateTime(2026, 8, 10, 13),
        reason: 'Correction admin',
      ),
    );

    expect(seenPaths, contains('POST ${ApiEndpoints.hrClockIn}'));
    expect(seenPaths, contains('POST ${ApiEndpoints.hrClockOut}'));
    expect(seenPaths, contains('PATCH ${ApiEndpoints.hrTimeClockEntry(5)}'));
  });

  test('alerts list and resolve use backend contract', () async {
    final seenPaths = <String>[];
    final repository = _repository((options) {
      seenPaths.add('${options.method} ${options.path}');
      if (options.method == 'GET') {
        return _jsonResponse([
          {
            'id': 9,
            'employee_id': 1,
            'establishment_id': 1,
            'type': 'late',
            'severity': 'warning',
            'payload': {'minutes_late': 12},
            'triggered_at': '2026-08-10T10:00:00Z',
            'resolved_at': null,
          },
        ]);
      }
      return _jsonResponse({
        'id': 9,
        'employee_id': 1,
        'establishment_id': 1,
        'type': 'late',
        'severity': 'warning',
        'payload': {'minutes_late': 12},
        'triggered_at': '2026-08-10T10:00:00Z',
        'resolved_at': '2026-08-10T11:00:00Z',
      });
    });

    final alerts =
        await repository.listAlerts(const HrAlertsQuery(resolved: false));
    final resolved = await repository.resolveAlert(9);

    expect(alerts.single.type, 'late');
    expect(resolved.isResolved, isTrue);
    expect(seenPaths, contains('GET ${ApiEndpoints.hrAlerts}'));
    expect(seenPaths, contains('PATCH ${ApiEndpoints.hrAlertResolve(9)}'));
  });
}

HrRepository _repository(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = _FakeAdapter(handler);
  return HrRepository(ApiClient(dio, _MemoryTokenStore()));
}

ShiftDraft _validShiftDraft() {
  return ShiftDraft(
    employeeId: 1,
    establishmentId: 1,
    startsAt: DateTime(2026, 8, 10, 9),
    endsAt: DateTime(2026, 8, 10, 13),
    breakMinutes: 15,
  );
}

Map<String, dynamic> _shiftJson({
  required int id,
  String status = 'scheduled',
}) {
  return {
    'id': id,
    'employee_id': 1,
    'establishment_id': 1,
    'starts_at': '2026-08-10T09:00:00Z',
    'ends_at': '2026-08-10T13:00:00Z',
    'break_minutes': 15,
    'status': status,
  };
}

Map<String, dynamic> _entryJson({
  required int id,
  String status = 'open',
}) {
  return {
    'id': id,
    'employee_id': 1,
    'shift_id': 2,
    'establishment_id': 1,
    'clock_in_at': '2026-08-10T09:00:00Z',
    'clock_out_at': status == 'open' ? null : '2026-08-10T13:00:00Z',
    'method': 'web',
    'status': status,
  };
}

ResponseBody _jsonResponse(
  Object body, {
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
