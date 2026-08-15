import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/api/paginated.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(ref.watch(apiClientProvider));
});

final catalogProductsProvider =
    FutureProvider.autoDispose<List<CatalogProduct>>((ref) {
  final query = ref.watch(catalogSearchProvider).trim();
  final categoryId = ref.watch(catalogCategoryFilterProvider);
  return ref.watch(catalogRepositoryProvider).listProducts(
        pageSize: 100,
        query: query.length >= 2 ? query : null,
        categoryId: categoryId,
      );
});

final catalogCategoriesProvider =
    FutureProvider.autoDispose<List<CatalogCategory>>((ref) {
  return ref.watch(catalogRepositoryProvider).listCategories(pageSize: 100);
});

final catalogSearchProvider = StateProvider<String>((ref) => '');
final catalogCategoryFilterProvider = StateProvider<int?>((ref) => null);
final catalogAvailabilityFilterProvider =
    StateProvider<CatalogAvailabilityFilter>((ref) {
  return CatalogAvailabilityFilter.all;
});

enum CatalogAvailabilityFilter { all, available, unavailable }

class CatalogRepository {
  const CatalogRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<CatalogProduct>> listProducts({
    int page = 1,
    int pageSize = 50,
    String? query,
    int? categoryId,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.catalogProducts,
      queryParameters: {
        'page': page,
        'page_size': pageSize,
        if (query != null && query.trim().length >= 2) 'q': query.trim(),
        if (categoryId != null) 'category_id': categoryId,
      },
    );
    final result = PaginatedResult.fromJson(
      response.data as Map<String, dynamic>,
      CatalogProduct.fromJson,
    );
    return result.items;
  }

  Future<List<CatalogCategory>> listCategories({
    int page = 1,
    int pageSize = 100,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.catalogCategories,
      queryParameters: {'page': page, 'page_size': pageSize},
    );
    final result = PaginatedResult.fromJson(
      response.data as Map<String, dynamic>,
      CatalogCategory.fromJson,
    );
    return result.items;
  }

