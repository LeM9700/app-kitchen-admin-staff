import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/catalog/presentation/catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [
    Size(390, 844),
    Size(768, 1024),
    Size(1024, 768),
    Size(1280, 800),
    Size(1440, 900),
    Size(1920, 1080),
  ]) {
    testWidgets('catalog responsive ${size.width.toInt()}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProductsProvider.overrideWith((ref) async => _products),
            catalogCategoriesProvider.overrideWith((ref) async => _categories),
            currentPermissionSetProvider.overrideWithValue(
              const PermissionSet(role: 'admin', permissions: null),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: const Scaffold(body: CatalogPage()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Catalogue'), findsOneWidget);
      expect(find.text('Margherita'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}

const _categories = [
  CatalogCategory(
    id: 1,
    name: 'Pizzas',
    displayOrder: 1,
    preparationStation: 'kitchen',
    isActive: true,
  ),
  CatalogCategory(
    id: 2,
    name: 'Boissons',
    displayOrder: 2,
    preparationStation: 'counter',
    isActive: true,
  ),
];

const _products = [
  CatalogProduct(
    id: 1,
    categoryId: 1,
    categoryName: 'Pizzas',
    name: 'Margherita',
    description: 'Tomate, mozzarella, basilic',
    basePrice: 11.5,
    isActive: true,
    available: true,
    effectivePreparationStation: 'kitchen',
    regulatoryComplete: true,
  ),
  CatalogProduct(
    id: 2,
    categoryId: 1,
    categoryName: 'Pizzas',
    name: 'Regina',
    description: 'Jambon, champignons',
    basePrice: 14,
    isActive: true,
    available: false,
    availabilityReason: 'Rupture champignons',
    effectivePreparationStation: 'kitchen',
    regulatoryComplete: false,
  ),
  CatalogProduct(
    id: 3,
    categoryId: 2,
    categoryName: 'Boissons',
    name: 'San Pellegrino',
    description: 'Eau petillante 50 cl',
    basePrice: 3.2,
    isActive: true,
    available: true,
    effectivePreparationStation: 'counter',
    regulatoryComplete: true,
  ),
];
