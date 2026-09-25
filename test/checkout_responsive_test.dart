import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/checkout/presentation/checkout_page.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const products = [
    CatalogProduct(
      id: 1,
      name: 'Margherita',
      categoryName: 'Pizzas',
      basePrice: 12,
      isActive: true,
      available: true,
      effectivePreparationStation: 'kitchen',
    ),
    CatalogProduct(
      id: 2,
      name: 'Burger maison',
      categoryName: 'Burgers',
      basePrice: 14,
      isActive: true,
      available: true,
      effectivePreparationStation: 'kitchen',
    ),
    CatalogProduct(
      id: 3,
      name: 'Tiramisu',
      categoryName: 'Desserts',
      basePrice: 6,
      isActive: true,
      available: true,
      effectivePreparationStation: 'kitchen',
    ),
  ];

  for (final size in const [
    Size(390, 844),
    Size(768, 1024),
    Size(1024, 768),
    Size(1280, 800),
    Size(1440, 900),
    Size(1920, 1080),
  ]) {
    testWidgets('checkout responsive ${size.width.toInt()}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogProductsProvider.overrideWith((ref) async => products),
            currentEstablishmentProvider.overrideWith(
              (ref) async => const Establishment(
                id: 1,
                name: 'Kitchen Test',
                timezone: 'Europe/Paris',
                isActive: true,
              ),
            ),
            tenantStatusProvider.overrideWith(
              (ref) async => const TenantStatus(
                isOpen: true,
                estimatedPrepTimeMinutes: 20,
                activeOrdersCount: 0,
              ),
            ),
            onlineStatusProvider.overrideWith((ref) => Stream.value(true)),
            currentPermissionSetProvider.overrideWithValue(
              const PermissionSet(role: 'admin', permissions: null),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: CheckoutPage())),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Caisse'), findsWidgets);
      expect(find.text('Margherita'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
