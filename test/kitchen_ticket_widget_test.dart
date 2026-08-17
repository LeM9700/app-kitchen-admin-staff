import 'package:flutter_test/flutter_test.dart';

import 'kitchen_board_test_support.dart';

void main() {
  final confirmedAt = DateTime.now().subtract(const Duration(minutes: 7));

  final cases = <String, String>{
    'pending': 'EN ATTENTE DE CONFIRMATION',
    'confirmed': 'À COMMENCER',
    'preparing': 'EN PRÉPARATION',
    'ready': 'PRÊTE',
  };

  for (final entry in cases.entries) {
    testWidgets('${entry.key} affiche ${entry.value}', (tester) async {
      addTearDown(tester.view.reset);

      await pumpKitchenTicket(
        tester,
        testKitchenTicket(
          status: entry.key,
          confirmedAt: entry.key == 'pending' ? null : confirmedAt,
        ),
      );

      expect(find.text(entry.value), findsOneWidget);
    });
  }

  testWidgets('produit, quantité, variant, extras et table sont visibles',
      (tester) async {
    addTearDown(tester.view.reset);

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'preparing',
        confirmedAt: confirmedAt,
        tableNumber: '08',
        items: [
          testKitchenItem(
            quantity: 2,
            productName: 'Burger classic',
            variantName: 'Double',
            extras: [
              testKitchenExtra(name: 'Cheddar'),
              testKitchenExtra(name: 'Bacon'),
            ],
          ),
        ],
      ),
    );

    expect(find.text('2 × BURGER CLASSIC'), findsOneWidget);
    expect(find.text('DOUBLE'), findsOneWidget);
    expect(find.text('+ Cheddar'), findsOneWidget);
    expect(find.text('+ Bacon'), findsOneWidget);
    expect(find.text('TABLE 08'), findsOneWidget);
  });

  testWidgets('les informations prix et client ne sont pas rendues',
      (tester) async {
    addTearDown(tester.view.reset);

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'preparing',
        confirmedAt: confirmedAt,
        customerName: 'Alice Martin',
        customerEmail: 'alice@example.com',
        customerPhone: '0600000000',
        total: 999.99,
        items: [
          testKitchenItem(
            productName: 'Regina',
            unitPrice: 999.99,
            total: 999.99,
          ),
        ],
      ),
    );

    expect(find.textContaining('999'), findsNothing);
    expect(find.textContaining('€'), findsNothing);
    expect(find.textContaining('Alice'), findsNothing);
    expect(find.textContaining('alice@example.com'), findsNothing);
  });

  testWidgets('un extra avec quantité affiche une formulation concise',
      (tester) async {
    addTearDown(tester.view.reset);

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'preparing',
        confirmedAt: confirmedAt,
        items: [
          testKitchenItem(
            productName: 'Frites',
            extras: [
              testKitchenExtra(name: 'Cheddar', quantity: 2),
            ],
          ),
        ],
      ),
    );

    expect(find.text('+ 2 × Cheddar'), findsOneWidget);
  });

  testWidgets('le timer affiche un placeholder sans confirmation',
      (tester) async {
    addTearDown(tester.view.reset);

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(status: 'pending', confirmedAt: null),
    );

    expect(find.text('--:--'), findsOneWidget);
  });
}
