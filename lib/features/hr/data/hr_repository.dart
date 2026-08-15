import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final hrRepositoryProvider = Provider<HrRepository>((ref) {
  return HrRepository(ref.watch(apiClientProvider));
});

final employeesProvider = FutureProvider.autoDispose<List<EmployeeProfile>>((
  ref,
) {
  return ref.watch(hrRepositoryProvider).listEmployees();
});

final myEmployeeProfileProvider =
    FutureProvider.autoDispose<EmployeeProfileSelf>((ref) {
  return ref.watch(hrRepositoryProvider).myEmployeeProfile();
});

final shiftsProvider = FutureProvider.autoDispose
    .family<List<HrShift>, HrShiftQuery>((ref, query) {
  return ref.watch(hrRepositoryProvider).listShifts(query);
});

final myShiftsProvider = FutureProvider.autoDispose
    .family<List<HrShift>, HrShiftQuery>((ref, query) {
  return ref.watch(hrRepositoryProvider).listMyShifts(query);
});

final timeClockEntriesProvider = FutureProvider.autoDispose
    .family<List<TimeClockEntry>, TimeClockEntryQuery>((ref, query) {
  return ref.watch(hrRepositoryProvider).listTimeClockEntries(query);
});

final myTimeClockEntriesProvider = FutureProvider.autoDispose
    .family<List<TimeClockEntry>, TimeClockEntryQuery>((ref, query) {
  return ref.watch(hrRepositoryProvider).listMyTimeClockEntries(query);
});

final hrAlertsProvider = FutureProvider.autoDispose
    .family<List<HrAlert>, HrAlertsQuery>((ref, query) {
  return ref.watch(hrRepositoryProvider).listAlerts(query);
});

class HrRepository {
  const HrRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<EmployeeProfile>> listEmployees() async {
    final response = await _apiClient.get(ApiEndpoints.hrEmployees);
    return _listFromResponse(response.data, EmployeeProfile.fromJson);
  }

