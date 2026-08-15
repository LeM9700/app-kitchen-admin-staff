import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/api/paginated.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/core/config/env.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tenantRepositoryProvider = Provider<TenantRepository>((ref) {
  return TenantRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStoreProvider),
  );
});

final tenantStatusProvider = FutureProvider.autoDispose<TenantStatus>((ref) {
  return ref.watch(tenantRepositoryProvider).status();
});

final tenantConfigProvider = FutureProvider.autoDispose<TenantConfig>((ref) {
  return ref.watch(tenantRepositoryProvider).config();
});

final tenantPrintConfigProvider =
    FutureProvider.autoDispose<TenantPrintConfig>((ref) {
  return ref.watch(tenantRepositoryProvider).printConfig();
});

final tenantBusinessHoursProvider =
    FutureProvider.autoDispose<List<BusinessHour>>((ref) {
  return ref.watch(tenantRepositoryProvider).businessHours();
});

final tenantClosuresProvider =
    FutureProvider.autoDispose<List<ExceptionalClosure>>((ref) {
  return ref.watch(tenantRepositoryProvider).closures();
});

final tenantAuditProvider =
    FutureProvider.autoDispose<List<TenantAuditEntry>>((ref) {
  return ref.watch(tenantRepositoryProvider).audit();
});

class TenantRepository {
  const TenantRepository(this._apiClient, this._tokenStore);

  final ApiClient _apiClient;
  final TokenStore _tokenStore;

