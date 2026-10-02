import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/app/router/app_router.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/features/delivery/data/delivery_repository.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/delivery/presentation/dispatch_page.dart';
import 'package:app_admin_staff/features/driver/presentation/driver_deliveries_page.dart';
import 'package:app_admin_staff/features/driver/presentation/driver_dialogs.dart';
import 'package:app_admin_staff/features/driver/presentation/driver_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDispatchRepository extends Mock implements DispatchRepository {}

class _MockDeliveryRepository extends Mock implements DeliveryRepository {}

StaffUser _user(String role, {Set<String>? permissions}) => StaffUser(
      id: 1,
      email: '$role@test.fr',
      role: role,
      tenantSlug: 'pizza',
      permissions: permissions,
      mustChangePassword: false,
    );

AsyncValue<SessionState> _session(String role) => AsyncData(
      SessionState.authenticated(
        user: _user(role, permissions: {'*'}),
        tenantSlug: 'pizza',
        sessionId: 1,
      ),
    );

DriverSummary _driver(
  int id, {
  String name = 'Marc',
  bool clockedIn = true,
  bool active = true,
  int activeDeliveries = 0,
}) =>
    DriverSummary(
      id: id,
      userId: id + 100,
      establishmentId: 1,
      isActive: active,
      fullName: name,
      clockedIn: clockedIn,
      activeDeliveries: activeDeliveries,
    );

DispatchOrder _order(int id, {String status = 'ready', String payment = 'paid'}) =>
    DispatchOrder(
      orderId: id,
      status: status,
      total: 25,
      paymentStatus: payment,
      deliveryAddress: '$id rue de la Paix',
    );

DriverDelivery _delivery(
  int id, {
  String phase = 'ready',
  double due = 0,
  String? phone = '0698765432',
  double? lat = 48.87,
  double? lng = 2.33,
}) =>
    DriverDelivery(
      id: id,
      orderId: id + 1000,
      status: phase == 'en_route'
          ? 'out_for_delivery'
          : phase == 'arrived'
              ? 'arrived'
              : 'assigned',
      phase: phase,
      total: 25,
      amountDue: due,
      paymentStatus: due > 0 ? 'guaranteed' : 'paid',
      customerName: 'Claire D.',
      customerPhone: phone,
      deliveryAddress: '1 rue de la Paix, Paris',
      deliveryLat: lat,
      deliveryLng: lng,
      itemsCount: 2,
    );