  Future<EmployeeProfileSelf> myEmployeeProfile() async {
    final response = await _apiClient.get(ApiEndpoints.hrEmployeeMe);
    return EmployeeProfileSelf.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<EmployeeProfile> createEmployee(
    EmployeeProfileCreateDraft draft,
  ) async {
    final response = await _apiClient.post(
      ApiEndpoints.hrEmployees,
      data: draft.toJson(),
    );
    return EmployeeProfile.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<EmployeeProfile> updateEmployee(
    int employeeId,
    EmployeeProfileUpdateDraft draft,
  ) async {
    final response = await _apiClient.patch(
      ApiEndpoints.hrEmployee(employeeId),
      data: draft.toJson(),
    );
    return EmployeeProfile.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<List<HrShift>> listShifts(HrShiftQuery query) async {
    final response = await _apiClient.get(
      ApiEndpoints.hrShifts,
      queryParameters: query.toQueryParameters(includeEmployee: true),
    );
    return _listFromResponse(response.data, HrShift.fromJson);
  }

  Future<List<HrShift>> listMyShifts(HrShiftQuery query) async {
    final response = await _apiClient.get(
      ApiEndpoints.hrShiftsMe,
      queryParameters: query.toQueryParameters(includeEmployee: false),
    );
    return _listFromResponse(response.data, HrShift.fromJson);
  }

  Future<HrShift> createShift(ShiftDraft draft) async {
    final error = draft.validate();
    if (error != null) {
      throw HrValidationException(error);
    }
    final response = await _apiClient.post(
      ApiEndpoints.hrShifts,
      data: draft.toCreateJson(),
    );
    return HrShift.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<HrShift> updateShift(int shiftId, ShiftDraft draft) async {
    final error = draft.validate();
    if (error != null) {
      throw HrValidationException(error);
    }
    final response = await _apiClient.patch(
      ApiEndpoints.hrShift(shiftId),
      data: draft.toUpdateJson(),
    );
    return HrShift.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<HrShift> cancelShift(int shiftId) async {
    final response = await _apiClient.patch(
      ApiEndpoints.hrShift(shiftId),
      data: {'status': 'cancelled'},
    );
    return HrShift.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<TimeClockEntry> clockIn(ClockInDraft draft) async {
    final response = await _apiClient.post(
      ApiEndpoints.hrClockIn,
      data: draft.toJson(),
    );
    return TimeClockEntry.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<TimeClockEntry> clockOut() async {
    final response = await _apiClient.post(ApiEndpoints.hrClockOut);
    return TimeClockEntry.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<List<TimeClockEntry>> listTimeClockEntries(
    TimeClockEntryQuery query,
  ) async {
    final response = await _apiClient.get(
      ApiEndpoints.hrTimeClockEntries,
      queryParameters: query.toQueryParameters(includeEmployee: true),
    );
    return _listFromResponse(response.data, TimeClockEntry.fromJson);
  }

  Future<List<TimeClockEntry>> listMyTimeClockEntries(
    TimeClockEntryQuery query,
  ) async {
    final response = await _apiClient.get(
      ApiEndpoints.hrTimeClockEntriesMe,
      queryParameters: query.toQueryParameters(includeEmployee: false),
    );
    return _listFromResponse(response.data, TimeClockEntry.fromJson);
  }

  Future<TimeClockEntry> correctTimeClockEntry(
    int entryId,
    TimeClockCorrectionDraft draft,
  ) async {
    final response = await _apiClient.patch(
      ApiEndpoints.hrTimeClockEntry(entryId),
      data: draft.toJson(),
    );
    return TimeClockEntry.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<List<HrAlert>> listAlerts(HrAlertsQuery query) async {
    final response = await _apiClient.get(
      ApiEndpoints.hrAlerts,
      queryParameters: query.toQueryParameters(),
    );
    return _listFromResponse(response.data, HrAlert.fromJson);
  }

  Future<HrAlert> resolveAlert(int alertId) async {
    final response =
        await _apiClient.patch(ApiEndpoints.hrAlertResolve(alertId));
    return HrAlert.fromJson(Map<String, dynamic>.from(response.data as Map));
  }
}

class EmployeeProfile {
  const EmployeeProfile({
    required this.id,
    required this.userId,
    required this.establishmentId,
    required this.weeklyHoursContract,
    required this.isActive,
    required this.createdAt,
    this.hourlyRateCents,
    this.hireDate,
  });

  final int id;
  final int userId;
  final int establishmentId;
  final int? hourlyRateCents;
  final int weeklyHoursContract;
  final DateTime? hireDate;
  final bool isActive;
  final DateTime createdAt;

  factory EmployeeProfile.fromJson(Map<String, dynamic> json) {
    return EmployeeProfile(
      id: _intValue(json['id']),
      userId: _intValue(json['user_id']),
      establishmentId: _intValue(json['establishment_id']),
      hourlyRateCents: _nullableInt(json['hourly_rate_cents']),
      weeklyHoursContract: _intValue(json['weekly_hours_contract']),
      hireDate: _nullableDate(json['hire_date']),
      isActive: json['is_active'] == true,
      createdAt: _dateTime(json['created_at']),
    );
  }
}

class EmployeeProfileSelf {
  const EmployeeProfileSelf({
    required this.id,
    required this.userId,
    required this.establishmentId,
    required this.weeklyHoursContract,
    required this.isActive,
    this.hireDate,
  });

  final int id;
  final int userId;
  final int establishmentId;
  final int weeklyHoursContract;
  final DateTime? hireDate;
  final bool isActive;

  factory EmployeeProfileSelf.fromJson(Map<String, dynamic> json) {
    return EmployeeProfileSelf(
      id: _intValue(json['id']),
      userId: _intValue(json['user_id']),
      establishmentId: _intValue(json['establishment_id']),
      weeklyHoursContract: _intValue(json['weekly_hours_contract']),
      hireDate: _nullableDate(json['hire_date']),
      isActive: json['is_active'] == true,
    );
  }
}

class EmployeeProfileCreateDraft {
  const EmployeeProfileCreateDraft({
    required this.userId,
    required this.establishmentId,
    this.hourlyRateCents,
    this.weeklyHoursContract = 35,
    this.hireDate,
  });

  final int userId;
  final int establishmentId;
  final int? hourlyRateCents;
  final int weeklyHoursContract;
  final DateTime? hireDate;

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'establishment_id': establishmentId,
      'hourly_rate_cents': hourlyRateCents,
      'weekly_hours_contract': weeklyHoursContract,
      'hire_date': hireDate?.toIso8601String().split('T').first,
    };
  }
}

class EmployeeProfileUpdateDraft {
  const EmployeeProfileUpdateDraft({
    this.establishmentId,
    this.hourlyRateCents,
    this.weeklyHoursContract,
    this.isActive,
  });

  final int? establishmentId;
  final int? hourlyRateCents;
  final int? weeklyHoursContract;
  final bool? isActive;

  Map<String, dynamic> toJson() {
    return {
      if (establishmentId != null) 'establishment_id': establishmentId,
      if (hourlyRateCents != null) 'hourly_rate_cents': hourlyRateCents,
      if (weeklyHoursContract != null)
        'weekly_hours_contract': weeklyHoursContract,
      if (isActive != null) 'is_active': isActive,
    };
  }
}

class HrShift {
  const HrShift({
    required this.id,
    required this.employeeId,
    required this.establishmentId,
    required this.startsAt,
    required this.endsAt,
    required this.breakMinutes,
    required this.status,
  });

  final int id;
  final int employeeId;
  final int establishmentId;
  final DateTime startsAt;
  final DateTime endsAt;
  final int breakMinutes;
  final String status;

  bool get isCancelled => status == 'cancelled';

  factory HrShift.fromJson(Map<String, dynamic> json) {
    return HrShift(
      id: _intValue(json['id']),
      employeeId: _intValue(json['employee_id']),
      establishmentId: _intValue(json['establishment_id']),
      startsAt: _dateTime(json['starts_at']),
      endsAt: _dateTime(json['ends_at']),
      breakMinutes: _intValue(json['break_minutes']),
      status: json['status']?.toString() ?? 'scheduled',
    );
  }
}

class ShiftDraft {
  const ShiftDraft({
    required this.employeeId,
    required this.establishmentId,
    required this.startsAt,
    required this.endsAt,
    required this.breakMinutes,
    this.status,
  });

  final int employeeId;
  final int establishmentId;
  final DateTime startsAt;
  final DateTime endsAt;
  final int breakMinutes;
  final String? status;

  String? validate() {
    if (employeeId <= 0) {
      return 'Employe requis';
    }
    if (establishmentId <= 0) {
      return 'Etablissement requis';
    }
    if (!endsAt.isAfter(startsAt)) {
      return 'La fin doit etre apres le debut';
    }
    if (breakMinutes < 0) {
      return 'La pause doit etre positive';
    }
    return null;
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'employee_id': employeeId,
      'establishment_id': establishmentId,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'break_minutes': breakMinutes,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'break_minutes': breakMinutes,
      if (status != null) 'status': status,
    };
  }
}

class HrShiftQuery {
  const HrShiftQuery({
    this.employeeId,
    this.dateFrom,
    this.dateTo,
  });

  final int? employeeId;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  Map<String, dynamic> toQueryParameters({required bool includeEmployee}) {
    return {
      if (includeEmployee && employeeId != null) 'employee_id': employeeId,
      if (dateFrom != null) 'date_from': dateFrom!.toUtc().toIso8601String(),
      if (dateTo != null) 'date_to': dateTo!.toUtc().toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is HrShiftQuery &&
        other.employeeId == employeeId &&
        other.dateFrom == dateFrom &&
        other.dateTo == dateTo;
  }

  @override
  int get hashCode => Object.hash(employeeId, dateFrom, dateTo);
}

class ClockInDraft {
  const ClockInDraft({
    required this.method,
    required this.establishmentId,
    this.shiftId,
  });

  final String method;
  final int establishmentId;
  final int? shiftId;

  Map<String, dynamic> toJson() {
    return {
      'method': method,
      'establishment_id': establishmentId,
      'shift_id': shiftId,
    };
  }
}

class TimeClockEntry {
  const TimeClockEntry({
    required this.id,
    required this.employeeId,
    required this.establishmentId,
    required this.clockInAt,
    required this.method,
    required this.status,
    this.shiftId,
    this.clockOutAt,
  });

  final int id;
  final int employeeId;
  final int? shiftId;
  final int establishmentId;
  final DateTime clockInAt;
  final DateTime? clockOutAt;
  final String method;
  final String status;

  bool get isOpen => status == 'open' && clockOutAt == null;

  factory TimeClockEntry.fromJson(Map<String, dynamic> json) {
    return TimeClockEntry(
      id: _intValue(json['id']),
      employeeId: _intValue(json['employee_id']),
      shiftId: _nullableInt(json['shift_id']),
      establishmentId: _intValue(json['establishment_id']),
      clockInAt: _dateTime(json['clock_in_at']),
      clockOutAt: _nullableDateTime(json['clock_out_at']),
      method: json['method']?.toString() ?? 'web',
      status: json['status']?.toString() ?? 'open',
    );
  }
}

class TimeClockEntryQuery {
  const TimeClockEntryQuery({
    this.employeeId,
    this.status,
    this.dateFrom,
    this.dateTo,
  });

  final int? employeeId;
  final String? status;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  Map<String, dynamic> toQueryParameters({required bool includeEmployee}) {
    return {
      if (includeEmployee && employeeId != null) 'employee_id': employeeId,
      if (includeEmployee && status != null && status!.isNotEmpty)
        'status': status,
      if (dateFrom != null) 'date_from': dateFrom!.toUtc().toIso8601String(),
      if (dateTo != null) 'date_to': dateTo!.toUtc().toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TimeClockEntryQuery &&
        other.employeeId == employeeId &&
        other.status == status &&
        other.dateFrom == dateFrom &&
        other.dateTo == dateTo;
  }

  @override
  int get hashCode => Object.hash(employeeId, status, dateFrom, dateTo);
}

class TimeClockCorrectionDraft {
  const TimeClockCorrectionDraft({
    required this.reason,
    this.newClockInAt,
    this.newClockOutAt,
  });

  final DateTime? newClockInAt;
  final DateTime? newClockOutAt;
  final String reason;

  Map<String, dynamic> toJson() {
    return {
      'new_clock_in_at': newClockInAt?.toUtc().toIso8601String(),
      'new_clock_out_at': newClockOutAt?.toUtc().toIso8601String(),
      'reason': reason.trim(),
    };
  }
}

class HrAlert {
  const HrAlert({
    required this.id,
    required this.type,
    required this.severity,
    required this.payload,
    required this.triggeredAt,
    this.employeeId,
    this.establishmentId,
    this.resolvedAt,
  });

  final int id;
  final int? employeeId;
  final int? establishmentId;
  final String type;
  final String severity;
  final Map<String, dynamic> payload;
  final DateTime triggeredAt;
  final DateTime? resolvedAt;

  bool get isResolved => resolvedAt != null;

  factory HrAlert.fromJson(Map<String, dynamic> json) {
    return HrAlert(
      id: _intValue(json['id']),
      employeeId: _nullableInt(json['employee_id']),
      establishmentId: _nullableInt(json['establishment_id']),
      type: json['type']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'warning',
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
      triggeredAt: _dateTime(json['triggered_at']),
      resolvedAt: _nullableDateTime(json['resolved_at']),
    );
  }
}

class HrAlertsQuery {
  const HrAlertsQuery({this.resolved});

  final bool? resolved;

  Map<String, dynamic> toQueryParameters() {
    return {
      if (resolved != null) 'resolved': resolved,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is HrAlertsQuery && other.resolved == resolved;
  }

  @override
  int get hashCode => resolved.hashCode;
}

class HrValidationException implements Exception {
  const HrValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

List<T> _listFromResponse<T>(
  Object? data,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (data is List) {
    return data
        .whereType<Map>()
        .map((value) => fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }
  return const [];
}

DateTime _dateTime(Object? value) {
  return DateTime.parse(value.toString()).toLocal();
}

DateTime? _nullableDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  final raw = value.toString();
  if (raw.isEmpty) {
    return null;
  }
  return DateTime.parse(raw).toLocal();
}

DateTime? _nullableDate(Object? value) {
  if (value == null) {
    return null;
  }
  final raw = value.toString();
  if (raw.isEmpty) {
    return null;
  }
  return DateTime.parse(raw);
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _nullableInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString());
}
