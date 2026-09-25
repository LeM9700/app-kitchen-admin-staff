import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';

bool catalogProductAvailable(CatalogProduct product) {
  return product.available ?? product.isActive;
}

bool matchesCatalogFilter(
  CatalogProduct product,
  CatalogAvailabilityFilter filter,
) {
  return switch (filter) {
    CatalogAvailabilityFilter.all => true,
    CatalogAvailabilityFilter.available => catalogProductAvailable(product),
    CatalogAvailabilityFilter.unavailable => !catalogProductAvailable(product),
    CatalogAvailabilityFilter.incomplete => !product.regulatoryComplete,
  };
}

String catalogStationLabel(String value) {
  return switch (value) {
    'kitchen' => 'Cuisine',
    'counter' => 'Comptoir',
    'none' => 'Aucune',
    'inherit' => 'Categorie',
    _ => value,
  };
}

String catalogStationSource(CatalogProduct product) {
  final explicit = product.preparationStation;
  if (explicit == null || explicit == 'inherit') {
    return 'Categorie';
  }
  return 'Produit';
}

String? catalogListImageUrl(CatalogProduct product) {
  final primary = product.primaryImage;
  if (primary != null && primary.urlThumbnail.isNotEmpty) {
    return primary.urlThumbnail;
  }
  if ((product.imageUrl ?? '').isNotEmpty) {
    return product.imageUrl;
  }
  return null;
}

Map<int, int> catalogProductCountsByCategory(List<CatalogProduct> products) {
  final counts = <int, int>{};
  for (final product in products) {
    final categoryId = product.categoryId;
    if (categoryId != null) {
      counts[categoryId] = (counts[categoryId] ?? 0) + 1;
    }
  }
  return counts;
}
