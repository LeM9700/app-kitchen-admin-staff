import 'package:app_admin_staff/features/kitchen/application/kitchen_actions_controller.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_hold_to_reopen_action.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_items.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_header.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_board_test_support.dart';

void main() {
  final confirmedAt = DateTime.now().subtract(const Duration(minutes: 7));
  const touchKitchenProfile = KitchenScreenProfile(
    mode: KitchenScreenMode.kitchen,
    station: 'kitchen',
    interactionMode: KitchenInteractionMode.touch,
  );

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

  testWidgets('late affiche bordure danger et timer danger', (tester) async {
    addTearDown(tester.view.reset);
    final confirmedAt = DateTime.now().subtract(const Duration(minutes: 16));

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(status: 'preparing', confirmedAt: confirmedAt),
      size: const Size(720, 520),
    );

    final ticketMaterial = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(KitchenTicket),
            matching: find.byType(Material),
          )
          .last,
    );
    final shape = ticketMaterial.shape! as RoundedRectangleBorder;
    expect(shape.side.color, AppColors.danger);
    expect(shape.side.width, 2);

    final timerText = tester.widget<Text>(
      find.descendant(
        of: find.byType(KitchenPreparationTimer),
        matching: find.byType(Text),
      ),
    );
    expect(timerText.style?.color, AppColors.danger);
  });

  testWidgets('normal conserve les styles standards', (tester) async {
    addTearDown(tester.view.reset);
    final confirmedAt = DateTime.now().subtract(const Duration(minutes: 14));

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(status: 'preparing', confirmedAt: confirmedAt),
      size: const Size(720, 520),
    );

    final ticketMaterial = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(KitchenTicket),
            matching: find.byType(Material),
          )
          .last,
    );
    final shape = ticketMaterial.shape! as RoundedRectangleBorder;
    expect(shape.side.color, isNot(AppColors.danger));
  });

  testWidgets('interactionMode wall masque COMMENCER et PRETE interactifs',
      (tester) async {
    addTearDown(tester.view.reset);

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'confirmed',
        confirmedAt: confirmedAt,
      ),
    );

    expect(find.text('COMMENCER'), findsNothing);
    expect(find.text('PRÊTE'), findsNothing);
  });

  testWidgets('interactionMode touch + confirmed affiche COMMENCER',
      (tester) async {
    addTearDown(tester.view.reset);

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'confirmed',
        confirmedAt: confirmedAt,
        profile: touchKitchenProfile,
      ),
      profile: touchKitchenProfile,
    );

    expect(find.text('COMMENCER'), findsOneWidget);
  });

  testWidgets('interactionMode touch + preparing affiche PRETE',
      (tester) async {
    addTearDown(tester.view.reset);

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'preparing',
        confirmedAt: confirmedAt,
        profile: touchKitchenProfile,
      ),
      profile: touchKitchenProfile,
    );

    expect(find.text('PRÊTE'), findsOneWidget);
  });

  testWidgets('stationReady affiche POSTE PRET', (tester) async {
    addTearDown(tester.view.reset);

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'preparing',
        confirmedAt: confirmedAt,
        items: [
          testKitchenItem(preparationStatus: 'ready'),
          testKitchenItem(
            id: 1002,
            productName: 'Coca',
            preparationStatus: 'preparing',
            preparationStation: 'counter',
          ),
        ],
        profile: touchKitchenProfile,
      ),
      profile: touchKitchenProfile,
    );

    expect(find.text('✓ POSTE PRÊT'), findsOneWidget);
  });

  testWidgets('ready affiche un etat final PRETE', (tester) async {
    addTearDown(tester.view.reset);

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'ready',
        confirmedAt: confirmedAt,
        items: [
          testKitchenItem(preparationStatus: 'ready'),
        ],
        profile: touchKitchenProfile,
      ),
      profile: touchKitchenProfile,
    );

    expect(find.text('✓ PRÊTE'), findsOneWidget);
  });

  testWidgets('poste pret en touch affiche le maintien 2 secondes',
      (tester) async {
    addTearDown(tester.view.reset);

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'preparing',
        confirmedAt: confirmedAt,
        items: [testKitchenItem(preparationStatus: 'ready')],
        profile: touchKitchenProfile,
      ),
      profile: touchKitchenProfile,
    );

    expect(find.byType(KitchenHoldToReopenAction), findsOneWidget);
    expect(
      find.text('MAINTENIR 2 S POUR REPASSER EN PRÉPARATION'),
      findsOneWidget,
    );
  });

  testWidgets('maintien relache avant 2s n appelle pas la mutation',
      (tester) async {
    addTearDown(tester.view.reset);
    var called = false;

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'preparing',
        confirmedAt: confirmedAt,
        items: [testKitchenItem(preparationStatus: 'ready')],
        profile: touchKitchenProfile,
      ),
      profile: touchKitchenProfile,
      onReopen: () => called = true,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(KitchenHoldToReopenAction)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 1));
    expect(called, isFalse);

    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    expect(called, isFalse);
  });

  testWidgets('maintien 2 secondes declenche reopenStation une seule fois',
      (tester) async {
    addTearDown(tester.view.reset);
    var callCount = 0;

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'preparing',
        confirmedAt: confirmedAt,
        items: [testKitchenItem(preparationStatus: 'ready')],
        profile: touchKitchenProfile,
      ),
      profile: touchKitchenProfile,
      onReopen: () => callCount++,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(KitchenHoldToReopenAction)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester
        .pump(kitchenReopenHoldDuration + const Duration(milliseconds: 50));

    expect(callCount, 1);

    // Maintenir 1s de plus (au-dela des 2s) ne redeclenche pas l'action.
    await tester.pump(const Duration(seconds: 1));
    expect(callCount, 1);

    await gesture.up();
    await tester.pump();
    expect(callCount, 1);
  });

  testWidgets('busy empeche le declenchement du maintien', (tester) async {
    addTearDown(tester.view.reset);
    var called = false;

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'preparing',
        confirmedAt: confirmedAt,
        items: [testKitchenItem(preparationStatus: 'ready')],
        profile: touchKitchenProfile,
      ),
      profile: touchKitchenProfile,
      actionsState: KitchenActionsState(
        busyKeys: {
          kitchenReopenStationActionKey(101, touchKitchenProfile),
        },
      ),
      onReopen: () => called = true,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(KitchenHoldToReopenAction)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester
        .pump(kitchenReopenHoldDuration + const Duration(milliseconds: 50));
    await gesture.up();

    expect(called, isFalse);
  });

  testWidgets('mode wall n affiche aucun geste de reouverture', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    const wallProfile = KitchenScreenProfile(
      mode: KitchenScreenMode.kitchen,
      station: 'kitchen',
    );

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'preparing',
        confirmedAt: confirmedAt,
        items: [testKitchenItem(preparationStatus: 'ready')],
        profile: wallProfile,
      ),
      profile: wallProfile,
    );

    expect(find.byType(KitchenHoldToReopenAction), findsNothing);
    expect(find.text('✓ POSTE PRÊT'), findsOneWidget);
  });

  testWidgets('mode service n affiche aucun geste de reouverture', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    const serviceProfile = KitchenScreenProfile(
      mode: KitchenScreenMode.service,
      station: 'service',
      interactionMode: KitchenInteractionMode.touch,
    );

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'preparing',
        confirmedAt: confirmedAt,
        items: [testKitchenItem(preparationStatus: 'ready')],
        profile: serviceProfile,
      ),
      profile: serviceProfile,
    );

    expect(find.byType(KitchenHoldToReopenAction), findsNothing);
    expect(find.text('✓ POSTE PRÊT'), findsOneWidget);
  });

  testWidgets('busy desactive le bouton et affiche un progress indicator',
      (tester) async {
    addTearDown(tester.view.reset);

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'confirmed',
        confirmedAt: confirmedAt,
        profile: touchKitchenProfile,
      ),
      profile: touchKitchenProfile,
      actionsState: KitchenActionsState(
        busyKeys: {kitchenStartOrderActionKey(101)},
      ),
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'COMMENCER'),
    );
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('tap COMMENCER appelle la mutation', (tester) async {
    addTearDown(tester.view.reset);
    var called = false;

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'confirmed',
        confirmedAt: confirmedAt,
        profile: touchKitchenProfile,
      ),
      profile: touchKitchenProfile,
      onStart: () => called = true,
    );

    await tester.tap(find.text('COMMENCER'));
    expect(called, isTrue);
  });

  testWidgets('tap PRETE appelle la mutation', (tester) async {
    addTearDown(tester.view.reset);
    var called = false;

    await pumpKitchenTicket(
      tester,
      testKitchenTicket(
        status: 'preparing',
        confirmedAt: confirmedAt,
        profile: touchKitchenProfile,
      ),
      profile: touchKitchenProfile,
      onReady: () => called = true,
    );

    await tester.tap(find.text('PRÊTE'));
    expect(called, isTrue);
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
