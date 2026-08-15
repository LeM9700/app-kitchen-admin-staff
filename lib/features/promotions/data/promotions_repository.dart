import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/api/paginated.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final promotionsRepositoryProvider = Provider<PromotionsRepository>((ref) {
  return PromotionsRepository(ref.watch(apiClientProvider));
});

enum PromotionStatusFilter { all, active, inactive, scheduled, expired }

final promotionSearchProvider = StateProvider<String>((ref) => '');
final promotionStatusFilterProvider = StateProvider<PromotionStatusFilter>(
  (ref) => PromotionStatusFilter.all,
);

final promotionsProvider =
    FutureProvider.autoDispose<List<PromotionAdminItem>>((ref) {
  final search = ref.watch(promotionSearchProvider).trim();
  final status = ref.watch(promotionStatusFilterProvider);
  final isActive = switch (status) {
    PromotionStatusFilter.active => true,
    PromotionStatusFilter.inactive => false,
    _ => null,
  };
  return ref.watch(promotionsRepositoryProvider).listAdmin(
        pageSize: 100,
        code: search.length >= 2 ? search : null,
        isActive: isActive,
      );
});

class PromotionsRepository {
  const PromotionsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<PromotionAdminItem>> listAdmin({
    int page = 1,
    int pageSize = 50,
    String? code,
    bool? isActive,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.promotionsAdmin,
      queryParameters: {
        'page': page,
        'page_size': pageSize,
        if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
        if (isActive != null) 'is_active': isActive,
      },
    );
    final result = PaginatedResult.fromJson(
      response.data as Map<String, dynamic>,
      PromotionAdminItem.fromJson,
    );
    return result.items;
  }

