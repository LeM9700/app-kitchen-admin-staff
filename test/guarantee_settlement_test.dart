import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/design_system/states/order_status_ui.dart';
import 'package:app_admin_staff/features/checkout/application/checkout_validation.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:app_admin_staff/features/payments/presentation/guarantee_settlement_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPaymentsRepository extends Mock implements PaymentsRepository {}

CheckoutValidationInput _input({
  String orderType = 'delivery',
  String paymentMethod = 'payment_link',
  String phone = '06 12 34 56 78',
  String email = '',
}) {
  return CheckoutValidationInput(
    hasItems: true,
    orderType: orderType,
    paymentMethod: paymentMethod,
    deliveryAddress: orderType == 'delivery' ? '1 rue de la Paix' : '',
    externalReference: '',
    loyaltyCustomerId: null,
    loyaltyRewardId: null,
    loyaltyOralConfirmed: false,
    total: 24,
    amountReceived: null,
    isOnline: true,
    isRestaurantOpen: true,
    customerPhone: phone,
    customerEmail: email,
    deliveryZoneId: orderType == 'delivery' ? 3 : null,
  );
}

void main() {
  group('caisse : lien de paiement et livraison', () {
    test('une livraison ne peut pas etre encaissee en especes au comptoir', () {
      final result = validateCheckout(_input(paymentMethod: 'cash'));
      expect(result.isValid, isFalse);
      expect(result.message, contains('lien de paiement'));
    });

    test('une livraison avec lien (empreinte) est valide', () {
      expect(validateCheckout(_input()).isValid, isTrue);
    });

    test('les especes restent possibles pour un retrait', () {
      expect(
        validateCheckout(
          _input(orderType: 'pickup', paymentMethod: 'cash', phone: ''),
        ).isValid,
        isTrue,
      );
    });

    test('le lien exige un telephone ou un email pour etre envoye', () {
      final none = validateCheckout(
        _input(orderType: 'pickup', phone: '', email: ''),
      );
      expect(none.isValid, isFalse);
      expect(none.message, contains('Telephone ou email'));
      expect(
        validateCheckout(
          _input(orderType: 'pickup', phone: '', email: 'a@b.fr'),
        ).isValid,
        isTrue,
      );
    });

    test('pas de lien de paiement pour une commande sur place', () {
      final result = validateCheckout(_input(orderType: 'dine_in'));
      expect(result.isValid, isFalse);
      expect(result.message, contains('sur place'));
    });
  });

  group('modeles', () {
    test('une commande avec lien n\'a pas encore de paiement', () {
      final result = ManualOrderResult.fromJson({
        'order': {'id': 5, 'order_type': 'delivery', 'total': 24},
        'payment': null,
        'receipt': {'order_id': 5},
        'payment_link': {
          'url': 'https://pay.example/x',
          'mode': 'guarantee',
          'payment_id': 9,
          'sent_by_sms': true,
        },
      });
      expect(result.payment, isNull);
      expect(result.awaitsCustomerPayment, isTrue);
      expect(result.paymentLink!.isGuarantee, isTrue);
      expect(result.paymentLink!.sentBySms, isTrue);
      expect(result.paymentLink!.sentByEmail, isFalse);
      expect(result.paymentLinkError, isNull);
    });

    test('une commande encaissee a un paiement et pas de lien', () {
      final result = ManualOrderResult.fromJson({
        'order': {'id': 6, 'order_type': 'pickup', 'total': 12},
        'payment': {
          'id': 1,
          'order_id': 6,
          'provider': 'cash',
          'amount': 12,
          'status': 'paid',
        },
        'receipt': {},
      });
      expect(result.awaitsCustomerPayment, isFalse);
      expect(result.paymentLink, isNull);
    });

    test('l\'erreur de creation du lien est conservee', () {
      final result = ManualOrderResult.fromJson({
        'order': {'id': 7, 'order_type': 'delivery', 'total': 24},
        'payment': null,
        'receipt': {},
        'payment_link_error': 'STRIPE_PAYMENT_FAILED',
      });
      expect(result.paymentLink, isNull);
      expect(result.paymentLinkError, 'STRIPE_PAYMENT_FAILED');
    });

    test('un paiement d\'empreinte expose son but et le montant debite', () {
      final item = PaymentListItem.fromJson({
        'id': 1,
        'order_id': 2,
        'provider': 'stripe',
        'amount': 25,
        'status': 'paid',
        'purpose': 'guarantee',
        'captured_amount': 5,
      });
      expect(item.purpose, 'guarantee');
      expect(item.capturedAmount, 5);
      expect(
        PaymentListItem.fromJson({'id': 1, 'order_id': 2}).purpose,
        'sale',
      );
    });

    test('les statuts d\'empreinte ont un libelle dedie', () {
      expect(OrderStatusUi.from('guaranteed').label, 'Empreinte (a regler)');
      expect(OrderStatusUi.from('guarantee_released').label, contains('liberee'));
      expect(OrderStatusUi.from('guarantee_captured').label, contains('debitee'));
    });
  });

  group('validateSettlement', () {
    String? check(
      GuaranteeSettlement choice, {
      String amount = '',
      String reason = '',
    }) {
      return validateSettlement(
        choice: choice,
        total: 25,
        amountText: amount,
        reason: reason,
      );
    }

    test('parseSettlementAmount accepte la virgule et refuse le reste', () {
      expect(parseSettlementAmount('5,5'), 5.5);
      expect(parseSettlementAmount(' 12.30 '), 12.3);
      expect(parseSettlementAmount(''), isNull);
      expect(parseSettlementAmount('0'), isNull);
      expect(parseSettlementAmount('-3'), isNull);
      expect(parseSettlementAmount('abc'), isNull);
    });

    test('especes : le montant recu doit couvrir le total', () {
      expect(check(GuaranteeSettlement.cash), isNull);
      expect(check(GuaranteeSettlement.cash, amount: '30'), isNull);
      expect(check(GuaranteeSettlement.cash, amount: '10'), contains('inferieur'));
      expect(check(GuaranteeSettlement.cash, amount: 'x'), contains('invalide'));
    });

    test('frais : montant, plafond et motif obligatoires', () {
      expect(
        check(GuaranteeSettlement.fee, reason: 'Client absent'),
        contains('requis'),
      );
      expect(
        check(GuaranteeSettlement.fee, amount: '26', reason: 'Client absent'),
        contains('depasse'),
      );
      expect(check(GuaranteeSettlement.fee, amount: '5'), contains('motif'));
      expect(
        check(GuaranteeSettlement.fee, amount: '5', reason: 'Client absent'),
        isNull,
      );
    });

    test('liberer et debiter le total n\'ont pas de saisie', () {
      expect(check(GuaranteeSettlement.release), isNull);
      expect(check(GuaranteeSettlement.card), isNull);
    });
  });

  group('boite de reglement', () {
    late _MockPaymentsRepository repo;

    setUp(() {
      repo = _MockPaymentsRepository();
      when(() => repo.guaranteeCashCollected(any(), amountReceived: any(named: 'amountReceived')))
          .thenAnswer((_) async {});
      when(() => repo.releaseGuarantee(any(), reason: any(named: 'reason')))
          .thenAnswer((_) async {});
      when(
        () => repo.captureGuarantee(
          any(),
          amountCents: any(named: 'amountCents'),
          reason: any(named: 'reason'),
        ),
      ).thenAnswer((_) async {});
    });

    Future<ValueNotifier<bool?>> open(
      WidgetTester tester, {
      String role = 'admin',
    }) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final result = ValueNotifier<bool?>(null);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            paymentsRepositoryProvider.overrideWithValue(repo),
            currentPermissionSetProvider.overrideWithValue(
              PermissionSet(role: role, permissions: null),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result.value =
                    await showGuaranteeSettlementDialog(
                  context,
                  orderId: 12,
                  total: 25,
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      return result;
    }

    Finder confirm() => find.widgetWithText(FilledButton, 'Confirmer');

    testWidgets('rien n\'est envoye tant qu\'aucun choix n\'est fait',
        (tester) async {
      await open(tester);

      expect(tester.widget<FilledButton>(confirm()).onPressed, isNull);
    });

    testWidgets('especes : libere l\'empreinte et enregistre l\'encaissement',
        (tester) async {
      final result = await open(tester);

      await tester.tap(find.text('Especes encaissees'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '30');
      await tester.pump();
      await tester.tap(confirm());
      await tester.pumpAndSettle();

      verify(() => repo.guaranteeCashCollected(12, amountReceived: 30)).called(1);
      verifyNever(
        () => repo.captureGuarantee(
          any(),
          amountCents: any(named: 'amountCents'),
          reason: any(named: 'reason'),
        ),
      );
      expect(result.value, isTrue);
    });

    testWidgets('especes insuffisantes : confirmation bloquee', (tester) async {
      await open(tester);

      await tester.tap(find.text('Especes encaissees'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '10');
      await tester.pump();

      expect(find.textContaining('inferieur au total'), findsOneWidget);
      expect(tester.widget<FilledButton>(confirm()).onPressed, isNull);
    });

    testWidgets('frais d\'echec : montant en centimes et motif transmis',
        (tester) async {
      final result = await open(tester);

      await tester.tap(find.text('Debiter des frais (echec client)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '5,50');
      await tester.pump();
      await tester.tap(confirm());
      await tester.pumpAndSettle();

      verify(
        () => repo.captureGuarantee(
          12,
          amountCents: 550,
          reason: 'Client absent',
        ),
      ).called(1);
      expect(result.value, isTrue);
    });

    testWidgets('liberer sans debit', (tester) async {
      final result = await open(tester);

      await tester.tap(find.text('Liberer sans debit'));
      await tester.pumpAndSettle();
      await tester.tap(confirm());
      await tester.pumpAndSettle();

      verify(() => repo.releaseGuarantee(12, reason: 'released_by_staff'))
          .called(1);
      expect(result.value, isTrue);
    });

    testWidgets('le personnel ne peut pas debiter la carte', (tester) async {
      await open(tester, role: 'staff');

      await tester.tap(find.text('Debiter la carte (total)'));
      await tester.pumpAndSettle();
      expect(find.text('Reserve a l\'administrateur'), findsNWidgets(2));
      expect(tester.widget<FilledButton>(confirm()).onPressed, isNull);

      await tester.tap(find.text('Debiter des frais (echec client)'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm()).onPressed, isNull);
      verifyNever(
        () => repo.captureGuarantee(
          any(),
          amountCents: any(named: 'amountCents'),
          reason: any(named: 'reason'),
        ),
      );
    });

    testWidgets('une erreur de l\'API est affichee et la boite reste ouverte',
        (tester) async {
      when(() => repo.releaseGuarantee(any(), reason: any(named: 'reason')))
          .thenThrow(
        const ApiError(
          message: 'Aucune empreinte active pour cette commande.',
          statusCode: 409,
        ),
      );
      final result = await open(tester);

      await tester.tap(find.text('Liberer sans debit'));
      await tester.pumpAndSettle();
      await tester.tap(confirm());
      await tester.pumpAndSettle();

      expect(
        find.text('Aucune empreinte active pour cette commande.'),
        findsOneWidget,
      );
      expect(find.text('Confirmer'), findsOneWidget);
      expect(result.value, isNull);
    });
  });
}