  Future<CatalogCategory> createCategory({
    required String name,
    int displayOrder = 0,
    String preparationStation = 'kitchen',
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.catalogCategories,
      data: {
        'name': name,
        'display_order': displayOrder,
        'preparation_station': preparationStation,
      },
    );
    return CatalogCategory.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CatalogCategory> updateCategory({
    required int categoryId,
    String? name,
    int? displayOrder,
    String? preparationStation,
    bool? isActive,
  }) async {
    final response = await _apiClient.put(
      '${ApiEndpoints.catalogCategories}/$categoryId',
      data: {
        if (name != null) 'name': name,
        if (displayOrder != null) 'display_order': displayOrder,
        if (preparationStation != null)
          'preparation_station': preparationStation,
        if (isActive != null) 'is_active': isActive,
      },
    );
    return CatalogCategory.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CatalogProduct> getProduct(int productId) async {
    final response =
        await _apiClient.get(ApiEndpoints.catalogProduct(productId));
    return CatalogProduct.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CatalogProduct> createProduct({
    int? categoryId,
    required String name,
    String? description,
    required double basePrice,
    String? imageUrl,
    String? preparationStation,
    bool isActive = true,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.catalogProducts,
      data: {
        if (categoryId != null) 'category_id': categoryId,
        'name': name,
        if (description != null) 'description': description,
        'base_price': basePrice,
        if (imageUrl != null) 'image_url': imageUrl,
        if (preparationStation != null)
          'preparation_station': preparationStation,
        'is_active': isActive,
      },
    );
    return CatalogProduct.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CatalogProduct> updateProduct({
    required int productId,
    int? categoryId,
    String? name,
    String? description,
    double? basePrice,
    String? imageUrl,
    String? preparationStation,
    bool? isActive,
    String? priceChangeReason,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.catalogProduct(productId),
      data: {
        if (categoryId != null) 'category_id': categoryId,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (basePrice != null) 'base_price': basePrice,
        if (imageUrl != null) 'image_url': imageUrl,
        if (preparationStation != null)
          'preparation_station':
              preparationStation == 'inherit' ? null : preparationStation,
        if (isActive != null) 'is_active': isActive,
        if (priceChangeReason != null && priceChangeReason.trim().isNotEmpty)
          'price_change_reason': priceChangeReason.trim(),
      },
    );
    return CatalogProduct.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteProduct(int productId) async {
    await _apiClient.delete(ApiEndpoints.catalogProduct(productId));
  }

  Future<CatalogVariant> createVariant({
    required int productId,
    required String name,
    required double priceDelta,
    bool isAvailable = true,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.catalogProductVariants(productId),
      data: {
        'name': name,
        'price_delta': priceDelta,
        'is_available': isAvailable,
      },
    );
    return CatalogVariant.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CatalogVariant> updateVariant({
    required int productId,
    required int variantId,
    String? name,
    double? priceDelta,
    bool? isAvailable,
    String? priceChangeReason,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.catalogProductVariant(productId, variantId),
      data: {
        if (name != null) 'name': name,
        if (priceDelta != null) 'price_delta': priceDelta,
        if (isAvailable != null) 'is_available': isAvailable,
        if (priceChangeReason != null && priceChangeReason.trim().isNotEmpty)
          'price_change_reason': priceChangeReason.trim(),
      },
    );
    return CatalogVariant.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteVariant({
    required int productId,
    required int variantId,
  }) async {
    await _apiClient.delete(
      ApiEndpoints.catalogProductVariant(productId, variantId),
    );
  }

  Future<CatalogExtra> createExtra({
    required String name,
    required double price,
    bool isActive = true,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.catalogExtras,
      data: {
        'name': name,
        'price': price,
        'is_active': isActive,
      },
    );
    return CatalogExtra.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CatalogExtra> updateExtra({
    required int extraId,
    String? name,
    double? price,
    bool? isActive,
    String? priceChangeReason,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.catalogExtra(extraId),
      data: {
        if (name != null) 'name': name,
        if (price != null) 'price': price,
        if (isActive != null) 'is_active': isActive,
        if (priceChangeReason != null && priceChangeReason.trim().isNotEmpty)
          'price_change_reason': priceChangeReason.trim(),
      },
    );
    return CatalogExtra.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteExtra(int extraId) async {
    await _apiClient.delete(ApiEndpoints.catalogExtra(extraId));
  }

  Future<void> linkExtra({
    required int productId,
    required int extraId,
  }) async {
    await _apiClient.post(ApiEndpoints.catalogProductExtra(productId, extraId));
  }

  Future<void> unlinkExtra({
    required int productId,
    required int extraId,
  }) async {
    await _apiClient
        .delete(ApiEndpoints.catalogProductExtra(productId, extraId));
  }

  Future<List<ProductRecommendation>> listRecommendations(int productId) async {
    final response = await _apiClient.get(
      ApiEndpoints.catalogProductRecommendations(productId),
    );
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => ProductRecommendation.fromJson(
            Map<String, dynamic>.from(value),
          ),
        )
        .toList();
  }

  Future<ProductRecommendation> addRecommendation({
    required int productId,
    required int recommendedProductId,
    int displayOrder = 0,
    String? label,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.catalogProductRecommendations(productId),
      data: {
        'recommended_product_id': recommendedProductId,
        'display_order': displayOrder,
        if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      },
    );
    return ProductRecommendation.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<ProductRecommendation> updateRecommendation({
    required int productId,
    required int recommendationId,
    int? displayOrder,
    String? label,
    bool? isActive,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.catalogProductRecommendation(productId, recommendationId),
      data: {
        if (displayOrder != null) 'display_order': displayOrder,
        if (label != null) 'label': label.trim(),
        if (isActive != null) 'is_active': isActive,
      },
    );
    return ProductRecommendation.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<void> deleteRecommendation({
    required int productId,
    required int recommendationId,
  }) async {
    await _apiClient.delete(
      ApiEndpoints.catalogProductRecommendation(productId, recommendationId),
    );
  }

  Future<List<CatalogMediaImage>> listImages({
    required String entityType,
    required int entityId,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.catalogEntityImages(entityType, entityId),
    );
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              CatalogMediaImage.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
  }

  Future<CatalogMediaImage> uploadImage({
    required String entityType,
    required int entityId,
    required List<int> bytes,
    required String filename,
    String? altText,
    bool isPrimary = false,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.catalogEntityImages(entityType, entityId),
      queryParameters: {
        if (altText != null && altText.trim().isNotEmpty)
          'alt_text': altText.trim(),
        'is_primary': isPrimary,
      },
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
    );
    return CatalogMediaImage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteImage(int imageId) async {
    await _apiClient.delete(ApiEndpoints.catalogImage(imageId));
  }

  Future<CatalogMediaImage> setPrimaryImage({
    required int imageId,
    required String entityType,
    required int entityId,
  }) async {
    final response = await _apiClient.patch(
      ApiEndpoints.catalogImagePrimary(imageId),
      queryParameters: {
        'entity_type': entityType,
        'entity_id': entityId,
      },
    );
    return CatalogMediaImage.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<CatalogMediaImage>> reorderImages({
    required String entityType,
    required int entityId,
    required List<int> imageIds,
  }) async {
    final response = await _apiClient.patch(
      ApiEndpoints.catalogEntityImagesReorder(entityType, entityId),
      data: {'image_ids': imageIds},
    );
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              CatalogMediaImage.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
  }

  Future<List<AllergenDefinition>> listAllergens() async {
    final response = await _apiClient.get(ApiEndpoints.catalogAllergens);
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              AllergenDefinition.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
  }

  Future<ProductAllergenSummary> productAllergens(int productId) async {
    final response = await _apiClient.get(
      ApiEndpoints.catalogProductAllergens(productId),
    );
    return ProductAllergenSummary.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<ProductAllergen> patchProductAllergen({
    required int productId,
    required int allergenId,
    required String level,
    String? reason,
  }) async {
    final response = await _apiClient.patch(
      ApiEndpoints.catalogProductAllergen(productId, allergenId),
      data: {
        'level': level,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return ProductAllergen.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> recomputeProductAllergens(int productId) async {
    await _apiClient
        .post(ApiEndpoints.catalogProductAllergensRecompute(productId));
  }

  Future<List<DietaryTag>> listDietaryTags() async {
    final response = await _apiClient.get(ApiEndpoints.catalogDietaryTags);
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map((value) => DietaryTag.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  Future<List<DietaryTag>> setProductDietaryTags({
    required int productId,
    required List<int> tagIds,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.catalogProductDietaryTags(productId),
      data: {'tag_ids': tagIds},
    );
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map((value) => DietaryTag.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  Future<CatalogCompleteness> completeness() async {
    final response = await _apiClient.get(ApiEndpoints.catalogCompleteness);
    return CatalogCompleteness.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<PriceAuditEntry>> priceAudit({
    required String entityType,
    required int entityId,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.catalogPriceAudit(entityType, entityId),
      queryParameters: {'page': 1, 'page_size': 50},
    );
    final result = PaginatedResult.fromJson(
      response.data as Map<String, dynamic>,
      PriceAuditEntry.fromJson,
    );
    return result.items;
  }

  Future<CatalogCsvDryRun> importCsvDryRun({
    required String csvText,
    String? filename,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.catalogImportDryRun,
      data: {
        'csv_text': csvText,
        if (filename != null && filename.trim().isNotEmpty)
          'filename': filename.trim(),
      },
    );
    return CatalogCsvDryRun.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CatalogCsvConfirm> importCsvConfirm(String token) async {
    final response = await _apiClient.post(
      ApiEndpoints.catalogImportConfirm(token),
    );
    return CatalogCsvConfirm.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ProductAvailabilityOverride> setAvailabilityOverride({
    required int productId,
    required bool available,
    String? reason,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.productAvailabilityOverride(productId),
      data: {
        'available': available,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return ProductAvailabilityOverride.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<List<ProductAvailabilityOverride>> availabilityHistory(
    int productId,
  ) async {
    final response = await _apiClient.get(
      ApiEndpoints.productAvailabilityHistory(productId),
    );
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => ProductAvailabilityOverride.fromJson(
            Map<String, dynamic>.from(value),
          ),
        )
        .toList();
  }

  Future<String> exportCsv() {
    return _apiClient.getText(ApiEndpoints.catalogExportCsv);
  }
}

class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.name,
    required this.displayOrder,
    required this.preparationStation,
    required this.isActive,
  });

  final int id;
  final String name;
  final int displayOrder;
  final String preparationStation;
  final bool isActive;

  factory CatalogCategory.fromJson(Map<String, dynamic> json) {
    return CatalogCategory(
      id: readInt(json['id']),
      name: json['name']?.toString() ?? '',
      displayOrder: readInt(json['display_order']),
      preparationStation: json['preparation_station']?.toString() ?? 'kitchen',
      isActive: readBool(json['is_active'], fallback: true),
    );
  }
}

class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.name,
    required this.basePrice,
    required this.isActive,
    required this.effectivePreparationStation,
    this.variants = const [],
    this.extras = const [],
    this.allergens = const [],
    this.dietaryTags = const [],
    this.recommendations = const [],
    this.gallery = const [],
    this.categoryId,
    this.categoryName,
    this.description,
    this.imageUrl,
    this.primaryImage,
    this.preparationStation,
    this.available,
    this.availabilityReason,
    this.regulatoryComplete = false,
  });

  final int id;
  final int? categoryId;
  final String? categoryName;
  final String name;
  final String? description;
  final double basePrice;
  final String? imageUrl;
  final CatalogMediaImage? primaryImage;
  final String? preparationStation;
  final String effectivePreparationStation;
  final List<CatalogVariant> variants;
  final List<CatalogExtra> extras;
  final List<String> allergens;
  final List<String> dietaryTags;
  final List<CatalogProduct> recommendations;
  final List<CatalogMediaImage> gallery;
  final bool isActive;
  final bool? available;
  final String? availabilityReason;
  final bool regulatoryComplete;

  factory CatalogProduct.fromJson(Map<String, dynamic> json) {
    final category = readMap(json['category']);
    final availability = readMap(json['availability']);
    return CatalogProduct(
      id: readInt(json['id']),
      categoryId: json['category_id'] == null
          ? (category.isEmpty ? null : readInt(category['id']))
          : readInt(json['category_id']),
      categoryName: category['name']?.toString(),
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      basePrice: readDouble(json['base_price']),
      imageUrl: json['image_url']?.toString(),
      primaryImage: readMap(json['primary_image']).isEmpty
          ? null
          : CatalogMediaImage.fromJson(readMap(json['primary_image'])),
      preparationStation: json['preparation_station']?.toString(),
      variants: (json['variants'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                CatalogVariant.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
      extras: (json['extras'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => CatalogExtra.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
      allergens: (json['allergens'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => value['name']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toList(),
      dietaryTags: (json['dietary_tags'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => value['name']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toList(),
      recommendations: (json['recommendations'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                CatalogProduct.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
      gallery: (json['gallery'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                CatalogMediaImage.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
      effectivePreparationStation:
          json['effective_preparation_station']?.toString() ??
              json['preparation_station']?.toString() ??
              category['preparation_station']?.toString() ??
              'kitchen',
      isActive: readBool(json['is_active'], fallback: true),
      available:
          availability.isEmpty ? null : readBool(availability['available']),
      availabilityReason: availability['reason']?.toString(),
      regulatoryComplete: readBool(json['regulatory_complete']),
    );
  }
}

class CatalogVariant {
  const CatalogVariant({
    required this.id,
    required this.productId,
    required this.name,
    required this.priceDelta,
    required this.isActive,
  });

  final int id;
  final int productId;
  final String name;
  final double priceDelta;
  final bool isActive;

  factory CatalogVariant.fromJson(Map<String, dynamic> json) {
    return CatalogVariant(
      id: readInt(json['id']),
      productId: readInt(json['product_id']),
      name: json['name']?.toString() ?? '',
      priceDelta: readDouble(json['price_delta']),
      isActive: readBool(json['is_active'], fallback: true),
    );
  }
}

class CatalogExtra {
  const CatalogExtra({
    required this.id,
    required this.name,
    required this.price,
    required this.isActive,
  });

  final int id;
  final String name;
  final double price;
  final bool isActive;

  factory CatalogExtra.fromJson(Map<String, dynamic> json) {
    return CatalogExtra(
      id: readInt(json['id']),
      name: json['name']?.toString() ?? '',
      price: readDouble(json['price']),
      isActive: readBool(json['is_active'], fallback: true),
    );
  }
}

class ProductAvailabilityOverride {
  const ProductAvailabilityOverride({
    required this.id,
    required this.productId,
    required this.available,
    required this.changedByUserId,
    required this.createdAt,
    this.reason,
  });

  final int id;
  final int productId;
  final bool available;
  final int changedByUserId;
  final DateTime? createdAt;
  final String? reason;

  factory ProductAvailabilityOverride.fromJson(Map<String, dynamic> json) {
    return ProductAvailabilityOverride(
      id: readInt(json['id']),
      productId: readInt(json['product_id']),
      available: readBool(json['available'], fallback: true),
      changedByUserId: readInt(json['changed_by_user_id']),
      createdAt: readDateTime(json['created_at']),
      reason: json['reason']?.toString(),
    );
  }
}

class CatalogMediaImage {
  const CatalogMediaImage({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.url,
    required this.urlThumbnail,
    required this.urlMedium,
    required this.format,
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.isPrimary,
    required this.displayOrder,
    this.altText,
    this.createdAt,
  });

  final int id;
  final String entityType;
  final int entityId;
  final String url;
  final String urlThumbnail;
  final String urlMedium;
  final String format;
  final int sizeBytes;
  final int width;
  final int height;
  final bool isPrimary;
  final int displayOrder;
  final String? altText;
  final DateTime? createdAt;

  factory CatalogMediaImage.fromJson(Map<String, dynamic> json) {
    return CatalogMediaImage(
      id: readInt(json['id']),
      entityType: json['entity_type']?.toString() ?? '',
      entityId: readInt(json['entity_id']),
      url: json['url']?.toString() ?? '',
      urlThumbnail:
          json['url_thumbnail']?.toString() ?? json['url']?.toString() ?? '',
      urlMedium:
          json['url_medium']?.toString() ?? json['url']?.toString() ?? '',
      format: json['format']?.toString() ?? '',
      sizeBytes: readInt(json['size_bytes']),
      width: readInt(json['width']),
      height: readInt(json['height']),
      isPrimary: readBool(json['is_primary']),
      displayOrder: readInt(json['display_order']),
      altText: json['alt_text']?.toString(),
      createdAt: readDateTime(json['created_at']),
    );
  }
}

class AllergenDefinition {
  const AllergenDefinition({
    required this.id,
    required this.name,
    required this.slug,
    required this.isRegulatory,
    this.description,
  });

  final int id;
  final String name;
  final String slug;
  final bool isRegulatory;
  final String? description;

  factory AllergenDefinition.fromJson(Map<String, dynamic> json) {
    return AllergenDefinition(
      id: readInt(json['id']),
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      isRegulatory: readBool(json['is_regulatory']),
      description: json['description']?.toString(),
    );
  }
}

class ProductAllergen {
  const ProductAllergen({
    required this.allergenId,
    required this.allergenName,
    required this.allergenSlug,
    required this.level,
    required this.source,
    required this.isRegulatory,
  });

  final int allergenId;
  final String allergenName;
  final String allergenSlug;
  final String level;
  final String source;
  final bool isRegulatory;

  factory ProductAllergen.fromJson(Map<String, dynamic> json) {
    return ProductAllergen(
      allergenId: readInt(json['allergen_id']),
      allergenName:
          json['allergen_name']?.toString() ?? json['name']?.toString() ?? '',
      allergenSlug:
          json['allergen_slug']?.toString() ?? json['slug']?.toString() ?? '',
      level: json['level']?.toString() ?? 'absent',
      source: json['source']?.toString() ?? 'manual',
      isRegulatory: readBool(json['is_regulatory']),
    );
  }
}

class DietaryTag {
  const DietaryTag({
    required this.id,
    required this.name,
    required this.slug,
  });

  final int id;
  final String name;
  final String slug;

  factory DietaryTag.fromJson(Map<String, dynamic> json) {
    return DietaryTag(
      id: readInt(json['id']),
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
    );
  }
}

class ProductAllergenSummary {
  const ProductAllergenSummary({
    required this.allergens,
    required this.dietaryTags,
    required this.regulatoryComplete,
  });

  final List<ProductAllergen> allergens;
  final List<DietaryTag> dietaryTags;
  final bool regulatoryComplete;

  factory ProductAllergenSummary.fromJson(Map<String, dynamic> json) {
    return ProductAllergenSummary(
      allergens: (json['allergens'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) =>
                ProductAllergen.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
      dietaryTags: (json['dietary_tags'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => DietaryTag.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
      regulatoryComplete: readBool(json['regulatory_complete']),
    );
  }
}

class ProductRecommendation {
  const ProductRecommendation({
    required this.id,
    required this.productId,
    required this.recommendedProductId,
    required this.displayOrder,
    required this.isActive,
    this.label,
    this.product,
  });

  final int id;
  final int productId;
  final int recommendedProductId;
  final int displayOrder;
  final bool isActive;
  final String? label;
  final CatalogProduct? product;

  factory ProductRecommendation.fromJson(Map<String, dynamic> json) {
    final product = readMap(json['product']);
    return ProductRecommendation(
      id: readInt(json['id']),
      productId: readInt(json['product_id']),
      recommendedProductId: readInt(json['recommended_product_id']),
      displayOrder: readInt(json['display_order']),
      isActive: readBool(json['is_active'], fallback: true),
      label: json['label']?.toString(),
      product: product.isEmpty ? null : CatalogProduct.fromJson(product),
    );
  }
}

class CatalogCompleteness {
  const CatalogCompleteness({
    required this.totalProducts,
    required this.completeProducts,
    required this.completionPercent,
  });

  final int totalProducts;
  final int completeProducts;
  final double completionPercent;

  int get incompleteProducts => totalProducts - completeProducts;

  factory CatalogCompleteness.fromJson(Map<String, dynamic> json) {
    return CatalogCompleteness(
      totalProducts: readInt(json['total_products']),
      completeProducts: readInt(json['complete_products']),
      completionPercent: readDouble(json['completion_percent']),
    );
  }
}

class PriceAuditEntry {
  const PriceAuditEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.newPrice,
    required this.source,
    this.oldPrice,
    this.changedByUserId,
    this.reason,
    this.changedAt,
  });

  final int id;
  final String entityType;
  final int entityId;
  final double? oldPrice;
  final double newPrice;
  final int? changedByUserId;
  final String source;
  final String? reason;
  final DateTime? changedAt;

  factory PriceAuditEntry.fromJson(Map<String, dynamic> json) {
    return PriceAuditEntry(
      id: readInt(json['id']),
      entityType: json['entity_type']?.toString() ?? '',
      entityId: readInt(json['entity_id']),
      oldPrice:
          json['old_price'] == null ? null : readDouble(json['old_price']),
      newPrice: readDouble(json['new_price']),
      changedByUserId: json['changed_by_user_id'] == null
          ? null
          : readInt(json['changed_by_user_id']),
      source: json['source']?.toString() ?? '',
      reason: json['reason']?.toString(),
      changedAt: readDateTime(json['changed_at']),
    );
  }
}

class CatalogCsvDryRun {
  const CatalogCsvDryRun({
    required this.token,
    required this.valid,
    required this.totalRows,
    required this.previews,
    required this.errors,
  });

  final String token;
  final bool valid;
  final int totalRows;
  final List<CatalogCsvPreview> previews;
  final List<CatalogCsvError> errors;

  factory CatalogCsvDryRun.fromJson(Map<String, dynamic> json) {
    return CatalogCsvDryRun(
      token: json['token']?.toString() ?? '',
      valid: readBool(json['valid']),
      totalRows: readInt(json['total_rows']),
      previews: (json['previews'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => CatalogCsvPreview.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList(),
      errors: (json['errors'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => CatalogCsvError.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList(),
    );
  }
}

class CatalogCsvConfirm {
  const CatalogCsvConfirm({
    required this.token,
    required this.imported,
    required this.totalRows,
    required this.created,
    required this.updated,
    required this.linked,
    required this.errors,
  });

  final String token;
  final bool imported;
  final int totalRows;
  final int created;
  final int updated;
  final int linked;
  final List<CatalogCsvError> errors;

  factory CatalogCsvConfirm.fromJson(Map<String, dynamic> json) {
    return CatalogCsvConfirm(
      token: json['token']?.toString() ?? '',
      imported: readBool(json['imported']),
      totalRows: readInt(json['total_rows']),
      created: readInt(json['created']),
      updated: readInt(json['updated']),
      linked: readInt(json['linked']),
      errors: (json['errors'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => CatalogCsvError.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList(),
    );
  }
}

class CatalogCsvPreview {
  const CatalogCsvPreview({
    required this.row,
    required this.action,
    required this.entityType,
    required this.key,
  });

  final int row;
  final String action;
  final String entityType;
  final String key;

  factory CatalogCsvPreview.fromJson(Map<String, dynamic> json) {
    return CatalogCsvPreview(
      row: readInt(json['row']),
      action: json['action']?.toString() ?? '',
      entityType: json['entity_type']?.toString() ?? '',
      key: json['key']?.toString() ?? '',
    );
  }
}

class CatalogCsvError {
  const CatalogCsvError({
    required this.row,
    required this.code,
    required this.detail,
  });

  final int row;
  final String code;
  final String detail;

  factory CatalogCsvError.fromJson(Map<String, dynamic> json) {
    return CatalogCsvError(
      row: readInt(json['row']),
      code: json['code']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
    );
  }
}
