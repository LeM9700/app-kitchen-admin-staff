import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/delivery/presentation/establishment_dispatch_card.dart';
import 'package:app_admin_staff/features/driver/presentation/driver_deliveries_page.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDispatchRepository extends Mock implements DispatchRepository {}

DriverMe _me({
  String mode = 'self_assign',
  int cap = 3,
  int active = 0,
}) =>
    DriverMe(
      id: 1,
      clockedIn: true,
      dispatchMode: mode,
      maxActiveDeliveries: cap,
      activeDeliveries: active,
      remainingCapacity: cap - active,
    );

AvailableOrders _available(
  List<DispatchOrder> orders, {
  int cap = 3,
  int active = 0,
  bool enabled = true,
}) =>
    AvailableOrders(
      enabled: enabled,
      dispatchMode: enabled ? 'self_assign' : 'counter',
      maxActiveDeliveries: cap,
      activeDeliveries: active,
      remainingCapacity: cap - active,
      orders: orders,
    );

DispatchOrder _order(int id) => DispatchOrder(
      orderId: id,
      status: 'ready',
      total: 25,
      paymentStatus: 'paid',
      deliveryAddress: '$id rue de la Paix',
      itemsCount: 2,
    );

DriverDelivery _delivery(int id, {String phase = 'ready'}) => DriverDelivery(
      id: id,
      orderId: id + 1000,
      status: phase == 'en_route' ? 'out_for_delivery' : 'assigned',
      phase: phase,
      total: 25,
      amountDue: 0,
      paymentStatus: 'paid',
      customerName: 'Claire D.',
      customerPhone: '0698765432',
      deliveryAddress: '1 rue de la Paix, Paris',
      itemsCount: 2,
    );

EstablishmentDispatchSettings _settings({
  String mode = 'counter',
  int cap = 3,
  int wait = 5,
  int calls = 1,
  bool overridden = false,
  int version = 0,
}) =>
    EstablishmentDispatchSettings(
      establishmentId: 7,
      dispatchMode: mode,
      maxActiveDeliveries: cap,
      failureMinWaitMinutes: wait,
      failureMinCallAttempts: calls,
      failureRulesOverridden: overridden,
      version: version,
    );

