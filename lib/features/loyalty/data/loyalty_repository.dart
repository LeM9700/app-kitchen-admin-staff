import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final loyaltyRepositoryProvider = Provider<LoyaltyRepository>((ref) {
  return LoyaltyRepository(ref.watch(apiClientProvider));
});

final loyaltyConfigProvider = FutureProvider.autoDispose<LoyaltyConfig>((ref) {
  return ref.watch(loyaltyRepositoryProvider).config();
});

final loyaltyRulesProvider =
    FutureProvider.autoDispose<List<LoyaltyRule>>((ref) {
  return ref.watch(loyaltyRepositoryProvider).rules();
});

final loyaltyRewardsProvider =
    FutureProvider.autoDispose<List<LoyaltyReward>>((ref) {
  return ref.watch(loyaltyRepositoryProvider).rewards();
});

final loyaltyStatsProvider = FutureProvider.autoDispose<LoyaltyStats>((ref) {
  return ref.watch(loyaltyRepositoryProvider).stats();
});

class LoyaltyRepository {
  const LoyaltyRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<LoyaltyConfig> config() async {
    final response = await _apiClient.get(ApiEndpoints.loyaltyConfig);
    return LoyaltyConfig.fromJson(response.data as Map<String, dynamic>);
  }

  Future<LoyaltyConfig> updateConfig({
    required double baseRatio,
    required int? pointsExpiryDays,
    required double pointsToEuroRate,
    required double maxCumulativeMultiplier,
    required bool isActive,
  }) async {
    final response = await _apiClient.patch(
      ApiEndpoints.loyaltyConfig,
      data: {
        'base_ratio': baseRatio,
        'points_expiry_days': pointsExpiryDays,
        'points_to_euro_rate': pointsToEuroRate,
        'max_cumulative_multiplier': maxCumulativeMultiplier,
        'is_active': isActive,
      },
    );
    return LoyaltyConfig.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<LoyaltyRule>> rules() async {
    final response = await _apiClient.get(ApiEndpoints.loyaltyRules);
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map((value) => LoyaltyRule.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  Future<LoyaltyRule> createRule({
    required String name,
    required String ruleType,
    int? categoryId,
    required double multiplier,
    int priority = 0,
    bool isActive = true,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.loyaltyRules,
      data: {
        'name': name,
        'rule_type': ruleType,
        if (categoryId != null) 'category_id': categoryId,
        'multiplier': multiplier,
        'priority': priority,
        'is_active': isActive,
        if (ruleType == 'day_multiplier')
          'days_of_week': const [0, 1, 2, 3, 4, 5, 6],
      },
    );
    return LoyaltyRule.fromJson(response.data as Map<String, dynamic>);
  }

  Future<LoyaltyRule> updateRule({
    required int ruleId,
    String? name,
    double? multiplier,
    int? priority,
    bool? isActive,
  }) async {
    final response = await _apiClient.patch(
      ApiEndpoints.loyaltyRule(ruleId),
      data: {
        if (name != null) 'name': name,
        if (multiplier != null) 'multiplier': multiplier,
        if (priority != null) 'priority': priority,
        if (isActive != null) 'is_active': isActive,
      },
    );
    return LoyaltyRule.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<LoyaltyReward>> rewards() async {
    final response = await _apiClient.get(ApiEndpoints.loyaltyRewards);
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => LoyaltyReward.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
  }

  Future<LoyaltyReward> createReward({
    required String name,
    required String rewardType,
    required int pointsRequired,
    double? discountAmount,
    int? productId,
    bool isActive = true,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.loyaltyRewards,
      data: {
        'name': name,
        'reward_type': rewardType,
        'points_required': pointsRequired,
        if (discountAmount != null) 'discount_amount': discountAmount,
        if (productId != null) 'product_id': productId,
        'is_active': isActive,
      },
    );
    return LoyaltyReward.fromJson(response.data as Map<String, dynamic>);
  }

  Future<LoyaltyReward> updateReward({
    required int rewardId,
    String? name,
    int? pointsRequired,
    double? discountAmount,
    int? productId,
    bool? isActive,
  }) async {
    final response = await _apiClient.patch(
      ApiEndpoints.loyaltyReward(rewardId),
      data: {
        if (name != null) 'name': name,
        if (pointsRequired != null) 'points_required': pointsRequired,
        if (discountAmount != null) 'discount_amount': discountAmount,
        if (productId != null) 'product_id': productId,
        if (isActive != null) 'is_active': isActive,
      },
    );
    return LoyaltyReward.fromJson(response.data as Map<String, dynamic>);
  }

  Future<LoyaltyStats> stats() async {
    final response = await _apiClient.get(ApiEndpoints.loyaltyStats);
    return LoyaltyStats.fromJson(response.data as Map<String, dynamic>);
  }

  Future<LoyaltyAccount> account(int userId) async {
    final response = await _apiClient.get(ApiEndpoints.loyaltyUser(userId));
    return LoyaltyAccount.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<LoyaltyTransaction>> transactions(int userId) async {
    final response = await _apiClient.get(
      ApiEndpoints.loyaltyUserTransactions(userId),
      queryParameters: {'page': 1, 'limit': 10},
    );
    return (readMap(response.data)['items'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => LoyaltyTransaction.fromJson(
            Map<String, dynamic>.from(value),
          ),
        )
        .toList();
  }
}

class LoyaltyConfig {
  const LoyaltyConfig({
    required this.id,
    required this.baseRatio,
    required this.pointsToEuroRate,
    required this.maxCumulativeMultiplier,
    required this.isActive,
    this.pointsExpiryDays,
  });

  final int id;
  final double baseRatio;
  final int? pointsExpiryDays;
  final double pointsToEuroRate;
  final double maxCumulativeMultiplier;
  final bool isActive;

  factory LoyaltyConfig.fromJson(Map<String, dynamic> json) {
    return LoyaltyConfig(
      id: readInt(json['id']),
      baseRatio: readDouble(json['base_ratio']),
      pointsExpiryDays: json['points_expiry_days'] == null
          ? null
          : readInt(json['points_expiry_days']),
      pointsToEuroRate: readDouble(json['points_to_euro_rate']),
      maxCumulativeMultiplier: readDouble(json['max_cumulative_multiplier']),
      isActive: readBool(json['is_active'], fallback: true),
    );
  }
}

class LoyaltyRule {
  const LoyaltyRule({
    required this.id,
    required this.name,
    required this.ruleType,
    required this.multiplier,
    required this.priority,
    required this.isActive,
    this.categoryId,
  });

  final int id;
  final String name;
  final String ruleType;
  final int? categoryId;
  final double multiplier;
  final int priority;
  final bool isActive;

  factory LoyaltyRule.fromJson(Map<String, dynamic> json) {
    return LoyaltyRule(
      id: readInt(json['id']),
      name: json['name']?.toString() ?? '',
      ruleType: json['rule_type']?.toString() ?? '',
      categoryId:
          json['category_id'] == null ? null : readInt(json['category_id']),
      multiplier: readDouble(json['multiplier']),
      priority: readInt(json['priority']),
      isActive: readBool(json['is_active'], fallback: true),
    );
  }
}

class LoyaltyReward {
  const LoyaltyReward({
    required this.id,
    required this.name,
    required this.rewardType,
    required this.pointsRequired,
    required this.isActive,
    this.discountAmount,
    this.productId,
  });

  final int id;
  final String name;
  final String rewardType;
  final int pointsRequired;
  final double? discountAmount;
  final int? productId;
  final bool isActive;

  factory LoyaltyReward.fromJson(Map<String, dynamic> json) {
    return LoyaltyReward(
      id: readInt(json['id']),
      name: json['name']?.toString() ?? '',
      rewardType: json['reward_type']?.toString() ?? '',
      pointsRequired: readInt(json['points_required']),
      discountAmount: json['discount_amount'] == null
          ? null
          : readDouble(json['discount_amount']),
      productId:
          json['product_id'] == null ? null : readInt(json['product_id']),
      isActive: readBool(json['is_active'], fallback: true),
    );
  }
}

class LoyaltyStats {
  const LoyaltyStats({
    required this.memberCount,
    required this.activeMemberCount,
    required this.pointsDistributed,
    required this.pointsRedeemed,
    required this.pointsExpired,
    required this.circulatingBalance,
    required this.redemptionRate,
  });

  final int memberCount;
  final int activeMemberCount;
  final int pointsDistributed;
  final int pointsRedeemed;
  final int pointsExpired;
  final int circulatingBalance;
  final double redemptionRate;

  factory LoyaltyStats.fromJson(Map<String, dynamic> json) {
    return LoyaltyStats(
      memberCount: readInt(json['member_count']),
      activeMemberCount: readInt(json['active_member_count']),
      pointsDistributed: readInt(json['points_distributed']),
      pointsRedeemed: readInt(json['points_redeemed']),
      pointsExpired: readInt(json['points_expired']),
      circulatingBalance: readInt(json['circulating_balance']),
      redemptionRate: readDouble(json['redemption_rate']),
    );
  }
}

class LoyaltyAccount {
  const LoyaltyAccount({
    required this.id,
    required this.userId,
    required this.points,
    required this.pointValueEuros,
    required this.expiringSoonPoints,
  });

  final int id;
  final int userId;
  final int points;
  final double pointValueEuros;
  final int expiringSoonPoints;

  factory LoyaltyAccount.fromJson(Map<String, dynamic> json) {
    return LoyaltyAccount(
      id: readInt(json['id']),
      userId: readInt(json['user_id']),
      points: readInt(json['points']),
      pointValueEuros: readDouble(json['point_value_euros']),
      expiringSoonPoints: readInt(json['expiring_soon_points']),
    );
  }
}

class LoyaltyTransaction {
  const LoyaltyTransaction({
    required this.id,
    required this.pointsDelta,
    required this.reason,
    required this.transactionType,
    required this.source,
    this.createdAt,
  });

  final int id;
  final int pointsDelta;
  final String reason;
  final String transactionType;
  final String source;
  final DateTime? createdAt;

  factory LoyaltyTransaction.fromJson(Map<String, dynamic> json) {
    return LoyaltyTransaction(
      id: readInt(json['id']),
      pointsDelta: readInt(json['points_delta']),
      reason: json['reason']?.toString() ?? '',
      transactionType: json['transaction_type']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      createdAt: readDateTime(json['created_at']),
    );
  }
}