void main() {
  group('navigation du livreur', () {
    test('un livreur est ramene a ses livraisons depuis tout autre ecran', () {
      for (final path in [
        '/home',
        '/orders',
        '/payments',
        '/team',
        '/hr',
        '/settings',
        '/delivery',
        '/dispatch',
        '/kitchen/remote',
        '/inconnu',
      ]) {
        expect(redirectForSession(_session('driver'), path), '/driver', reason: path);
      }
    });

    test('ses trois ecrans lui sont ouverts, et l\'accueil apres connexion aussi', () {
      for (final path in ['/driver', '/driver/recap', '/driver/clock']) {
        expect(redirectForSession(_session('driver'), path), isNull, reason: path);
      }
      expect(redirectForSession(_session('driver'), '/bootstrap'), '/driver');
      expect(redirectForSession(_session('driver'), '/login'), '/driver');
    });

    test('les ecrans livreur sont interdits aux autres roles', () {
      for (final role in ['staff', 'admin']) {
        expect(redirectForSession(_session(role), '/driver'), '/forbidden', reason: role);
        expect(redirectForSession(_session(role), '/driver/recap'), '/forbidden');
      }
    });

    test('le dispatch reste soumis a la permission commandes', () {
      expect(redirectForSession(_session('admin'), '/dispatch'), isNull);
      expect(
        redirectForSession(
          AsyncData(
            SessionState.authenticated(
              user: _user('staff', permissions: {}),
              tenantSlug: 'pizza',
              sessionId: 1,
            ),
          ),
          '/dispatch',
        ),
        '/forbidden',
      );
    });

    test('la coque livreur n\'expose que trois destinations', () {
      expect(driverDestinations.map((d) => d.path), ['/driver', '/driver/recap', '/driver/clock']);
      expect(driverDestinationIndex('/driver/clock'), 2);
      expect(driverDestinationIndex('/driver'), 0);
    });
  });

  group('aides du livreur', () {
    test('itineraire : point GPS si connu, sinon adresse', () {
      final withPoint = routeUriFor(_delivery(1));
      expect(withPoint!.queryParameters['destination'], '48.87,2.33');
      final byAddress = routeUriFor(_delivery(1, lat: null, lng: null));
      expect(byAddress!.queryParameters['destination'], '1 rue de la Paix, Paris');
    });

    test('appel : numero nettoye, rien sans telephone', () {
      expect(phoneUriFor(_delivery(1, phone: '06 98-76 54.32'))!.toString(), 'tel:0698765432');
      expect(phoneUriFor(_delivery(1, phone: null)), isNull);
    });

    test('especes recues : au moins le montant du', () {
      expect(validCashReceived('25', 25), 25);
      expect(validCashReceived('30,5', 25), 30.5);
      expect(validCashReceived('24.99', 25), isNull);
      expect(validCashReceived('', 25), isNull);
      expect(validCashReceived('abc', 25), isNull);
    });

    test('disponibilite d\'un livreur vue du comptoir', () {
      expect(driverAvailabilityLabel(_driver(1)), 'Disponible');
      expect(driverAvailabilityLabel(_driver(1, clockedIn: false)), 'Non pointe');
      expect(driverAvailabilityLabel(_driver(1, active: false)), 'Desactive');
      expect(driverUnavailableReason(_driver(1)), isNull);
      expect(driverUnavailableReason(_driver(1, clockedIn: false)), isNotNull);
    });
  });

  group('modeles', () {
    test('le tableau de dispatch se lit depuis l\'API', () {
      final board = DispatchBoard.fromJson({
        'dispatch_enabled': true,
        'unassigned': [
          {'order_id': 4, 'status': 'ready', 'total': 25, 'payment_status': 'guaranteed'},
        ],
        'deliveries': [
          {
            'id': 9,
            'status': 'assigned',
            'driver_id': 2,
            'driver_name': 'Marc',
            'order': {'order_id': 5, 'status': 'ready', 'total': 12, 'payment_status': 'paid'},
          },
        ],
        'drivers': [
          {'id': 2, 'user_id': 8, 'establishment_id': 1, 'is_active': true, 'clocked_in': true},
        ],
      });
      expect(board.dispatchEnabled, isTrue);
      expect(board.unassigned.single.dueOnDelivery, isTrue);
      expect(board.deliveries.single.canReassign, isTrue);
      expect(board.drivers.single.assignable, isTrue);
    });

    test('une livraison partie ne se reattribue plus', () {
      final delivery = DispatchDelivery.fromJson({
        'id': 1,
        'status': 'out_for_delivery',
        'driver_id': 2,
        'order': {'order_id': 5, 'total': 12},
      });
      expect(delivery.canReassign, isFalse);
    });

    test('la vue livreur ne contient que ce qu\'il lui faut', () {
      final d = DriverDelivery.fromJson({
        'id': 1,
        'order_id': 7,
        'status': 'assigned',
        'phase': 'ready',
        'total': 25,
        'amount_due': 25,
        'payment_status': 'guaranteed',
        'customer_phone': '0698765432',
      });
      expect(d.canDepart, isTrue);
      expect(d.isOngoing, isFalse);
      expect(d.amountDue, 25);
    });

    test('les reglages lisent le drapeau de dispatch (absent = coupe)', () {
      expect(
        DeliverySettings.fromJson({'internal_enabled': true, 'version': 2}).driverDispatchEnabled,
        isFalse,
      );
      expect(
        DeliverySettings.fromJson({
          'internal_enabled': true,
          'driver_dispatch_enabled': true,
          'version': 3,
        }).driverDispatchEnabled,
        isTrue,
      );
    });
  });

  group('page de dispatch', () {
    late _MockDispatchRepository repo;
    late _MockDeliveryRepository deliveryRepo;
    late DispatchBoard board;

    setUp(() {
      repo = _MockDispatchRepository();
      deliveryRepo = _MockDeliveryRepository();
      board = DispatchBoard(
        dispatchEnabled: true,
        unassigned: [_order(11), _order(12, payment: 'guaranteed')],
        deliveries: [
          DispatchDelivery(
            id: 1,
            status: 'assigned',
            driverId: 2,
            driverName: 'Marc',
            order: _order(21),
          ),
          DispatchDelivery(
            id: 2,
            status: 'out_for_delivery',
            driverId: 2,
            driverName: 'Marc',
            order: _order(22),
          ),
        ],
        drivers: [
          _driver(2, name: 'Marc', activeDeliveries: 2),
          _driver(3, name: 'Lea'),
          _driver(4, name: 'Absent', clockedIn: false),
        ],
      );
      when(() => repo.board(establishmentId: any(named: 'establishmentId')))
          .thenAnswer((_) async => board);
      when(() => repo.assign(orderIds: any(named: 'orderIds'), driverId: any(named: 'driverId')))
          .thenAnswer((_) async {});
      when(() => repo.unassign(any())).thenAnswer((_) async {});
      when(() => repo.setDriverActive(any(), any()))
          .thenAnswer((_) async => _driver(3, active: false));
      when(
        () => deliveryRepo.setDriverDispatch(
          enabled: any(named: 'enabled'),
          internalEnabled: any(named: 'internalEnabled'),
          expectedVersion: any(named: 'expectedVersion'),
        ),
      ).thenAnswer(
        (_) async => const DeliverySettings(internalEnabled: true, version: 4),
      );
    });

    Future<void> pump(WidgetTester tester, {String role = 'staff'}) async {
      tester.view.physicalSize = const Size(900, 2400);
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

    testWidgets('affiche livreurs, commandes a attribuer et livraisons en cours', (tester) async {
      await pump(tester);

      expect(find.text('A attribuer (2)'), findsOneWidget);
      expect(find.text('En cours (2)'), findsOneWidget);
      expect(find.text('Commande #11'), findsOneWidget);
      expect(find.text('A encaisser a la remise'), findsOneWidget);
      expect(find.text('Non pointe'), findsOneWidget);
    });

    testWidgets('attribue plusieurs commandes a un livreur disponible', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('select-order-12')));
      await tester.tap(find.byKey(const ValueKey('select-order-11')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('dispatch-assign-selected')));
      await tester.pumpAndSettle();

      // Le livreur qui n'a pas pointe est visible mais grise.
      expect(
        tester.widget<ListTile>(find.byKey(const ValueKey('driver-option-4'))).enabled,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('driver-option-3')));
      await tester.pumpAndSettle();

      verify(() => repo.assign(orderIds: [11, 12], driverId: 3)).called(1);
    });

    testWidgets('un livreur qui n\'a pas pointe ne peut pas etre choisi', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('select-order-11')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('dispatch-assign-selected')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('driver-option-4')));
      await tester.pumpAndSettle();

      verifyNever(
        () => repo.assign(orderIds: any(named: 'orderIds'), driverId: any(named: 'driverId')),
      );
    });

    testWidgets('reattribuer exclut le livreur actuel, retirer appelle l\'API', (tester) async {
      await pump(tester);

      // Seule la livraison pas encore partie propose Reattribuer / Retirer.
      expect(find.byKey(const ValueKey('reassign-21')), findsOneWidget);
      expect(find.byKey(const ValueKey('reassign-22')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('reassign-21')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('driver-option-2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('driver-option-3')));
      await tester.pumpAndSettle();
      verify(() => repo.assign(orderIds: [21], driverId: 3)).called(1);

      await tester.tap(find.byKey(const ValueKey('unassign-21')));
      await tester.pumpAndSettle();
      verify(() => repo.unassign(21)).called(1);
    });

    testWidgets('une erreur de l\'API est affichee', (tester) async {
      when(() => repo.assign(orderIds: any(named: 'orderIds'), driverId: any(named: 'driverId')))
          .thenThrow(
        const ApiError(message: 'Ce livreur n\'a pas pointe', statusCode: 409),
      );
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('select-order-11')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('dispatch-assign-selected')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('driver-option-3')));
      await tester.pumpAndSettle();

      expect(find.text('Ce livreur n\'a pas pointe'), findsOneWidget);
    });

    testWidgets('seul un administrateur change le dispatch ou desactive un livreur', (tester) async {
      await pump(tester, role: 'staff');
      expect(
        tester.widget<SwitchListTile>(find.byKey(const ValueKey('dispatch-enabled-switch'))).onChanged,
        isNull,
      );
      expect(
        tester.widget<Switch>(find.byKey(const ValueKey('driver-active-3'))).onChanged,
        isNull,
      );
    });

    testWidgets('l\'administrateur coupe le dispatch avec la version attendue', (tester) async {
      await pump(tester, role: 'admin');

      await tester.tap(find.byKey(const ValueKey('dispatch-enabled-switch')));
      await tester.pumpAndSettle();

      verify(
        () => deliveryRepo.setDriverDispatch(
          enabled: false,
          internalEnabled: true,
          expectedVersion: 3,
        ),
      ).called(1);

      await tester.tap(find.byKey(const ValueKey('driver-active-3')));
      await tester.pumpAndSettle();
      verify(() => repo.setDriverActive(3, false)).called(1);
    });
  });

  group('ecran livreur', () {
    late _MockDispatchRepository repo;
    late List<DriverDelivery> deliveries;

    setUp(() {
      repo = _MockDispatchRepository();
      deliveries = [];
      when(() => repo.driverDeliveries()).thenAnswer((_) async => deliveries);
      when(() => repo.depart(any())).thenAnswer((_) async {});
      when(() => repo.arrived(any())).thenAnswer((_) async {});
      when(() => repo.delivered(any(), cashReceived: any(named: 'cashReceived')))
          .thenAnswer((_) async {});
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dispatchRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: Scaffold(body: DriverDeliveriesPage())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sans livraison, un message clair', (tester) async {
      await pump(tester);
      expect(find.textContaining('Aucune livraison'), findsOneWidget);
    });

    testWidgets('En cours puis A venir ; seule une commande prete peut partir', (tester) async {
      deliveries = [
        _delivery(1, phase: 'en_route'),
        _delivery(2, phase: 'ready'),
        _delivery(3, phase: 'upcoming'),
      ];
      await pump(tester);

      expect(find.text('En cours (1)'), findsOneWidget);
      expect(find.text('A venir (2)'), findsOneWidget);
      expect(find.byKey(const ValueKey('select-delivery-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('select-delivery-3')), findsNothing);
      expect(find.text('En preparation'), findsOneWidget);
    });

    testWidgets('partir avec plusieurs commandes prêtes en un seul depart', (tester) async {
      deliveries = [_delivery(2), _delivery(5)];
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('select-delivery-2')));
      await tester.tap(find.byKey(const ValueKey('select-delivery-5')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('driver-depart')));
      await tester.pumpAndSettle();

      verify(() => repo.depart([2, 5])).called(1);
    });

    testWidgets('arrive : seulement quand on est en route', (tester) async {
      deliveries = [_delivery(1, phase: 'en_route'), _delivery(2, phase: 'arrived')];
      await pump(tester);

      expect(find.byKey(const ValueKey('arrived-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('arrived-2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('arrived-1')));
      await tester.pumpAndSettle();
      verify(() => repo.arrived(1)).called(1);
    });

    testWidgets('commande deja payee : confirmation simple, aucun encaissement', (tester) async {
      deliveries = [_delivery(1, phase: 'arrived')];
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('delivered-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cash-received')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('confirm-delivered')));
      await tester.pumpAndSettle();

      verify(() => repo.delivered(1, cashReceived: null)).called(1);
    });

    testWidgets('empreinte a regler : les especes recues couvrent le montant du', (tester) async {
      deliveries = [_delivery(1, phase: 'arrived', due: 25)];
      await pump(tester);
      expect(find.text('Encaisser ${formatMoney(25)}'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('delivered-1')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('cash-received')), '10');
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byKey(const ValueKey('confirm-delivered'))).onPressed,
        isNull,
      );
      expect(find.text('Montant insuffisant ou invalide'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('cash-received')), '30');
      await tester.pump();
      expect(find.textContaining('A rendre'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-delivered')));
      await tester.pumpAndSettle();

      verify(() => repo.delivered(1, cashReceived: 30)).called(1);
    });

    testWidgets('annuler l\'encaissement ne livre rien', (tester) async {
      deliveries = [_delivery(1, phase: 'arrived', due: 25)];
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('delivered-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.delivered(any(), cashReceived: any(named: 'cashReceived')));
    });

    testWidgets('une erreur de l\'API est affichee au livreur', (tester) async {
      when(() => repo.depart(any())).thenThrow(
        const ApiError(message: 'La commande #1002 n\'est pas encore prete.', statusCode: 409),
      );
      deliveries = [_delivery(2)];
      await pump(tester);

      await tester.tap(find.byKey(const ValueKey('select-delivery-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('driver-depart')));
      await tester.pumpAndSettle();

      expect(find.textContaining('pas encore prete'), findsOneWidget);
    });
  });
}
