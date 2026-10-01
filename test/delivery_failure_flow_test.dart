import 'package:app_admin_staff/design_system/states/order_status_ui.dart';
import 'package:app_admin_staff/features/checkout/application/checkout_validation.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/orders/presentation/delivery_failure_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CheckoutValidationInput _input({
  String orderType = 'delivery',
  String address = '1 rue de la Paix',
  String phone = '06 12 34 56 78',
  int? zoneId = 3,
}) {
  return CheckoutValidationInput(
    hasItems: true,
    orderType: orderType,
    paymentMethod: 'cash',
    deliveryAddress: address,
    externalReference: '',
    loyaltyCustomerId: null,
    loyaltyRewardId: null,
    loyaltyOralConfirmed: false,
    total: 24,
    amountReceived: null,
    isOnline: true,
    isRestaurantOpen: true,
    customerPhone: phone,
    deliveryZoneId: zoneId,
  );
}

void main() {
  group('saisie de livraison au comptoir', () {
    test('une livraison complete est valide', () {
      expect(validateCheckout(_input()).isValid, isTrue);
    });

    test('refuse une livraison sans telephone', () {
      final result = validateCheckout(_input(phone: '  '));
      expect(result.isValid, isFalse);
      expect(result.message, contains('Telephone requis'));
    });

    test('refuse un telephone invalide', () {
      final result = validateCheckout(_input(phone: 'abc'));
      expect(result.isValid, isFalse);
      expect(result.message, 'Telephone invalide');
    });

    test('refuse une livraison sans zone (frais impossibles a calculer)', () {
      final result = validateCheckout(_input(zoneId: null));
      expect(result.isValid, isFalse);
      expect(result.message, contains('Zone de livraison requise'));
    });

    test('le retrait ne demande ni telephone ni zone', () {
      final result = validateCheckout(
        _input(orderType: 'pickup', address: '', phone: '', zoneId: null),
      );
      expect(result.isValid, isTrue);
    });

    test('isValidCustomerPhone suit la regle du serveur', () {
      expect(isValidCustomerPhone('+33 6 12 34 56 78'), isTrue);
      expect(isValidCustomerPhone('064/123-4567'), isFalse);
      expect(isValidCustomerPhone('12345'), isFalse);
      expect(isValidCustomerPhone(''), isFalse);
    });
  });

  group('ManualOrderDraft livraison', () {
    test('envoie zone et instructions, rognees', () {
      const draft = ManualOrderDraft(
        idempotencyKey: 'k',
        orderType: 'delivery',
        paymentMethod: 'cash',
        deliveryAddress: '1 rue de la Paix',
        deliveryZoneId: 3,
        deliveryInstructions: '  3e etage  ',
        customerPhone: '06 12 34 56 78',
        items: [ManualOrderLine(productId: 10, quantity: 1)],
      );
      final json = draft.toJson();
      expect(json['delivery_zone_id'], 3);
      expect(json['delivery_instructions'], '3e etage');
      expect((json['customer'] as Map)['phone'], '06 12 34 56 78');
    });

    test('le retrait ignore les instructions', () {
      const draft = ManualOrderDraft(
        idempotencyKey: 'k',
        orderType: 'pickup',
        paymentMethod: 'cash',
        deliveryInstructions: 'ignore',
        items: [ManualOrderLine(productId: 10, quantity: 1)],
      );
      expect(draft.toJson().containsKey('delivery_instructions'), isFalse);
    });
  });

  group('modeles et statuts', () {
    test('OrderSummary lit les instructions de livraison', () {
      final summary = OrderSummary.fromJson({
        'id': 5,
        'order_type': 'delivery',
        'status': 'delivery_failed',
        'delivery_instructions': 'Interphone 12',
      });
      expect(summary.deliveryInstructions, 'Interphone 12');
      expect(OrderSummary.fromJson({'id': 6}).deliveryInstructions, isNull);
    });

    test('delivery_failed et rejected ont un libelle dedie', () {
      expect(OrderStatusUi.from('delivery_failed').label, 'Livraison echouee');
      expect(OrderStatusUi.from('rejected').label, 'Refusee');
    });
  });

  group('boite de dialogue du motif', () {
    test('composeDeliveryFailureNote', () {
      expect(
        composeDeliveryFailureNote('Client absent', '  '),
        'Client absent',
      );
      expect(
        composeDeliveryFailureNote('Client absent', 'sonne 3 fois'),
        'Client absent - sonne 3 fois',
      );
    });

    Future<ValueNotifier<String?>> open(WidgetTester tester) async {
      final result = ValueNotifier<String?>('non-ferme');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result.value = await showDeliveryFailureDialog(context, 9),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('autre exige un detail avant de confirmer', (tester) async {
      final result = await open(tester);
      final confirm = find.byKey(const ValueKey('delivery-failure-confirm'));

      await tester
          .tap(find.byKey(const ValueKey('delivery-failure-reason-Autre')));
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('delivery-failure-details')),
        'Portail ferme',
      );
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(result.value, 'Autre - Portail ferme');
    });

    testWidgets('annuler ne renvoie aucun motif', (tester) async {
      final result = await open(tester);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(result.value, isNull);
    });
  });
}
