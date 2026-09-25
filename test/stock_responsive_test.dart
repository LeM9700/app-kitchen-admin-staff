import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:app_admin_staff/features/stock/presentation/stock_page.dart';
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
    testWidgets('stock responsive ${size.width.toInt()}', (tester) async {
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
            ingredientsProvider.overrideWith((ref) async => _ingredients),
            stockAlertsProvider.overrideWith(
              (ref) async =>
                  _ingredients.where((item) => item.isBelowThreshold).toList(),
            ),
            stockMovementsProvider.overrideWith((ref) async => _movements),
            adjustmentRequestsProvider.overrideWith((ref) async => _requests),
            currentEstablishmentProvider.overrideWith(
              (ref) async => const Establishment(
                id: 1,
                name: 'Kitchen Test',
                timezone: 'Europe/Paris',
                isActive: true,
              ),
            ),
            currentPermissionSetProvider.overrideWithValue(
              const PermissionSet(role: 'admin', permissions: null),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: const Scaffold(body: StockPage()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Stock'), findsOneWidget);
      expect(find.text('Mozzarella'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}

const _ingredients = [
  Ingredient(
    id: 1,
    name: 'Mozzarella',
    unit: 'kg',
    currentQty: 0,
    alertThreshold: 5,
    isBelowThreshold: true,
  ),
  Ingredient(
    id: 2,
    name: 'Pate maison',
    unit: 'kg',
    currentQty: 12,
    alertThreshold: 6,
    isBelowThreshold: false,
  ),
  Ingredient(
    id: 3,
    name: 'Sauce tomate',
    unit: 'l',
    currentQty: 2.5,
    alertThreshold: 4,
    isBelowThreshold: true,
  ),
];

final _movements = [
  StockMovement(
    id: 1,
    ingredientId: 1,
    quantityDelta: -2,
    reason: 'inventory',
    createdAt: DateTime(2026, 9, 25, 12),
  ),
  StockMovement(
    id: 2,
    ingredientId: 2,
    quantityDelta: 5,
    reason: 'supply',
    createdAt: DateTime(2026, 9, 25, 11),
  ),
];

final _requests = [
  StockAdjustmentRequest(
    id: 1,
    ingredientId: 1,
    quantityDelta: -2,
    reason: 'loss',
    status: 'pending',
    requestedByUserId: 4,
    isLargeAdjustment: false,
    note: 'Comptage rush',
    createdAt: DateTime(2026, 9, 25, 12),
  ),
];
