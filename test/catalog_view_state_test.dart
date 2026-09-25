import 'package:app_admin_staff/features/catalog/application/catalog_view_state.dart';
import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('derives operational availability without confusing isActive', () {
    expect(catalogProductAvailable(_product(available: true)), isTrue);
    expect(catalogProductAvailable(_product(available: false)), isFalse);
    expect(catalogProductAvailable(_product(isActive: false)), isFalse);
  });

  test('matches availability and regulatory filters locally', () {
    final available = _product(available: true, regulatoryComplete: true);
    final unavailable = _product(available: false, regulatoryComplete: true);
    final incomplete = _product(available: true, regulatoryComplete: false);

    expect(
      matchesCatalogFilter(available, CatalogAvailabilityFilter.available),
      isTrue,
    );
    expect(
      matchesCatalogFilter(unavailable, CatalogAvailabilityFilter.unavailable),
      isTrue,
    );
    expect(
      matchesCatalogFilter(incomplete, CatalogAvailabilityFilter.incomplete),
      isTrue,
    );
    expect(
      matchesCatalogFilter(available, CatalogAvailabilityFilter.incomplete),
      isFalse,
    );
  });

  test('labels station source and image fallback', () {
    expect(catalogStationLabel('kitchen'), 'Cuisine');
    expect(
      catalogStationSource(_product(preparationStation: null)),
      'Categorie',
    );
    expect(
      catalogStationSource(_product(preparationStation: 'counter')),
      'Produit',
    );
    expect(
      catalogListImageUrl(_product(imageUrl: 'https://img.test/a.jpg')),
      isNotNull,
    );
  });
}

CatalogProduct _product({
  bool isActive = true,
  bool? available,
  bool regulatoryComplete = true,
  String? preparationStation,
  String? imageUrl,
}) {
  return CatalogProduct(
    id: 1,
    name: 'Margherita',
    basePrice: 11.5,
    isActive: isActive,
    available: available,
    regulatoryComplete: regulatoryComplete,
    preparationStation: preparationStation,
    effectivePreparationStation: preparationStation ?? 'kitchen',
    imageUrl: imageUrl,
  );
}
