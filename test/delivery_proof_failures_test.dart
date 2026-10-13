import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/features/delivery/data/delivery_repository.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/delivery/presentation/dispatch_page.dart';
import 'package:app_admin_staff/features/delivery/presentation/failures_section.dart';
import 'package:app_admin_staff/features/driver/presentation/driver_deliveries_page.dart';
import 'package:app_admin_staff/features/driver/presentation/driver_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDispatchRepository extends Mock implements DispatchRepository {}

class _MockDeliveryRepository extends Mock implements DeliveryRepository {}

DriverDelivery _delivery(
  int id, {
  String phase = 'arrived',
  double due = 0,
  bool proof = false,
  bool locked = false,
  DateTime? arrivedAt,
  int minWait = 5,
  int minCalls = 1,
}) => DriverDelivery(
  id: id,
  orderId: id + 1000,
  status: phase == 'arrived' ? 'arrived' : 'out_for_delivery',
  phase: phase,
  total: 25,
  amountDue: due,
  paymentStatus: due > 0 ? 'guaranteed' : 'paid',
  customerPhone: '0698765432',
  deliveryAddress: '1 rue de la Paix',
  proofRequired: proof,
  codeLocked: locked,
  arrivedAt: arrivedAt,
  failureMinWaitMinutes: minWait,
  failureMinCallAttempts: minCalls,
);

DeliveryFailure _failure(
  int id, {
  String fault = 'customer',
  String payment = 'guaranteed',
  String reason = 'wrong_address',
}) => DeliveryFailure(
  id: id,
  orderId: id + 500,
  reason: reason,
  reasonLabel: 'Adresse introuvable ou fausse',
  fault: fault,
  status: 'pending',
  total: 25,
  paymentStatus: payment,
  driverName: 'Marc',
  deliveryAddress: '1 rue de la Paix',
  callAttempts: 2,
);