void main() {
  group('ecran livreur en libre-service', () {
    late _MockDispatchRepository repo;
    late DriverMe me;
    late AvailableOrders available;
    late List<DriverDelivery> deliveries;

    setUp(() {
      repo = _MockDispatchRepository();
      me = _me();
      available = _available([_order(11), _order(12)]);
      deliveries = [];
      when(() => repo.driverDeliveries()).thenAnswer((_) async => deliveries);
      when(() => repo.driverMe()).thenAnswer((_) async => me);
      when(() => repo.driverAvailable()).thenAnswer((_) async => available);
      when(() => repo.driverRecap()).thenAnswer(
        (_) async => throw StateError('not used'),
      );
      when(() => repo.claim(any())).thenAnswer((_) async {});
      when(() => repo.release(any())).thenAnswer((_) async {});
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(600, 2800);
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

    testWidgets('liste les commandes disponibles et affiche la charge', (
      tester,
    ) async {
      me = _me(active: 1);
      available = _available([_order(11), _order(12)], active: 1);
      await pump(tester);

      expect(find.text('Disponibles (2)'), findsOneWidget);
      expect(find.text('1 / 3 livraisons en cours'), findsOneWidget);
      expect(find.byKey(const ValueKey('claim-order-11')), findsOneWidget);
      expect(find.byKey(const ValueKey('claim-order-12')), findsOneWidget);
    });

    testWidgets('prendre une commande appelle l\'API avec son identifiant', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('claim-order-12')));
      await tester.pumpAndSettle();

      verify(() => repo.claim([12])).called(1);
      expect(find.text('Commande #12 prise'), findsOneWidget);
    });

    testWidgets('au plafond, prendre est desactive et le motif visible', (
      tester,
    ) async {
      me = _me(active: 3);
      available = _available([_order(11)], active: 3);
      await pump(tester);

      expect(find.textContaining('Plafond atteint : 3 / 3'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('claim-order-11')),
      );
      expect(button.onPressed, isNull);
      verifyNever(() => repo.claim(any()));
    });

    testWidgets('une commande prise par un autre affiche l\'erreur du serveur', (
      tester,
    ) async {
      when(() => repo.claim(any())).thenThrow(
        const ApiError(
          code: 'ORDER_ALREADY_TAKEN',
          message: 'La commande #11 est deja prise.',
          statusCode: 409,
        ),
      );
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('claim-order-11')));
      await tester.pumpAndSettle();

      expect(find.text('La commande #11 est deja prise.'), findsOneWidget);
    });

    testWidgets('rendre : confirmation puis appel, jamais une commande en route', (
      tester,
    ) async {
      deliveries = [_delivery(1), _delivery(2, phase: 'en_route')];
      me = _me(active: 2);
      available = _available([], active: 2);
      await pump(tester);

      expect(find.byKey(const ValueKey('release-2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('release-1')));
      await tester.pumpAndSettle();
      verifyNever(() => repo.release(any()));

      await tester.tap(find.byKey(const ValueKey('release-confirm')));
      await tester.pumpAndSettle();
      verify(() => repo.release(1)).called(1);
    });

    testWidgets('en mode comptoir : ni section Disponibles ni bouton Rendre', (
      tester,
    ) async {
      me = _me(mode: 'counter');
      available = _available([_order(11)], enabled: false);
      deliveries = [_delivery(1)];
      await pump(tester);

      expect(find.textContaining('Disponibles'), findsNothing);
      expect(find.byKey(const ValueKey('driver-capacity')), findsNothing);
      expect(find.byKey(const ValueKey('release-1')), findsNothing);
      verifyNever(() => repo.driverAvailable());
    });
  });

  group('carte de reglages par etablissement', () {
    late _MockDispatchRepository repo;
    late EstablishmentDispatchSettings current;

    setUp(() {
      repo = _MockDispatchRepository();
      current = _settings();
      when(() => repo.dispatchSettings(7)).thenAnswer((_) async => current);
      when(
        () => repo.updateDispatchSettings(
          7,
          expectedVersion: any(named: 'expectedVersion'),
          changes: any(named: 'changes'),
        ),
      ).thenAnswer((_) async => current);
    });

    Future<void> pump(WidgetTester tester, {bool isAdmin = true}) async {
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dispatchRepositoryProvider.overrideWithValue(repo),
            currentEstablishmentProvider.overrideWith(
              (ref) async => const Establishment(
                id: 7,
                name: 'Paris 11',
                timezone: 'Europe/Paris',
                isActive: true,
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: EstablishmentDispatchCard(isAdmin: isAdmin),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, String key, String label) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    testWidgets('affiche l\'etablissement et les valeurs effectives', (
      tester,
    ) async {
      current = _settings(mode: 'self_assign', cap: 2, version: 3);
      await pump(tester);

      expect(find.text('Livraison : Paris 11'), findsOneWidget);
      expect(find.text('Les livreurs se servent'), findsOneWidget);
      expect(find.textContaining('regles generales'), findsOneWidget);
    });

    testWidgets('changer le mode envoie le champ et la version attendue', (
      tester,
    ) async {
      current = _settings(version: 4);
      await pump(tester);

      await choose(tester, 'dispatch-mode', 'Les livreurs se servent');

      verify(
        () => repo.updateDispatchSettings(
          7,
          expectedVersion: 4,
          changes: {'dispatch_mode': 'self_assign'},
        ),
      ).called(1);
    });

    testWidgets('revenir au reglage general envoie une valeur nulle', (
      tester,
    ) async {
      current = _settings(wait: 1, overridden: true, version: 2);
      await pump(tester);
      expect(find.textContaining('propres a cet etablissement'), findsOneWidget);

      await choose(tester, 'est-failure-wait', 'Reglage general');

      verify(
        () => repo.updateDispatchSettings(
          7,
          expectedVersion: 2,
          changes: {'failure_min_wait_minutes': null},
        ),
      ).called(1);
    });

    testWidgets('un conflit de version affiche le message du serveur', (
      tester,
    ) async {
      when(
        () => repo.updateDispatchSettings(
          7,
          expectedVersion: any(named: 'expectedVersion'),
          changes: any(named: 'changes'),
        ),
      ).thenThrow(
        const ApiError(
          code: 'DISPATCH_SETTINGS_CONFLICT',
          message: 'Les reglages ont ete modifies entre-temps, rechargez la page.',
          statusCode: 409,
        ),
      );
      await pump(tester);

      await choose(tester, 'dispatch-cap', '5');

      expect(find.textContaining('modifies entre-temps'), findsOneWidget);
    });

    testWidgets('hors administrateur, tout est en lecture seule', (tester) async {
      await pump(tester, isAdmin: false);

      for (final key in [
        'dispatch-mode',
        'dispatch-cap',
        'est-failure-wait',
        'est-failure-calls',
      ]) {
        final field = tester.widget<DropdownButtonFormField<Object>>(
          find.byKey(ValueKey(key)),
        );
        expect(field.onChanged, isNull, reason: key);
      }
    });
  });
}
