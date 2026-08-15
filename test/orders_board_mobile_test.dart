import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/orders/presentation/orders_board_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'orders board renders the mobile status dropdown at narrow widths',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeOrdersProvider.overrideWith(
              (ref) async => [
                const OrderSummary(
                  id: 1,
                  orderType: 'delivery',
                  status: 'pending',
                  paymentStatus: 'pending',
                  source: 'customer',
                  total: 12.5,
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

      // The mobile branch renders a status dropdown instead of the
      // desktop horizontal multi-column board.
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('Commandes actives'), findsOneWidget);
    },
  );

  testWidgets(
    'orders board mobile view starts on the first non-empty status',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeOrdersProvider.overrideWith(
              (ref) async => [
                const OrderSummary(
                  id: 2,
                  orderType: 'delivery',
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

      // The mobile board starts on the first status with work to show.
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
    },
  );
}
