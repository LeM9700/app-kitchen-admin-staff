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
  return ref
      .watch(stockRepositoryProvider)
      .listIngredients(
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
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.stockSupply,
      data: {'ingredient_id': ingredientId, 'quantity': quantity},
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
    DateTime? expiresAt,
    int? useWithinHoursAfterOpening,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.stockIngredientBatches(ingredientId),
      data: {
        'quantity': quantity,
        if (expiresAt != null) 'expires_at': expiresAt.toIso8601String(),
        if (useWithinHoursAfterOpening != null)
          'use_within_hours_after_opening': useWithinHoursAfterOpening,
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
      productId: json['product_id'] == null
          ? null
          : readInt(json['product_id']),
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
    this.effectiveExpiresAt,
    this.createdAt,
  });

  final int id;
  final int ingredientId;
  final double quantity;
  final String status;
  final DateTime? expiresAt;
  final DateTime? openedAt;
  final DateTime? effectiveExpiresAt;
  final DateTime? createdAt;

  factory IngredientBatch.fromJson(Map<String, dynamic> json) {
    return IngredientBatch(
      id: readInt(json['id']),
      ingredientId: readInt(json['ingredient_id']),
      quantity: readDouble(json['quantity']),
      status: json['status']?.toString() ?? 'sealed',
      expiresAt: readDateTime(json['expires_at']),
      openedAt: readDateTime(json['opened_at']),
      effectiveExpiresAt: readDateTime(json['effective_expires_at']),
      createdAt: readDateTime(json['created_at']),
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
