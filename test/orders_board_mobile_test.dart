import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/orders/presentation/orders_board_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'orders board renders mobile service tabs at narrow widths',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._establishmentOverrides(),
            activeOrdersProvider.overrideWith(
              (ref) async => [
                const OrderSummary(
                  id: 1,
                  orderType: 'preparing',
                  status: 'preparing',
                  paymentStatus: 'paid',
                  source: 'customer',
                  total: 12.5,
                  deliveryFee: 0,
                ),
                const OrderSummary(
                  id: 2,
                  orderType: 'delivery',
                  status: 'ready',
                  paymentStatus: 'paid',
                  source: 'customer',
                  total: 21,
                  deliveryFee: 4,
                ),
              ],
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: OrdersBoardPage())),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Pretes 1'), findsOneWidget);
      expect(find.text('Livraison 0'), findsOneWidget);
      expect(find.text('Service'), findsOneWidget);
      expect(find.text('Commande #2'), findsOneWidget);
      expect(find.text('Commande #1'), findsNothing);
    },
  );

  testWidgets(
    'orders board mobile view starts on ready service tab',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._establishmentOverrides(),
            activeOrdersProvider.overrideWith(
              (ref) async => [
                const OrderSummary(
                  id: 3,
                  orderType: 'delivery',
                  status: 'out_for_delivery',
                  paymentStatus: 'paid',
                  source: 'customer',
                  total: 18,
                  deliveryFee: 4,
                ),
                const OrderSummary(
                  id: 2,
                  orderType: 'pickup',
                  status: 'ready',
                  paymentStatus: 'paid',
                  source: 'customer',
                  total: 9.0,
                  deliveryFee: 0,
                ),
              ],
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: OrdersBoardPage())),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Pretes 1'), findsOneWidget);
      expect(find.text('Livraison 1'), findsWidgets);
      expect(find.text('Commande #2'), findsOneWidget);
      expect(find.text('Commande #3'), findsNothing);
    },
  );
}

List<Override> _establishmentOverrides() {
  return [
    availableEstablishmentsProvider.overrideWith(
      (ref) async => const [
        Establishment(
          id: 1,
          name: 'KOD MOME',
          timezone: 'Europe/Paris',
          isActive: true,
        ),
      ],
    ),
  ];
}
