import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/api/paginated.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final stockRepositoryProvider = Provider<StockRepository>((ref) {
  return StockRepository(ref.watch(apiClientProvider));
});

final stockSearchProvider = StateProvider<String>((ref) => '');
final stockLevelFilterProvider = StateProvider<StockLevelFilter>((ref) {
  return StockLevelFilter.all;
});

final ingredientsProvider = FutureProvider.autoDispose<List<Ingredient>>((ref) {
  final search = ref.watch(stockSearchProvider).trim();
  final level = ref.watch(stockLevelFilterProvider);
  return ref.watch(stockRepositoryProvider).listIngredients(
        pageSize: 100,
        search: search.length >= 2 ? search : null,
        belowThreshold: level == StockLevelFilter.low ? true : null,
      );
});

final stockAlertsProvider = FutureProvider.autoDispose<List<Ingredient>>((ref) {
  return ref.watch(stockRepositoryProvider).listAlerts();
});

final stockMovementsProvider = FutureProvider.autoDispose<List<StockMovement>>((
  ref,
) {
  return ref.watch(stockRepositoryProvider).listMovements(pageSize: 30);
});

final stockMissingRecipesProvider =
    FutureProvider.autoDispose<List<MissingStockRecipe>>((ref) {
  return ref.watch(stockRepositoryProvider).listMissingRecipes();
});

final stockDlcOverviewProvider =
    FutureProvider.autoDispose<StockDlcOverview>((ref) {
  return ref.watch(stockRepositoryProvider).getDlcOverview();
});

final adjustmentRequestsProvider =
    FutureProvider.autoDispose<List<StockAdjustmentRequest>>((ref) {
  return ref
      .watch(stockRepositoryProvider)
      .listAdjustmentRequests(pageSize: 50);
});

enum StockLevelFilter { all, low, out }

class StockRepository {
  const StockRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Ingredient>> listIngredients({
    int page = 1,
    int pageSize = 50,
    String? search,
    bool? belowThreshold,
    String? unit,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.stockIngredients,
      queryParameters: {
        'page': page,
        'page_size': pageSize,
        if (search != null && search.trim().length >= 2)
          'search': search.trim(),
        if (belowThreshold != null) 'below_threshold': belowThreshold,
        if (unit != null && unit.trim().isNotEmpty) 'unit': unit.trim(),
      },
    );
    final result = PaginatedResult.fromJson(
      response.data as Map<String, dynamic>,
      Ingredient.fromJson,
    );
    return result.items;
  }

