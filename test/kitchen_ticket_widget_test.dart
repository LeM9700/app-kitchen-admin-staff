import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_items.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter/material.dart';
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

  testWidgets('commande normale non compact sans scroll interne',
      (tester) async {
    addTearDown(tester.view.reset);

    await _pumpKitchenTicketItems(
      tester,
      items: [
        testKitchenItem(productName: 'Margherita'),
        testKitchenItem(id: 1002, productName: 'Frites'),
      ],
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.textContaining('MARGHERITA'), findsOneWidget);
    expect(find.textContaining('FRITES'), findsOneWidget);
  });

  testWidgets('commande non compact de 6 produits passe en 2 colonnes',
      (tester) async {
    addTearDown(tester.view.reset);
    final items = _sixProductOrderItems();

    await _pumpKitchenTicketItems(tester, items: items);

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(Row), findsOneWidget);
    expect(find.text('COMMANDE VOLUMINEUSE'), findsNothing);
    for (final item in items) {
      expect(
        find.textContaining(item.productName!.toUpperCase()),
        findsOneWidget,
      );
      expect(find.text(item.variantName!.toUpperCase()), findsOneWidget);
      for (final extra in item.extras) {
        expect(find.text('+ ${extra.name}'), findsOneWidget);
      }
    }
  });

  testWidgets('commande oversized conserve tous les produits et signale',
      (tester) async {
    addTearDown(tester.view.reset);
    final items = _oversizedOrderItems();

    await _pumpKitchenTicketItems(
      tester,
      items: items,
      size: const Size(820, 1500),
    );

    expect(isOversizedKitchenOrder(items), isTrue);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('COMMANDE VOLUMINEUSE'), findsOneWidget);
    for (final item in items) {
      expect(
        find.textContaining(item.productName!.toUpperCase()),
        findsOneWidget,
      );
    }
  });

  testWidgets('compact autorise le scroll vertical en fallback',
      (tester) async {
    addTearDown(tester.view.reset);

    await _pumpKitchenTicketItems(
      tester,
      items: _oversizedOrderItems(),
      compact: true,
      size: const Size(390, 640),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}

Future<void> _pumpKitchenTicketItems(
  WidgetTester tester, {
  required List<OrderItem> items,
  bool compact = false,
  Size size = const Size(820, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox.expand(
          child: KitchenTicketItems(items: items, compact: compact),
        ),
      ),
    ),
  );
  await tester.pump();
}

List<OrderItem> _sixProductOrderItems() {
  return [
    for (var index = 1; index <= 6; index++)
      testKitchenItem(
        id: 2000 + index,
        productName: 'Produit $index',
        variantName: 'Variant $index',
        extras: [
          testKitchenExtra(id: 3000 + index, name: 'Extra $index'),
        ],
      ),
  ];
}

List<OrderItem> _oversizedOrderItems() {
  return [
    for (var index = 1; index <= 7; index++)
      testKitchenItem(
        id: 4000 + index,
        productName: 'Grande commande $index',
        variantName: 'Format $index',
        extras: [
          testKitchenExtra(id: 5000 + index, name: 'Cheddar $index'),
          testKitchenExtra(id: 6000 + index, name: 'Bacon $index'),
        ],
      ),
  ];
}