  Future<PromotionAdminItem> create({
    required String code,
    required String discountType,
    required double discountValue,
    String? description,
    double minOrderAmount = 0,
    bool isPublic = true,
    bool isStackable = false,
    bool firstOrderOnly = false,
    bool emailVerifiedRequired = false,
    int? maxUses,
    int? maxUsesPerUser,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.promotions,
      data: {
        'code': code,
        'discount_type': discountType,
        'discount_value': discountValue,
        'min_order_amount': minOrderAmount,
        'is_public': isPublic,
        'is_stackable': isStackable,
        'first_order_only': firstOrderOnly,
        'email_verified_required': emailVerifiedRequired,
        if (maxUses != null) 'max_uses': maxUses,
        if (maxUsesPerUser != null) 'max_uses_per_user': maxUsesPerUser,
        if (startsAt != null) 'starts_at': startsAt.toUtc().toIso8601String(),
        if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
      },
    );
    return PromotionAdminItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PromotionAdminItem> update({
    required int promoId,
    String? code,
    String? discountType,
    double? discountValue,
    String? description,
    double? minOrderAmount,
    bool? isActive,
    bool? isPublic,
    bool? isStackable,
    bool? firstOrderOnly,
    bool? emailVerifiedRequired,
    int? maxUses,
    int? maxUsesPerUser,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final response = await _apiClient.patch(
      ApiEndpoints.promotion(promoId),
      data: {
        if (code != null) 'code': code,
        if (discountType != null) 'discount_type': discountType,
        if (discountValue != null) 'discount_value': discountValue,
        if (description != null) 'description': description,
        if (minOrderAmount != null) 'min_order_amount': minOrderAmount,
        if (isActive != null) 'is_active': isActive,
        if (isPublic != null) 'is_public': isPublic,
        if (isStackable != null) 'is_stackable': isStackable,
        if (firstOrderOnly != null) 'first_order_only': firstOrderOnly,
        if (emailVerifiedRequired != null)
          'email_verified_required': emailVerifiedRequired,
        if (maxUses != null) 'max_uses': maxUses,
        if (maxUsesPerUser != null) 'max_uses_per_user': maxUsesPerUser,
        if (startsAt != null) 'starts_at': startsAt.toUtc().toIso8601String(),
        if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
      },
    );
    return PromotionAdminItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PromotionAdminItem> toggle(int promoId, bool active) async {
    final response = await _apiClient.post(
      ApiEndpoints.promotionToggle(promoId),
      data: {'is_active': active},
    );
    return PromotionAdminItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int promoId) async {
    await _apiClient.delete(ApiEndpoints.promotion(promoId));
  }

  Future<PromotionCampaign> bulkGenerate({
    required String name,
    required String prefix,
    required int count,
    required String discountType,
    required double discountValue,
    String? description,
    double minOrderAmount = 0,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.promotionsBulkGenerate,
      data: {
        'name': name,
        'prefix': prefix,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        'count': count,
        'promotion': {
          'code': '${prefix}_TEMPLATE',
          'description': description,
          'discount_type': discountType,
          'discount_value': discountValue,
          'min_order_amount': minOrderAmount,
          'is_public': false,
        },
      },
    );
    return PromotionCampaign.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<PromotionUsage>> usages(int promoId) async {
    final response = await _apiClient.get(
      ApiEndpoints.promotionUsages(promoId),
      queryParameters: {'page': 1, 'page_size': 30},
    );
    final result = PaginatedResult.fromJson(
      response.data as Map<String, dynamic>,
      PromotionUsage.fromJson,
    );
    return result.items;
  }
}

class PromotionAdminItem {
  const PromotionAdminItem({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
    required this.isActive,
    required this.isPublic,
    required this.isStackable,
    required this.firstOrderOnly,
    required this.emailVerifiedRequired,
    required this.usageCount,
    required this.uniqueUsers,
    required this.currentUses,
    required this.revenueGross,
    required this.revenueNet,
    required this.discountTotal,
    required this.targetCategoryIds,
    required this.targetProductIds,
    this.description,
    this.remainingUses,
    this.maxUses,
    this.maxUsesPerUser,
    this.startsAt,
    this.endsAt,
    this.campaignId,
    this.userId,
  });

  final int id;
  final String code;
  final String? description;
  final String discountType;
  final double discountValue;
  final double minOrderAmount;
  final bool isActive;
  final bool isPublic;
  final bool isStackable;
  final bool firstOrderOnly;
  final bool emailVerifiedRequired;
  final int usageCount;
  final int uniqueUsers;
  final int currentUses;
  final int? maxUses;
  final int? maxUsesPerUser;
  final int? remainingUses;
  final int? campaignId;
  final int? userId;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final double revenueGross;
  final double revenueNet;
  final double discountTotal;
  final List<int> targetCategoryIds;
  final List<int> targetProductIds;

  bool get hasTargets =>
      targetCategoryIds.isNotEmpty || targetProductIds.isNotEmpty;

  factory PromotionAdminItem.fromJson(Map<String, dynamic> json) {
    final targets = readMap(json['targets']);
    return PromotionAdminItem(
      id: readInt(json['id']),
      code: json['code']?.toString() ?? '',
      description: json['description']?.toString(),
      discountType: json['discount_type']?.toString() ?? 'fixed',
      discountValue: readDouble(json['discount_value']),
      minOrderAmount: readDouble(json['min_order_amount']),
      isActive: readBool(json['is_active'], fallback: true),
      isPublic: readBool(json['is_public'], fallback: true),
      isStackable: readBool(json['is_stackable']),
      firstOrderOnly: readBool(json['first_order_only']),
      emailVerifiedRequired: readBool(json['email_verified_required']),
      usageCount: readInt(json['usage_count']),
      uniqueUsers: readInt(json['unique_users']),
      currentUses: readInt(json['current_uses']),
      maxUses: json['max_uses'] == null ? null : readInt(json['max_uses']),
      maxUsesPerUser: json['max_uses_per_user'] == null
          ? null
          : readInt(json['max_uses_per_user']),
      remainingUses: json['remaining_uses'] == null
          ? null
          : readInt(json['remaining_uses']),
      campaignId:
          json['campaign_id'] == null ? null : readInt(json['campaign_id']),
      userId: json['user_id'] == null ? null : readInt(json['user_id']),
      startsAt: readDateTime(json['starts_at']),
      endsAt: readDateTime(json['ends_at']),
      revenueGross: readDouble(json['revenue_gross']),
      revenueNet: readDouble(json['revenue_net']),
      discountTotal: readDouble(json['discount_total']),
      targetCategoryIds: _intList(targets['category_ids']),
      targetProductIds: _intList(targets['product_ids']),
    );
  }

  static List<int> _intList(Object? value) {
    return (value as List? ?? const []).map(readInt).toList();
  }
}

class PromotionCampaign {
  const PromotionCampaign({
    required this.id,
    required this.name,
    required this.prefix,
    required this.codes,
    this.description,
  });

  final int id;
  final String name;
  final String prefix;
  final String? description;
  final List<String> codes;

  factory PromotionCampaign.fromJson(Map<String, dynamic> json) {
    return PromotionCampaign(
      id: readInt(json['id']),
      name: json['name']?.toString() ?? '',
      prefix: json['prefix']?.toString() ?? '',
      description: json['description']?.toString(),
      codes: (json['codes'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(),
    );
  }
}

class PromotionUsage {
  const PromotionUsage({
    required this.id,
    required this.userId,
    required this.orderId,
    required this.subtotal,
    required this.discountTotal,
    required this.total,
    this.orderStatus,
    this.usedAt,
  });

  final int id;
  final int userId;
  final int orderId;
  final String? orderStatus;
  final double subtotal;
  final double discountTotal;
  final double total;
  final DateTime? usedAt;

  factory PromotionUsage.fromJson(Map<String, dynamic> json) {
    return PromotionUsage(
      id: readInt(json['id']),
      userId: readInt(json['user_id']),
      orderId: readInt(json['order_id']),
      orderStatus: json['order_status']?.toString(),
      subtotal: readDouble(json['subtotal']),
      discountTotal: readDouble(json['discount_total']),
      total: readDouble(json['total']),
      usedAt: readDateTime(json['used_at']),
    );
  }
}