  Future<List<Ingredient>> listAlerts() async {
    final response = await _apiClient.get(ApiEndpoints.stockAlerts);
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map((value) => Ingredient.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  Future<List<StockMovement>> listMovements({
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.stockMovements,
      queryParameters: {'page': page, 'page_size': pageSize},
    );
    final result = PaginatedResult.fromJson(
      response.data as Map<String, dynamic>,
      StockMovement.fromJson,
    );
    return result.items;
  }

  Future<Ingredient> createIngredient({
    required String name,
    required String unit,
    required double currentQty,
    required double alertThreshold,
    double? purchasePricePerUnit,
    String? purchaseUnit,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.stockIngredients,
      data: {
        'name': name,
        'unit': unit,
        'current_qty': currentQty,
        'alert_threshold': alertThreshold,
        if (purchasePricePerUnit != null)
          'purchase_price_per_unit': purchasePricePerUnit,
        if (purchaseUnit != null && purchaseUnit.trim().isNotEmpty)
          'purchase_unit': purchaseUnit.trim(),
      },
    );
    return Ingredient.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Ingredient> patchIngredient({
    required int ingredientId,
    String? name,
    String? unit,
    double? alertThreshold,
    double? purchasePricePerUnit,
    String? purchaseUnit,
  }) async {
    final response = await _apiClient.patch(
      '${ApiEndpoints.stockIngredients}/$ingredientId',
      data: {
        if (name != null) 'name': name,
        if (unit != null) 'unit': unit,
        if (alertThreshold != null) 'alert_threshold': alertThreshold,
        if (purchasePricePerUnit != null)
          'purchase_price_per_unit': purchasePricePerUnit,
        if (purchaseUnit != null && purchaseUnit.trim().isNotEmpty)
          'purchase_unit': purchaseUnit.trim(),
      },
    );
    return Ingredient.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Ingredient> supply({
    required int ingredientId,
    required double quantity,
    required DateTime expiresAt,
    DateTime? receivedAt,
    int? useWithinHoursAfterOpening,
    int? tertiaryUseWithinHours,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.stockSupply,
      data: {
        'ingredient_id': ingredientId,
        'quantity': quantity,
        'expires_at': expiresAt.toIso8601String(),
        if (receivedAt != null) 'received_at': receivedAt.toIso8601String(),
        if (useWithinHoursAfterOpening != null)
          'use_within_hours_after_opening': useWithinHoursAfterOpening,
        if (tertiaryUseWithinHours != null)
          'tertiary_use_within_hours': tertiaryUseWithinHours,
      },
    );
    return Ingredient.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<IngredientBatch>> listBatches(int ingredientId) async {
    final response = await _apiClient.get(
      ApiEndpoints.stockIngredientBatches(ingredientId),
    );
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => IngredientBatch.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
  }

  Future<IngredientBatch> createBatch({
    required int ingredientId,
    required double quantity,
    required DateTime expiresAt,
    int? useWithinHoursAfterOpening,
    int? tertiaryUseWithinHours,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.stockIngredientBatches(ingredientId),
      data: {
        'quantity': quantity,
        'expires_at': expiresAt.toIso8601String(),
        if (useWithinHoursAfterOpening != null)
          'use_within_hours_after_opening': useWithinHoursAfterOpening,
        if (tertiaryUseWithinHours != null)
          'tertiary_use_within_hours': tertiaryUseWithinHours,
      },
    );
    return IngredientBatch.fromJson(response.data as Map<String, dynamic>);
  }

  Future<IngredientBatch> openBatch(int batchId) async {
    final response = await _apiClient.post(
      ApiEndpoints.stockBatchOpen(batchId),
    );
    return IngredientBatch.fromJson(response.data as Map<String, dynamic>);
  }

  Future<IngredientBatch> startBatchUse({
    required int batchId,
    int? tertiaryUseWithinHours,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.stockBatchStartUse(batchId),
      data: {
        if (tertiaryUseWithinHours != null)
          'tertiary_use_within_hours': tertiaryUseWithinHours,
      },
    );
    return IngredientBatch.fromJson(response.data as Map<String, dynamic>);
  }

  Future<IngredientBatch> discardBatch({
    required int batchId,
    required String reason,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.stockBatchDiscard(batchId),
      data: {'reason': reason},
    );
    return IngredientBatch.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StockAdjustmentRequest> createAdjustmentRequest({
    required int ingredientId,
    required double quantityDelta,
    required String reason,
    String? note,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.stockAdjustmentRequests,
      data: {
        'ingredient_id': ingredientId,
        'quantity_delta': quantityDelta,
        'reason': reason,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return StockAdjustmentRequest.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<List<StockAdjustmentRequest>> listAdjustmentRequests({
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.stockAdjustmentRequests,
      queryParameters: {'page': page, 'page_size': pageSize},
    );
    final result = PaginatedResult.fromJson(
      response.data as Map<String, dynamic>,
      StockAdjustmentRequest.fromJson,
    );
    return result.items;
  }

  Future<StockAdjustmentRequest> approveAdjustment(
    int requestId, {
    String? note,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.stockAdjustmentApprove(requestId),
      data: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
    );
    return StockAdjustmentRequest.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<StockAdjustmentRequest> rejectAdjustment(
    int requestId, {
    String? note,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.stockAdjustmentReject(requestId),
      data: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
    );
    return StockAdjustmentRequest.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<void> createProductRecipe({
    required int productId,
    required int ingredientId,
    required double quantity,
    String? unit,
  }) async {
    await _apiClient.post(
      ApiEndpoints.stockRecipeProduct,
      data: {
        'product_id': productId,
        'ingredient_id': ingredientId,
        'quantity': quantity,
        if (unit != null && unit.trim().isNotEmpty) 'unit': unit.trim(),
      },
    );
  }

  Future<void> createVariantRecipe({
    required int variantId,
    required int ingredientId,
    required double quantity,
    String? unit,
  }) async {
    await _apiClient.post(
      ApiEndpoints.stockRecipeVariant,
      data: {
        'variant_id': variantId,
        'ingredient_id': ingredientId,
        'quantity': quantity,
        if (unit != null && unit.trim().isNotEmpty) 'unit': unit.trim(),
      },
    );
  }

  Future<void> createExtraRecipe({
    required int extraId,
    required int ingredientId,
    required double quantity,
    String? unit,
  }) async {
    await _apiClient.post(
      ApiEndpoints.stockRecipeExtra,
      data: {
        'extra_id': extraId,
        'ingredient_id': ingredientId,
        'quantity': quantity,
        if (unit != null && unit.trim().isNotEmpty) 'unit': unit.trim(),
      },
    );
  }

  Future<StockRecipe> getProductRecipe(int productId) async {
    final response = await _apiClient.get(
      ApiEndpoints.stockProductRecipe(productId),
    );
    return StockRecipe.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StockRecipe> getVariantRecipe(int variantId) async {
    final response = await _apiClient.get(
      ApiEndpoints.stockVariantRecipe(variantId),
    );
    return StockRecipe.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StockRecipe> getExtraRecipe(int extraId) async {
    final response = await _apiClient.get(
      ApiEndpoints.stockExtraRecipe(extraId),
    );
    return StockRecipe.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StockRecipe> replaceProductRecipe({
    required int productId,
    required List<StockRecipeInputLine> items,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.stockProductRecipe(productId),
      data: {'items': items.map((item) => item.toJson()).toList()},
    );
    return StockRecipe.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StockRecipe> replaceVariantRecipe({
    required int variantId,
    required List<StockRecipeInputLine> items,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.stockVariantRecipe(variantId),
      data: {'items': items.map((item) => item.toJson()).toList()},
    );
    return StockRecipe.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StockRecipe> replaceExtraRecipe({
    required int extraId,
    required List<StockRecipeInputLine> items,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.stockExtraRecipe(extraId),
      data: {'items': items.map((item) => item.toJson()).toList()},
    );
    return StockRecipe.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteRecipeLine({
    required String recipeType,
    required int recipeLineId,
  }) async {
    await _apiClient.delete(
      ApiEndpoints.stockRecipeLine(recipeType, recipeLineId),
    );
  }

  Future<List<MissingStockRecipe>> listMissingRecipes() async {
    final response = await _apiClient.get(ApiEndpoints.stockRecipesMissing);
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              MissingStockRecipe.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
  }

  Future<StockDlcOverview> getDlcOverview({
    int? ingredientId,
    String? dlcLevel,
    String? severity,
    String? status,
    int horizonHours = 72,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.stockDlcOverview,
      queryParameters: {
        if (ingredientId != null) 'ingredient_id': ingredientId,
        if (dlcLevel != null) 'dlc_level': dlcLevel,
        if (severity != null) 'severity': severity,
        if (status != null) 'status': status,
        'horizon_hours': horizonHours,
      },
    );
    return StockDlcOverview.fromJson(response.data as Map<String, dynamic>);
  }
}

class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.unit,
    required this.currentQty,
    required this.alertThreshold,
    required this.isBelowThreshold,
    this.purchasePricePerUnit,
    this.purchaseUnit,
  });

  final int id;
  final String name;
  final String unit;
  final double currentQty;
  final double alertThreshold;
  final bool isBelowThreshold;
  final double? purchasePricePerUnit;
  final String? purchaseUnit;

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      id: readInt(json['id']),
      name: json['name']?.toString() ?? '',
      unit: json['unit']?.toString() ?? '',
      currentQty: readDouble(json['current_qty']),
      alertThreshold: readDouble(json['alert_threshold']),
      isBelowThreshold: readBool(json['is_below_threshold']),
      purchasePricePerUnit: json['purchase_price_per_unit'] == null
          ? null
          : readDouble(json['purchase_price_per_unit']),
      purchaseUnit: json['purchase_unit']?.toString(),
    );
  }
}

class StockRecipeInputLine {
  const StockRecipeInputLine({
    required this.ingredientId,
    required this.quantity,
    this.unit,
  });

  final int ingredientId;
  final double quantity;
  final String? unit;

  Map<String, dynamic> toJson() {
    return {
      'ingredient_id': ingredientId,
      'quantity': quantity,
      if (unit != null && unit!.trim().isNotEmpty) 'unit': unit!.trim(),
    };
  }
}

class StockRecipe {
  const StockRecipe({
    required this.recipeType,
    required this.targetId,
    required this.items,
  });

  final String recipeType;
  final int targetId;
  final List<StockRecipeLine> items;

  factory StockRecipe.fromJson(Map<String, dynamic> json) {
    return StockRecipe(
      recipeType: json['recipe_type']?.toString() ?? 'product',
      targetId: readInt(json['target_id']),
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                StockRecipeLine.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
    );
  }
}

class StockRecipeLine {
  const StockRecipeLine({
    required this.id,
    required this.recipeType,
    required this.targetId,
    required this.ingredientId,
    required this.quantity,
    this.ingredientName,
    this.unit,
  });

  final int id;
  final String recipeType;
  final int targetId;
  final int ingredientId;
  final String? ingredientName;
  final double quantity;
  final String? unit;

  factory StockRecipeLine.fromJson(Map<String, dynamic> json) {
    return StockRecipeLine(
      id: readInt(json['id']),
      recipeType: json['recipe_type']?.toString() ?? 'product',
      targetId: readInt(json['target_id']),
      ingredientId: readInt(json['ingredient_id']),
      ingredientName: json['ingredient_name']?.toString(),
      quantity: readDouble(json['quantity']),
      unit: json['unit']?.toString(),
    );
  }
}

class MissingStockRecipe {
  const MissingStockRecipe({
    required this.recipeType,
    required this.targetId,
    required this.name,
    this.productId,
  });

  final String recipeType;
  final int targetId;
  final String name;
  final int? productId;

  bool get isProduct => recipeType == 'product';
  bool get isVariant => recipeType == 'variant';
  bool get isExtra => recipeType == 'extra';

  factory MissingStockRecipe.fromJson(Map<String, dynamic> json) {
    return MissingStockRecipe(
      recipeType: json['recipe_type']?.toString() ?? 'product',
      targetId: readInt(json['target_id']),
      name: json['name']?.toString() ?? '',
      productId:
          json['product_id'] == null ? null : readInt(json['product_id']),
    );
  }
}

class IngredientBatch {
  const IngredientBatch({
    required this.id,
    required this.ingredientId,
    required this.quantity,
    required this.status,
    this.expiresAt,
    this.openedAt,
    this.primaryExpiresAt,
    this.secondaryStartedAt,
    this.secondaryUseWithinHours,
    this.secondaryExpiresAt,
    this.tertiaryStartedAt,
    this.tertiaryUseWithinHours,
    this.tertiaryExpiresAt,
    this.effectiveExpiresAt,
    this.effectiveDlcLevel,
    this.createdAt,
  });

  final int id;
  final int ingredientId;
  final double quantity;
  final String status;
  final DateTime? expiresAt;
  final DateTime? openedAt;
  final DateTime? primaryExpiresAt;
  final DateTime? secondaryStartedAt;
  final int? secondaryUseWithinHours;
  final DateTime? secondaryExpiresAt;
  final DateTime? tertiaryStartedAt;
  final int? tertiaryUseWithinHours;
  final DateTime? tertiaryExpiresAt;
  final DateTime? effectiveExpiresAt;
  final String? effectiveDlcLevel;
  final DateTime? createdAt;

  factory IngredientBatch.fromJson(Map<String, dynamic> json) {
    return IngredientBatch(
      id: readInt(json['id']),
      ingredientId: readInt(json['ingredient_id']),
      quantity: readDouble(json['quantity']),
      status: json['status']?.toString() ?? 'sealed',
      expiresAt: readDateTime(json['expires_at']),
      openedAt: readDateTime(json['opened_at']),
      primaryExpiresAt: readDateTime(json['primary_expires_at']),
      secondaryStartedAt: readDateTime(json['secondary_started_at']),
      secondaryUseWithinHours: json['secondary_use_within_hours'] == null
          ? null
          : readInt(json['secondary_use_within_hours']),
      secondaryExpiresAt: readDateTime(json['secondary_expires_at']),
      tertiaryStartedAt: readDateTime(json['tertiary_started_at']),
      tertiaryUseWithinHours: json['tertiary_use_within_hours'] == null
          ? null
          : readInt(json['tertiary_use_within_hours']),
      tertiaryExpiresAt: readDateTime(json['tertiary_expires_at']),
      effectiveExpiresAt: readDateTime(json['effective_expires_at']),
      effectiveDlcLevel: json['effective_dlc_level']?.toString(),
      createdAt: readDateTime(json['created_at']),
    );
  }
}

class StockDlcOverview {
  const StockDlcOverview({
    required this.counters,
    required this.items,
  });

  final StockDlcCounters counters;
  final List<StockDlcItem> items;

  factory StockDlcOverview.fromJson(Map<String, dynamic> json) {
    return StockDlcOverview(
      counters: StockDlcCounters.fromJson(
        Map<String, dynamic>.from(json['counters'] as Map? ?? const {}),
      ),
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => StockDlcItem.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
    );
  }

  int get criticalCount {
    return items
        .where(
          (item) =>
              item.severity == 'expired' ||
              item.severity == 'regularize' ||
              item.severity == 'critical',
        )
        .length;
  }

  bool get hasCriticalRisk => criticalCount > 0;
}

class StockDlcCounters {
  const StockDlcCounters({
    required this.totalBatches,
    required this.regularizeBatchCount,
    required this.primaryNearCount,
    required this.secondaryNearCount,
    required this.tertiaryNearCount,
    required this.expiredBatchCount,
    required this.missingOrNoncompliantCheckCount,
  });

  final int totalBatches;
  final int regularizeBatchCount;
  final int primaryNearCount;
  final int secondaryNearCount;
  final int tertiaryNearCount;
  final int expiredBatchCount;
  final int missingOrNoncompliantCheckCount;

  factory StockDlcCounters.fromJson(Map<String, dynamic> json) {
    return StockDlcCounters(
      totalBatches: readInt(json['total_batches']),
      regularizeBatchCount: readInt(json['regularize_batch_count']),
      primaryNearCount: readInt(json['primary_near_count']),
      secondaryNearCount: readInt(json['secondary_near_count']),
      tertiaryNearCount: readInt(json['tertiary_near_count']),
      expiredBatchCount: readInt(json['expired_batch_count']),
      missingOrNoncompliantCheckCount:
          readInt(json['missing_or_noncompliant_check_count']),
    );
  }
}

class StockDlcItem {
  const StockDlcItem({
    required this.batchId,
    required this.ingredientId,
    required this.ingredientName,
    required this.quantity,
    required this.status,
    required this.severity,
    required this.hasDlcCheck,
    required this.noncompliantCheckCount,
    this.dlcLevel,
    this.primaryExpiresAt,
    this.secondaryExpiresAt,
    this.tertiaryExpiresAt,
    this.effectiveExpiresAt,
    this.blockedReason,
  });

  final int batchId;
  final int ingredientId;
  final String ingredientName;
  final double quantity;
  final String status;
  final String severity;
  final bool hasDlcCheck;
  final int noncompliantCheckCount;
  final String? dlcLevel;
  final DateTime? primaryExpiresAt;
  final DateTime? secondaryExpiresAt;
  final DateTime? tertiaryExpiresAt;
  final DateTime? effectiveExpiresAt;
  final String? blockedReason;

  factory StockDlcItem.fromJson(Map<String, dynamic> json) {
    return StockDlcItem(
      batchId: readInt(json['batch_id']),
      ingredientId: readInt(json['ingredient_id']),
      ingredientName: json['ingredient_name']?.toString() ?? '',
      quantity: readDouble(json['quantity']),
      status: json['status']?.toString() ?? 'sealed',
      severity: json['severity']?.toString() ?? 'ok',
      hasDlcCheck: readBool(json['has_dlc_check']),
      noncompliantCheckCount: readInt(json['noncompliant_check_count']),
      dlcLevel: json['dlc_level']?.toString(),
      primaryExpiresAt: readDateTime(json['primary_expires_at']),
      secondaryExpiresAt: readDateTime(json['secondary_expires_at']),
      tertiaryExpiresAt: readDateTime(json['tertiary_expires_at']),
      effectiveExpiresAt: readDateTime(json['effective_expires_at']),
      blockedReason: json['blocked_reason']?.toString(),
    );
  }
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.ingredientId,
    required this.quantityDelta,
    required this.reason,
    this.userId,
    this.createdAt,
  });

  final int id;
  final int ingredientId;
  final double quantityDelta;
  final String reason;
  final int? userId;
  final DateTime? createdAt;

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    return StockMovement(
      id: readInt(json['id']),
      ingredientId: readInt(json['ingredient_id']),
      quantityDelta: readDouble(json['quantity_delta']),
      reason: json['reason']?.toString() ?? '',
      userId: json['user_id'] == null ? null : readInt(json['user_id']),
      createdAt: readDateTime(json['created_at']),
    );
  }
}

class StockAdjustmentRequest {
  const StockAdjustmentRequest({
    required this.id,
    required this.ingredientId,
    required this.quantityDelta,
    required this.reason,
    required this.status,
    required this.requestedByUserId,
    required this.isLargeAdjustment,
    this.note,
    this.reviewedByUserId,
    this.reviewedAt,
    this.createdAt,
  });

  final int id;
  final int ingredientId;
  final double quantityDelta;
  final String reason;
  final String status;
  final int requestedByUserId;
  final bool isLargeAdjustment;
  final String? note;
  final int? reviewedByUserId;
  final DateTime? reviewedAt;
  final DateTime? createdAt;

  factory StockAdjustmentRequest.fromJson(Map<String, dynamic> json) {
    return StockAdjustmentRequest(
      id: readInt(json['id']),
      ingredientId: readInt(json['ingredient_id']),
      quantityDelta: readDouble(json['quantity_delta']),
      reason: json['reason']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      requestedByUserId: readInt(json['requested_by_user_id']),
      reviewedByUserId: json['reviewed_by_user_id'] == null
          ? null
          : readInt(json['reviewed_by_user_id']),
      reviewedAt: readDateTime(json['reviewed_at']),
      isLargeAdjustment: readBool(json['is_large_adjustment']),
      note: json['note']?.toString(),
      createdAt: readDateTime(json['created_at']),
    );
  }
}