  Future<TenantStatus> status() async {
    final tenantSlug =
        await _tokenStore.readTenantSlug() ?? Env.defaultTenantSlug;
    final response = await _apiClient.get(
      ApiEndpoints.tenantStatus,
      queryParameters: {'tenant_slug': tenantSlug},
      authenticated: false,
    );
    return TenantStatus.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TenantPrintConfig> printConfig() async {
    final response = await _apiClient.get(ApiEndpoints.tenantPrintConfig);
    return TenantPrintConfig.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TenantConfig> config() async {
    final response = await _apiClient.get(ApiEndpoints.tenantConfig);
    return TenantConfig.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<BusinessHour>> businessHours() async {
    final tenantSlug =
        await _tokenStore.readTenantSlug() ?? Env.defaultTenantSlug;
    final response = await _apiClient.get(
      ApiEndpoints.tenantHours,
      queryParameters: {'tenant_slug': tenantSlug},
      authenticated: false,
    );
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map((value) => BusinessHour.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  Future<List<BusinessHour>> replaceBusinessHours({
    required int dayOfWeek,
    required String opensAt,
    required String closesAt,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.tenantHoursDay(dayOfWeek),
      data: [
        {
          'slot_index': 0,
          'opens_at': opensAt,
          'closes_at': closesAt,
        },
      ],
    );
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map((value) => BusinessHour.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  Future<void> deleteBusinessHours(int dayOfWeek) async {
    await _apiClient.delete(ApiEndpoints.tenantHoursDay(dayOfWeek));
  }

  Future<List<ExceptionalClosure>> closures() async {
    final response = await _apiClient.get(ApiEndpoints.tenantClosures);
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => ExceptionalClosure.fromJson(
            Map<String, dynamic>.from(value),
          ),
        )
        .toList();
  }

  Future<ExceptionalClosure> createClosure({
    required String closureDate,
    String? message,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.tenantClosures,
      data: {
        'closure_date': closureDate,
        if (message != null && message.trim().isNotEmpty)
          'custom_message': message.trim(),
        'use_default_message': message == null || message.trim().isEmpty,
      },
    );
    return ExceptionalClosure.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteClosure(int closureId) async {
    await _apiClient.delete(ApiEndpoints.tenantClosure(closureId));
  }

  Future<List<TenantAuditEntry>> audit() async {
    final response = await _apiClient.get(
      ApiEndpoints.tenantAudit,
      queryParameters: {'limit': 30, 'offset': 0},
    );
    final result = PaginatedResult.fromJson(
      response.data as Map<String, dynamic>,
      TenantAuditEntry.fromJson,
    );
    return result.items;
  }

  Future<TenantPrintConfig> updatePrintConfig({
    required bool enabled,
    required Map<String, dynamic> config,
  }) async {
    final response = await _apiClient.patch(
      ApiEndpoints.tenantPrintConfig,
      data: {
        'print_enabled': enabled,
        'print_config': config,
      },
    );
    return TenantPrintConfig.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> toggleClosure({
    required bool closed,
    String? message,
  }) async {
    await _apiClient.patch(
      ApiEndpoints.tenantToggleClosure,
      data: {
        'is_temporarily_closed': closed,
        if (message != null && message.trim().isNotEmpty)
          'temporary_closure_message': message.trim(),
      },
    );
  }

  Future<void> updateLargeStockAdjustmentThreshold(double threshold) async {
    await _apiClient.patch(
      ApiEndpoints.tenantConfig,
      data: {'large_stock_adjustment_threshold': threshold},
    );
  }

  Future<TenantConfig> updatePreparationSettings({
    required int normalMinutes,
    required int peakMinutes,
    required int peakOrdersThreshold,
    required int overheadPerOrderMinutes,
    required bool autoCalcPrepTime,
  }) async {
    final response = await _apiClient.patch(
      ApiEndpoints.tenantConfig,
      data: {
        'prep_time_normal_minutes': normalMinutes,
        'prep_time_peak_minutes': peakMinutes,
        'peak_orders_threshold': peakOrdersThreshold,
        'overhead_per_order_minutes': overheadPerOrderMinutes,
        'auto_calc_prep_time': autoCalcPrepTime,
      },
    );
    return TenantConfig.fromJson(response.data as Map<String, dynamic>);
  }
}

class TenantStatus {
  const TenantStatus({
    required this.isOpen,
    required this.estimatedPrepTimeMinutes,
    required this.activeOrdersCount,
    this.message,
    this.nextOpening,
  });

  final bool isOpen;
  final int estimatedPrepTimeMinutes;
  final int activeOrdersCount;
  final String? message;
  final String? nextOpening;

  factory TenantStatus.fromJson(Map<String, dynamic> json) {
    return TenantStatus(
      isOpen: readBool(json['is_open']),
      estimatedPrepTimeMinutes: readInt(json['estimated_prep_time_minutes']),
      activeOrdersCount: readInt(json['active_orders_count']),
      message: json['message']?.toString(),
      nextOpening: json['next_opening']?.toString(),
    );
  }
}

class TenantPrintConfig {
  const TenantPrintConfig({
    required this.enabled,
    required this.config,
  });

  final bool enabled;
  final Map<String, dynamic> config;

  factory TenantPrintConfig.fromJson(Map<String, dynamic> json) {
    return TenantPrintConfig(
      enabled: readBool(json['print_enabled']),
      config: readMap(json['print_config']),
    );
  }
}

class TenantConfig {
  const TenantConfig({
    required this.id,
    required this.isTemporarilyClosed,
    required this.defaultClosureMessage,
    required this.prepTimeNormalMinutes,
    required this.prepTimePeakMinutes,
    required this.peakOrdersThreshold,
    required this.autoCalcPrepTime,
    required this.overheadPerOrderMinutes,
    required this.timezone,
    required this.largeStockAdjustmentThreshold,
    required this.printEnabled,
    required this.printConfig,
    this.temporaryClosureMessage,
    this.updatedAt,
    this.scheduledCloseAt,
  });

  final int id;
  final bool isTemporarilyClosed;
  final String? temporaryClosureMessage;
  final String defaultClosureMessage;
  final int prepTimeNormalMinutes;
  final int prepTimePeakMinutes;
  final int peakOrdersThreshold;
  final bool autoCalcPrepTime;
  final int overheadPerOrderMinutes;
  final String timezone;
  final double largeStockAdjustmentThreshold;
  final bool printEnabled;
  final Map<String, dynamic> printConfig;
  final DateTime? updatedAt;
  final DateTime? scheduledCloseAt;

  factory TenantConfig.fromJson(Map<String, dynamic> json) {
    return TenantConfig(
      id: readInt(json['id']),
      isTemporarilyClosed: readBool(json['is_temporarily_closed']),
      temporaryClosureMessage: json['temporary_closure_message']?.toString(),
      defaultClosureMessage: json['default_closure_message']?.toString() ?? '',
      prepTimeNormalMinutes: readInt(json['prep_time_normal_minutes']),
      prepTimePeakMinutes: readInt(json['prep_time_peak_minutes']),
      peakOrdersThreshold: readInt(json['peak_orders_threshold']),
      autoCalcPrepTime: readBool(json['auto_calc_prep_time']),
      overheadPerOrderMinutes: readInt(json['overhead_per_order_minutes']),
      timezone: json['timezone']?.toString() ?? 'Europe/Paris',
      largeStockAdjustmentThreshold:
          readDouble(json['large_stock_adjustment_threshold']),
      printEnabled: readBool(json['print_enabled']),
      printConfig: readMap(json['print_config']),
      updatedAt: readDateTime(json['updated_at']),
      scheduledCloseAt: readDateTime(json['scheduled_close_at']),
    );
  }
}

class BusinessHour {
  const BusinessHour({
    required this.id,
    required this.dayOfWeek,
    required this.slotIndex,
    required this.opensAt,
    required this.closesAt,
    required this.isActive,
  });

  final int id;
  final int dayOfWeek;
  final int slotIndex;
  final String opensAt;
  final String closesAt;
  final bool isActive;

  factory BusinessHour.fromJson(Map<String, dynamic> json) {
    return BusinessHour(
      id: readInt(json['id']),
      dayOfWeek: readInt(json['day_of_week']),
      slotIndex: readInt(json['slot_index']),
      opensAt: json['opens_at']?.toString() ?? '',
      closesAt: json['closes_at']?.toString() ?? '',
      isActive: readBool(json['is_active'], fallback: true),
    );
  }
}

class ExceptionalClosure {
  const ExceptionalClosure({
    required this.id,
    required this.closureDate,
    required this.useDefaultMessage,
    this.customMessage,
    this.createdAt,
  });

  final int id;
  final String closureDate;
  final String? customMessage;
  final bool useDefaultMessage;
  final DateTime? createdAt;

  factory ExceptionalClosure.fromJson(Map<String, dynamic> json) {
    return ExceptionalClosure(
      id: readInt(json['id']),
      closureDate: json['closure_date']?.toString() ?? '',
      customMessage: json['custom_message']?.toString(),
      useDefaultMessage: readBool(json['use_default_message']),
      createdAt: readDateTime(json['created_at']),
    );
  }
}

class TenantAuditEntry {
  const TenantAuditEntry({
    required this.id,
    required this.changedByUserId,
    required this.fieldName,
    this.userEmail,
    this.oldValue,
    this.newValue,
    this.ipAddress,
    this.changedAt,
  });

  final int id;
  final int changedByUserId;
  final String? userEmail;
  final DateTime? changedAt;
  final String fieldName;
  final String? oldValue;
  final String? newValue;
  final String? ipAddress;

  factory TenantAuditEntry.fromJson(Map<String, dynamic> json) {
    return TenantAuditEntry(
      id: readInt(json['id']),
      changedByUserId: readInt(json['changed_by_user_id']),
      userEmail: json['user_email']?.toString(),
      changedAt: readDateTime(json['changed_at']),
      fieldName: json['field_name']?.toString() ?? '',
      oldValue: json['old_value']?.toString(),
      newValue: json['new_value']?.toString(),
      ipAddress: json['ip_address']?.toString(),
    );
  }
}
