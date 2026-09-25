import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/features/auth/presentation/login_page.dart';
import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/checkout/presentation/checkout_page.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_page.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login screen renders the staff form', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_TestSessionController.new),
        ],
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pump();

    expect(find.text("O'Pizza Staff"), findsOneWidget);
    expect(find.text('Tenant'), findsOneWidget);
    expect(find.text('Connexion'), findsOneWidget);
  });

  testWidgets('checkout renders empty cart and loyalty fields', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsProvider.overrideWith((ref) async => const []),
          currentEstablishmentProvider.overrideWith(
            (ref) async => const Establishment(
              id: 1,
              name: 'Kitchen Test',
              timezone: 'Europe/Paris',
              isActive: true,
            ),
          ),
          onlineStatusProvider.overrideWith((ref) => Stream.value(true)),
          currentPermissionSetProvider.overrideWithValue(
            const PermissionSet(role: 'admin', permissions: null),
          ),
          tenantStatusProvider.overrideWith(
            (ref) async => const TenantStatus(
              isOpen: true,
              estimatedPrepTimeMinutes: 25,
              activeOrdersCount: 0,
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: CheckoutPage())),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Caisse'), findsOneWidget);
    expect(find.text('Aucun produit disponible'), findsOneWidget);
    expect(find.text('Voir panier'), findsOneWidget);
  });

  testWidgets('kitchen board renders empty preparation state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeOrdersProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: Scaffold(body: KitchenPage())),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.pump();

    expect(find.text('AUCUNE COMMANDE EN COURS'), findsOneWidget);
  });
}

class _TestSessionController extends SessionController {
  @override
  Future<SessionState> build() async {
    return const SessionState.unauthenticated();
  }
}