void main() {
  group('regles de declaration d\'echec (miroir de l\'API)', () {
    final now = DateTime(2026, 10, 2, 12, 0);

    String? block(
      DriverDelivery delivery,
      String reason, {
      int calls = 1,
      String note = '',
    }) => failureBlockReason(
      delivery,
      reason,
      callAttempts: calls,
      now: now,
      note: note,
    );

    test('absent ou injoignable : arrivee signalee d\'abord', () {
      final enRoute = _delivery(1, phase: 'en_route');
      expect(block(enRoute, 'customer_absent'), contains('arrivee'));
      expect(block(enRoute, 'customer_unreachable'), contains('arrivee'));
    });

    test(
      'attente minimale depuis l\'arrivee, arrondie a la minute superieure',
      () {
        final arrivedRecently = _delivery(
          1,
          arrivedAt: now.subtract(const Duration(minutes: 2, seconds: 10)),
        );
        expect(block(arrivedRecently, 'customer_absent'), contains('3 min'));
        final waitedEnough = _delivery(
          1,
          arrivedAt: now.subtract(const Duration(minutes: 5)),
        );
        expect(block(waitedEnough, 'customer_absent'), isNull);
      },
    );

    test('appels minimaux exiges', () {
      final delivery = _delivery(
        1,
        arrivedAt: now.subtract(const Duration(minutes: 10)),
        minCalls: 2,
      );
      expect(block(delivery, 'customer_absent', calls: 1), contains('2 fois'));
      expect(block(delivery, 'customer_absent', calls: 2), isNull);
    });

    test('adresse, refus et probleme de commande : pas d\'attente', () {
      final enRoute = _delivery(1, phase: 'en_route');
      for (final reason in [
        'wrong_address',
        'customer_refused',
        'order_problem',
      ]) {
        expect(block(enRoute, reason, calls: 0), isNull, reason: reason);
      }
    });

    test('« autre » exige une precision', () {
      final enRoute = _delivery(1, phase: 'en_route');
      expect(block(enRoute, 'other'), isNotNull);
      expect(block(enRoute, 'other', note: 'Portail ferme'), isNull);
    });

    test('code de remise : exactement 4 chiffres', () {
      expect(isValidDeliveryCode('1234'), isTrue);
      expect(isValidDeliveryCode(' 1234 '), isTrue);
      for (final bad in ['', '123', '12345', 'abcd', '12a4']) {
        expect(isValidDeliveryCode(bad), isFalse, reason: bad);
      }
    });
  });

  group('traitement d\'un echec', () {
    String? check(
      DeliveryFailure f,
      String? action, {
      String amount = '',
      String note = '',
    }) => validateResolution(f, action: action, amountText: amount, note: note);

    test('aucune action choisie', () {
      expect(check(_failure(1), null), isNotNull);
    });

    test('rembourser est toujours possible', () {
      expect(check(_failure(1, fault: 'restaurant'), 'refund'), isNull);
    });

    test(
      'retenir : faute du client, montant dans le total, motif obligatoire',
      () {
        expect(
          check(_failure(1), 'retain', amount: '5', note: 'Client absent'),
          isNull,
        );
        expect(
          check(_failure(1), 'retain', note: 'Client absent'),
          contains('Montant'),
        );
        expect(
          check(_failure(1), 'retain', amount: '26', note: 'x'),
          contains('depasse'),
        );
        expect(check(_failure(1), 'retain', amount: '5'), contains('motif'));
        expect(
          check(
            _failure(1, fault: 'restaurant'),
            'retain',
            amount: '5',
            note: 'Frais',
          ),
          contains('restaurant'),
        );
      },
    );

    test('relivrer : seulement une commande encore reglee', () {
      expect(check(_failure(1, payment: 'paid'), 'redeliver'), isNull);
      expect(check(_failure(1, payment: 'guaranteed'), 'redeliver'), isNull);
      expect(
        check(_failure(1, payment: 'guarantee_released'), 'redeliver'),
        isNotNull,
      );
    });
  });

  group('modeles', () {
    test('un echec se lit depuis l\'API', () {
      final failure = DeliveryFailure.fromJson({
        'id': 3,
        'order_id': 9,
        'reason': 'customer_absent',
        'reason_label': 'Client absent',
        'fault': 'customer',
        'status': 'pending',
        'total': 25,
        'payment_status': 'guaranteed',
        'waited_seconds': 400,
        'call_attempts': 2,
      });
      expect(failure.isPending, isTrue);
      expect(failure.customerFault, isTrue);
      expect(failure.canRedeliver, isTrue);
      expect(failure.waitedSeconds, 400);
    });

    test('la livraison du livreur porte les regles de preuve et d\'echec', () {
      final delivery = DriverDelivery.fromJson({
        'id': 1,
        'order_id': 2,
        'status': 'arrived',
        'phase': 'arrived',
        'total': 25,
        'amount_due': 0,
        'payment_status': 'paid',
        'proof_required': true,
        'code_locked': true,
        'arrived_at': '2026-10-02T10:00:00Z',
        'failure_min_wait_minutes': 7,
        'failure_min_call_attempts': 2,
      });
      expect(delivery.proofRequired, isTrue);
      expect(delivery.codeLocked, isTrue);
      expect(delivery.arrivedAt, isNotNull);
      expect(delivery.failureMinWaitMinutes, 7);
      expect(delivery.failureMinCallAttempts, 2);
    });

    test(
      'les reglages lisent la preuve et les regles d\'echec (valeurs par defaut sures)',
      () {
        final defaults = DeliverySettings.fromJson({
          'internal_enabled': true,
          'version': 1,
        });
        expect(defaults.deliveryProofRequired, isFalse);
        expect(defaults.failureMinWaitMinutes, 5);
        expect(defaults.failureMinCallAttempts, 1);
      },
    );
  });

  group('ecran livreur : preuve et echec', () {
    late _MockDispatchRepository repo;
    late List<DriverDelivery> deliveries;

    setUp(() {
      repo = _MockDispatchRepository();
      deliveries = [];
      when(() => repo.driverDeliveries()).thenAnswer((_) async => deliveries);
      when(
        () => repo.delivered(
          any(),
          cashReceived: any(named: 'cashReceived'),
          code: any(named: 'code'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => repo.failed(
          any(),
          reason: any(named: 'reason'),
          note: any(named: 'note'),
          callAttempts: any(named: 'callAttempts'),
        ),
      ).thenAnswer((_) async {});
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dispatchRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(
            home: Scaffold(body: DriverDeliveriesPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('le code est exige et doit avoir 4 chiffres', (tester) async {
      deliveries = [_delivery(1, proof: true)];
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('delivered-1')));
      await tester.pumpAndSettle();
      FilledButton confirm() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('confirm-delivered')),
      );
      expect(confirm().onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('delivery-code')), '12');
      await tester.pump();
      expect(confirm().onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('delivery-code')),
        '1234',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-delivered')));
      await tester.pumpAndSettle();

      verify(
        () => repo.delivered(1, cashReceived: null, code: '1234'),
      ).called(1);
    });

    testWidgets('code et especes ensemble pour une empreinte a regler', (
      tester,
    ) async {
      deliveries = [_delivery(1, proof: true, due: 25)];
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('delivered-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('delivery-code')),
        '4821',
      );
      await tester.enterText(find.byKey(const ValueKey('cash-received')), '30');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-delivered')));
      await tester.pumpAndSettle();

      verify(() => repo.delivered(1, cashReceived: 30, code: '4821')).called(1);
    });

    testWidgets('sans preuve exigee, aucun champ de code', (tester) async {
      deliveries = [_delivery(1)];
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('delivered-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('delivery-code')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('confirm-delivered')));
      await tester.pumpAndSettle();

      verify(() => repo.delivered(1, cashReceived: null, code: null)).called(1);
    });

    testWidgets('livraison verrouillee : message, aucune saisie, aucun appel', (
      tester,
    ) async {
      deliveries = [_delivery(1, proof: true, locked: true)];
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('delivered-1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Trop de codes incorrects'), findsOneWidget);
      expect(find.byKey(const ValueKey('delivery-code')), findsNothing);
      verifyNever(
        () => repo.delivered(
          any(),
          cashReceived: any(named: 'cashReceived'),
          code: any(named: 'code'),
        ),
      );
    });

    testWidgets('un code refuse par l\'API est affiche au livreur', (
      tester,
    ) async {
      when(
        () => repo.delivered(
          any(),
          cashReceived: any(named: 'cashReceived'),
          code: any(named: 'code'),
        ),
      ).thenThrow(
        const ApiError(
          message: 'Code incorrect. 4 essai(s) restant(s).',
          statusCode: 422,
        ),
      );
      deliveries = [_delivery(1, proof: true)];
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('delivered-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('delivery-code')),
        '0000',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-delivered')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Code incorrect'), findsOneWidget);
    });

    testWidgets('echec « adresse fausse » : declare avec le motif', (
      tester,
    ) async {
      deliveries = [_delivery(1, phase: 'en_route')];
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('failed-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('failure-wrong_address')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-failure')));
      await tester.pumpAndSettle();

      verify(
        () =>
            repo.failed(1, reason: 'wrong_address', note: '', callAttempts: 0),
      ).called(1);
    });

    testWidgets(
      'echec « client absent » bloque tant que l\'attente et les appels manquent',
      (tester) async {
        deliveries = [
          _delivery(
            1,
            arrivedAt: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
        ];
        await pump(tester);

        await tester.tap(find.byKey(const ValueKey('failed-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('failure-customer_absent')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('failure-block')), findsOneWidget);
        expect(find.textContaining('Attendez encore'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('confirm-failure')),
              )
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets('« autre » demande une precision', (tester) async {
      deliveries = [_delivery(1, phase: 'en_route')];
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('failed-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('failure-other')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirm-failure')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('failure-note')),
        'Portail ferme',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-failure')));
      await tester.pumpAndSettle();

      verify(
        () => repo.failed(
          1,
          reason: 'other',
          note: 'Portail ferme',
          callAttempts: 0,
        ),
      ).called(1);
    });

    testWidgets('le bouton d\'echec n\'existe pas avant le depart', (
      tester,
    ) async {
      deliveries = [_delivery(1, phase: 'ready')];
      await pump(tester);

      expect(find.byKey(const ValueKey('failed-1')), findsNothing);
    });
  });

  group('dispatch : echecs, livraison sans code, reglages', () {
    late _MockDispatchRepository repo;
    late _MockDeliveryRepository deliveryRepo;
    late List<DeliveryFailure> pending;

    setUp(() {
      repo = _MockDispatchRepository();
      deliveryRepo = _MockDeliveryRepository();
      pending = [
        _failure(1),
        _failure(2, fault: 'restaurant', reason: 'order_problem'),
      ];
      when(
        () => repo.board(establishmentId: any(named: 'establishmentId')),
      ).thenAnswer(
        (_) async => const DispatchBoard(
          dispatchEnabled: true,
          unassigned: [],
          deliveries: [
            DispatchDelivery(
              id: 9,
              status: 'out_for_delivery',
              driverId: 2,
              driverName: 'Marc',
              order: DispatchOrder(
                orderId: 22,
                status: 'ready',
                total: 25,
                paymentStatus: 'paid',
              ),
            ),
          ],
          drivers: [],
        ),
      );
      when(
        () => repo.failures(status: any(named: 'status')),
      ).thenAnswer((_) async => pending);
      when(
        () => repo.resolveFailure(
          any(),
          action: any(named: 'action'),
          amountCents: any(named: 'amountCents'),
          note: any(named: 'note'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => repo.deliverWithoutCode(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => deliveryRepo.updateProofSettings(
          internalEnabled: any(named: 'internalEnabled'),
          expectedVersion: any(named: 'expectedVersion'),
          proofRequired: any(named: 'proofRequired'),
          failureMinWaitMinutes: any(named: 'failureMinWaitMinutes'),
          failureMinCallAttempts: any(named: 'failureMinCallAttempts'),
        ),
      ).thenAnswer(
        (_) async => const DeliverySettings(internalEnabled: true, version: 4),
      );
    });

    Future<void> pump(WidgetTester tester, {String role = 'admin'}) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dispatchRepositoryProvider.overrideWithValue(repo),
            deliveryRepositoryProvider.overrideWithValue(deliveryRepo),
            deliverySettingsProvider.overrideWith(
              (ref) async => const DeliverySettings(
                internalEnabled: true,
                version: 3,
                driverDispatchEnabled: true,
              ),
            ),
            currentPermissionSetProvider.overrideWithValue(
              PermissionSet(role: role, permissions: const {'*'}),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: DispatchPage())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('les echecs a traiter sont listes, avec la faute', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Echecs a traiter (2)'), findsOneWidget);
      expect(find.text('Faute du client'), findsOneWidget);
      expect(find.text('Faute du restaurant'), findsOneWidget);
    });

    testWidgets('le personnel les voit mais ne peut pas les traiter', (
      tester,
    ) async {
      await pump(tester, role: 'staff');

      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('resolve-failure-1')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('rembourser', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('resolve-failure-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('resolve-refund')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-resolve')));
      await tester.pumpAndSettle();

      verify(
        () => repo.resolveFailure(
          1,
          action: 'refund',
          amountCents: null,
          note: '',
        ),
      ).called(1);
    });

    testWidgets('retenir : montant en centimes et motif obligatoires', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('resolve-failure-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('resolve-retain')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirm-resolve')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('retain-amount')),
        '5,50',
      );
      await tester.enterText(
        find.byKey(const ValueKey('resolve-note')),
        'Client absent 3 appels',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-resolve')));
      await tester.pumpAndSettle();

      verify(
        () => repo.resolveFailure(
          1,
          action: 'retain',
          amountCents: 550,
          note: 'Client absent 3 appels',
        ),
      ).called(1);
    });

    testWidgets('faute du restaurant : impossible de retenir des frais', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('resolve-failure-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('resolve-retain')));
      await tester.pumpAndSettle();

      expect(find.text('Impossible : faute du restaurant'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirm-resolve')))
            .onPressed,
        isNull,
      );
      verifyNever(
        () => repo.resolveFailure(
          any(),
          action: any(named: 'action'),
          amountCents: any(named: 'amountCents'),
          note: any(named: 'note'),
        ),
      );
    });

    testWidgets('une erreur de l\'API est affichee dans la boite', (
      tester,
    ) async {
      when(
        () => repo.resolveFailure(
          any(),
          action: any(named: 'action'),
          amountCents: any(named: 'amountCents'),
          note: any(named: 'note'),
        ),
      ).thenThrow(
        const ApiError(
          message: 'Cet echec a deja ete traite.',
          statusCode: 409,
        ),
      );
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('resolve-failure-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('resolve-refund')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-resolve')));
      await tester.pumpAndSettle();

      expect(find.text('Cet echec a deja ete traite.'), findsOneWidget);
      expect(find.byKey(const ValueKey('confirm-resolve')), findsOneWidget);
    });

    testWidgets('livrer sans code : administrateur, motif obligatoire', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('no-code-22')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirm-no-code')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('no-code-reason')),
        'Code perdu, client identifie',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-no-code')));
      await tester.pumpAndSettle();

      verify(
        () => repo.deliverWithoutCode(22, 'Code perdu, client identifie'),
      ).called(1);
    });

    testWidgets('le personnel n\'a pas le bouton « livrer sans code »', (
      tester,
    ) async {
      await pump(tester, role: 'staff');

      expect(find.byKey(const ValueKey('no-code-22')), findsNothing);
    });

    testWidgets('l\'administrateur active la preuve par code', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('proof-required-switch')));
      await tester.pumpAndSettle();

      verify(
        () => deliveryRepo.updateProofSettings(
          internalEnabled: true,
          expectedVersion: 3,
          proofRequired: true,
          failureMinWaitMinutes: null,
          failureMinCallAttempts: null,
        ),
      ).called(1);
    });

    testWidgets('le personnel ne change ni la preuve ni les regles', (
      tester,
    ) async {
      await pump(tester, role: 'staff');

      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('proof-required-switch')),
            )
            .onChanged,
        isNull,
      );
    });
  });
}
