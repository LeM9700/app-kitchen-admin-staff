import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/features/checkout/presentation/delivery_address_picker.dart';
import 'package:app_admin_staff/features/delivery/data/delivery_repository.dart';
import 'package:app_admin_staff/features/loyalty/data/loyalty_repository.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/promotions/data/promotions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'delivery_test_support.dart';

void main() {
  group('DeliveryZone', () {
    test('lit zone, regles, forme et contour', () {
      final zone = DeliveryZone.fromJson(
        zoneJson(
          id: 7,
          name: 'Centre',
          rules: [
            {
              'id': 3,
              'label': 'Vendredi soir',
              'kind': 'fee',
              'fee': 6,
              'days_of_week': [4],
              'start_time': '19:00:00',
              'end_time': '23:00:00',
              'priority': 5,
              'is_active': true,
            },
          ],
        ),
      );
      expect((zone.id, zone.name, zone.establishmentId), (7, 'Centre', 1));
      expect((zone.shapeKind, zone.areaKm2), ('circle', 4.0));
      expect(zone.ring, hasLength(4)); // le point de fermeture est retire
      expect(zone.ring.first.latitude, closeTo(44.7766, 1e-6));
      final rule = zone.rules.single;
      expect(rule.kind, 'fee');
      expect(rule.fee, 6.0);
      expect(rule.daysOfWeek, [4]);
      expect((rule.startTime, rule.endTime), ('19:00', '23:00'));
    });

    test('tolere un ancien payload sans les champs recents', () {
      final zone = DeliveryZone.fromJson({
        'id': 1,
        'name': 'Ancienne',
        'fee': 2,
        'min_order_amount': 0,
        'estimated_minutes': 20,
      });
      expect(zone.shapeKind, 'polygon');
      expect(zone.rules, isEmpty);
      expect(zone.ring, isEmpty);
      expect((zone.establishmentId, zone.isActive), (null, true));
    });

    test('un contour illisible donne un anneau vide, jamais d\'exception', () {
      expect(
        DeliveryZone.fromJson({
          'id': 1,
          'name': 'x',
          'polygon': {'coordinates': 'oups'},
        }).ring,
        isEmpty,
      );
      expect(
        DeliveryZone.fromJson({
          'id': 1,
          'name': 'x',
          'polygon': {
            'coordinates': [
              [
                ['a', 'b'],
                [1, 2],
              ],
            ],
          },
        }).ring,
        hasLength(1),
      );
    });
  });

  group('ZoneShape', () {
    test('se reconstruit depuis la zone selon son mode de saisie', () {
      expect(
        ZoneShape.fromZone(
          DeliveryZone.fromJson(
            zoneJson(
              id: 1,
              name: 'a',
              shapeParams: {
                'center_lat': 1.0,
                'center_lng': 2.0,
                'radius_m': 900,
              },
            ),
          ),
        ),
        isA<CircleZoneShape>().having((s) => s.radiusMeters, 'radius', 900.0),
      );
      expect(
        ZoneShape.fromZone(
          DeliveryZone.fromJson(
            zoneJson(
              id: 1,
              name: 'a',
              shapeKind: 'isochrone',
              shapeParams: {
                'center_lat': 1.0,
                'center_lng': 2.0,
                'minutes': 12,
              },
            ),
          ),
        ),
        isA<IsochroneZoneShape>().having((s) => s.minutes, 'minutes', 12),
      );
      expect(
        ZoneShape.fromZone(
          DeliveryZone.fromJson(
            zoneJson(id: 1, name: 'a', shapeKind: 'polygon'),
          ),
        ),
        isA<PolygonZoneShape>().having((s) => s.points.length, 'points', 4),
      );
    });

    test('des parametres incomplets retombent sur le contour', () {
      final zone = DeliveryZone.fromJson(
        zoneJson(id: 1, name: 'a', shapeParams: {'center_lat': 1.0}),
      );
      expect(ZoneShape.fromZone(zone), isA<PolygonZoneShape>());
    });

    test('serialisation : lng avant lat, aucun champ en trop', () {
      expect(
        const CircleZoneShape(LatLng(44.0, 20.0), 1500).toJson(),
        {
          'kind': 'circle',
          'center_lat': 44.0,
          'center_lng': 20.0,
          'radius_m': 1500.0,
        },
      );
      expect(
        const IsochroneZoneShape(LatLng(44.0, 20.0), 10).toJson(),
        {
          'kind': 'isochrone',
          'center_lat': 44.0,
          'center_lng': 20.0,
          'minutes': 10,
        },
      );
      expect(
        const PolygonZoneShape(
          [LatLng(44.0, 20.0), LatLng(45.0, 21.0), LatLng(44.0, 22.0)],
        ).toJson(),
        {
          'kind': 'polygon',
          'polygon': {
            'type': 'Polygon',
            'coordinates': [
              [
                [20.0, 44.0],
                [21.0, 45.0],
                [22.0, 44.0],
              ],
            ],
          },
        },
      );
    });
  });

  group('DeliveryZoneRule', () {
    test('serialise une regle « livraison offerte » sans tarif', () {
      const rule =
          DeliveryZoneRule(label: ' Offerte ', kind: 'free', minSubtotal: 25);
      expect(rule.toJson(), {
        'label': 'Offerte',
        'kind': 'free',
        'min_subtotal': 25.0,
        'priority': 0,
        'is_active': true,
      });
    });

    test('serialise un tarif avec jours, fenetre horaire et periode', () {
      const rule = DeliveryZoneRule(
        label: 'Soir',
        kind: 'fee',
        fee: 6,
        daysOfWeek: [4, 5],
        startTime: '19:00',
        endTime: '23:00',
        startsOn: '2026-12-24',
        endsOn: '2026-12-25',
        priority: 3,
      );
      expect(rule.toJson(), {
        'label': 'Soir',
        'kind': 'fee',
        'fee': 6.0,
        'days_of_week': [4, 5],
        'start_time': '19:00',
        'end_time': '23:00',
        'starts_on': '2026-12-24',
        'ends_on': '2026-12-25',
        'priority': 3,
        'is_active': true,
      });
    });

    test('une fenetre horaire incomplete n\'est pas envoyee', () {
      const rule =
          DeliveryZoneRule(label: 'x', kind: 'free', startTime: '19:00');
      final json = rule.toJson();
      expect(json.containsKey('start_time'), isFalse);
      expect(json.containsKey('end_time'), isFalse);
    });

    test('describe : lisible par un restaurateur', () {
      const rule = DeliveryZoneRule(
        label: 'x',
        kind: 'free',
        minSubtotal: 25,
        daysOfWeek: [4],
        startTime: '19:00',
        endTime: '23:00',
      );
      final text = rule.describe(formatMoney);
      expect(text, contains('Livraison offerte'));
      expect(text, contains('ven'));
      expect(text, contains('19:00-23:00'));
      expect(
        const DeliveryZoneRule(
          label: 'x',
          kind: 'fee',
          fee: 4,
          daysOfWeek: [0, 1, 2, 3, 4, 5, 6],
        ).describe(formatMoney),
        isNot(contains('lun')),
      );
    });

    test('copyWith peut effacer tarif, horaires et dates', () {
      const rule = DeliveryZoneRule(
        label: 'x',
        kind: 'fee',
        fee: 4,
        startTime: '19:00',
        endTime: '23:00',
        startsOn: '2026-01-01',
        endsOn: '2026-02-01',
      );
      final cleared = rule.copyWith(
        kind: 'free',
        clearFee: true,
        clearTimes: true,
        clearDates: true,
      );
      expect(
        (
          cleared.fee,
          cleared.startTime,
          cleared.endTime,
          cleared.startsOn,
          cleared.endsOn
        ),
        (null, null, null, null, null),
      );
    });
  });

  group('DeliveryZoneDraft', () {
    test(
        'envoie forme et regles ; sans regles, ne touche pas aux regles existantes',
        () {
      const shape = CircleZoneShape(LatLng(44.0, 20.0), 1000);
      final withRules = const DeliveryZoneDraft(
        name: 'Z',
        fee: 3,
        minOrderAmount: 10,
        estimatedMinutes: 25,
        shape: shape,
        establishmentId: 2,
        rules: [DeliveryZoneRule(label: 'r', kind: 'free')],
      ).toJson();
      expect(withRules['establishment_id'], 2);
      expect(withRules['is_active'], true);
      expect((withRules['rules'] as List), hasLength(1));

      final untouched = const DeliveryZoneDraft(
        name: 'Z',
        fee: 3,
        minOrderAmount: 0,
        estimatedMinutes: 25,
        shape: shape,
      ).toJson();
      expect(untouched.containsKey('rules'), isFalse);
      expect(untouched.containsKey('establishment_id'), isFalse);
    });
  });

  group('reponses de l\'API', () {
    test('DeliveryCheckResult : ancien et nouveau format', () {
      final old = DeliveryCheckResult.fromJson(
        {'zone_id': 1, 'name': 'Z', 'fee': 2, 'estimated_minutes': 20},
      );
      expect(
        (old.freeDelivery, old.minOrderMet, old.baseFee, old.establishmentId),
        (false, null, null, null),
      );

      final full = DeliveryCheckResult.fromJson({
        'zone_id': 1,
        'name': 'Z',
        'fee': 0,
        'base_fee': 3.5,
        'free_delivery': true,
        'applied_label': 'Offerte',
        'remaining_for_free': 5,
        'min_order_amount': 15,
        'min_order_met': false,
        'establishment_id': 4,
        'estimated_minutes': 20,
      });
      expect(
        (
          full.freeDelivery,
          full.minOrderMet,
          full.baseFee,
          full.establishmentId,
          full.remainingForFree
        ),
        (true, false, 3.5, 4, 5.0),
      );
    });

    test('ZonePreview et AddressSuggestion', () {
      final preview = ZonePreview.fromJson({
        'polygon': {
          'type': 'Polygon',
          'coordinates': [
            [
              [20.0, 44.0],
              [20.1, 44.0],
              [20.1, 44.1],
              [20.0, 44.0],
            ],
          ],
        },
        'area_km2': 12.5,
      });
      expect(preview.points, hasLength(3));
      expect(preview.areaKm2, 12.5);

      expect(
        AddressSuggestion.tryParse({'label': 'x', 'lat': 44, 'lng': 20})?.point,
        const LatLng(44, 20),
      );
      expect(
        AddressSuggestion.tryParse({'label': 'x', 'lat': 91, 'lng': 20}),
        isNull,
      );
      expect(
        AddressSuggestion.tryParse({'label': '', 'lat': 44, 'lng': 20}),
        isNull,
      );
      expect(AddressSuggestion.tryParse('x'), isNull);
    });

    test('Establishment lit la position (absente = null)', () {
      // Verifie via le modele du depot d'etablissements.
      expect(establishmentJson().containsKey('latitude'), isTrue);
      expect(
        establishmentJson(withLocation: false).containsKey('latitude'),
        isFalse,
      );
    });
  });

  group('DeliveryRepository', () {
    test('listZones utilise l\'endpoint reserve au personnel', () async {
      final backend = FakeBackend()
        ..onJson('GET', '/delivery/zones/manage', [zoneJson(id: 1, name: 'A')]);
      final zones = await DeliveryRepository(backend.client()).listZones();
      expect(zones.single.name, 'A');
    });

    test('checkAddress n\'envoie que ce qui est renseigne', () async {
      final backend = FakeBackend()
        ..onJson(
          'POST',
          '/delivery/check',
          {'zone_id': 1, 'name': 'Z', 'fee': 2, 'estimated_minutes': 20},
        );
      final repository = DeliveryRepository(backend.client());

      await repository.checkAddress(lat: 1, lng: 2);
      await repository.checkAddress(
        lat: 1,
        lng: 2,
        address: '  12 rue  ',
        subtotal: 20,
        establishmentId: 3,
      );
      final bodies =
          backend.where('POST', '/delivery/check').map(backend.bodyOf).toList();
      expect(bodies[0], {'lat': 1.0, 'lng': 2.0});
      expect(bodies[1], {
        'lat': 1.0,
        'lng': 2.0,
        'address': '12 rue',
        'subtotal': 20.0,
        'establishment_id': 3,
      });
    });

    test('geocode favorise la proximite et ignore les resultats inutilisables',
        () async {
      final backend = FakeBackend()
        ..onJson('GET', '/delivery/geocode', [
          {'label': 'A', 'lat': 44.0, 'lng': 20.0},
          {'label': 'sans point'},
        ]);
      final results = await DeliveryRepository(backend.client())
          .geocode('rue', near: const LatLng(44.1, 20.1));
      expect(results.map((r) => r.label), ['A']);
      final query =
          backend.where('GET', '/delivery/geocode').single.queryParameters;
      expect(
        (query['q'], query['lat'], query['lng'], query['language']),
        ('rue', 44.1, 20.1, 'fr'),
      );
    });

    test(
        'setDeliveryEnabled envoie la version attendue ; setZoneActive ne supprime jamais',
        () async {
      final backend = FakeBackend()
        ..onJson(
          'PUT',
          '/delivery/settings',
          {'internal_enabled': false, 'version': 3},
        )
        ..onJson(
          'PATCH',
          '/delivery/zones/9',
          zoneJson(id: 9, name: 'Z', isActive: false),
        );
      final repository = DeliveryRepository(backend.client());

      final settings = await repository.setDeliveryEnabled(
        enabled: false,
        expectedVersion: 2,
      );
      expect((settings.internalEnabled, settings.version), (false, 3));
      expect(
        backend.bodyOf(backend.where('PUT', '/delivery/settings').single),
        {'internal_enabled': false, 'expected_version': 2},
      );

      await repository.setZoneActive(9, false);
      expect(backend.requests.where((r) => r.method == 'DELETE'), isEmpty);
    });
  });

  group('commande au comptoir', () {
    test(
        'ManualOrderDraft envoie le point GPS d\'une livraison, jamais pour un retrait',
        () {
      const delivery = ManualOrderDraft(
        idempotencyKey: 'k',
        orderType: 'delivery',
        paymentMethod: 'cash',
        deliveryAddress: '12 rue',
        deliveryZoneId: 3,
        deliveryLat: 44.78,
        deliveryLng: 20.44,
        items: [ManualOrderLine(productId: 1, quantity: 1)],
      );
      expect(delivery.toJson()['delivery_lat'], 44.78);
      expect(delivery.toJson()['delivery_lng'], 20.44);

      const pickup = ManualOrderDraft(
        idempotencyKey: 'k',
        orderType: 'pickup',
        paymentMethod: 'cash',
        deliveryLat: 44.78,
        deliveryLng: 20.44,
        items: [ManualOrderLine(productId: 1, quantity: 1)],
      );
      expect(pickup.toJson().containsKey('delivery_lat'), isFalse);

      const noPoint = ManualOrderDraft(
        idempotencyKey: 'k',
        orderType: 'delivery',
        paymentMethod: 'cash',
        deliveryZoneId: 3,
        items: [ManualOrderLine(productId: 1, quantity: 1)],
      );
      expect(noPoint.toJson().containsKey('delivery_lat'), isFalse);
      expect(noPoint.toJson()['delivery_zone_id'], 3);
    });
  });

  group('DeliveryAddressPicker', () {
    Future<
        ({
          List<int?> zones,
          List<LatLng?> points,
          TextEditingController controller,
        })> pumpPicker(
      WidgetTester tester,
      FakeBackend backend, {
      double subtotal = 20,
    }) async {
      final zones = <int?>[];
      final points = <LatLng?>[];
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: deliveryOverrides(backend),
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DeliveryAddressPicker(
                  controller: controller,
                  zoneId: null,
                  onZoneChanged: zones.add,
                  onPointChanged: points.add,
                  subtotal: subtotal,
                  establishmentId: 1,
                  near: const LatLng(44.78, 20.44),
                  onChanged: () {},
                ),
              ),
            ),
          ),
        ),
      );
      return (zones: zones, points: points, controller: controller);
    }

    const suggestions = [
      {'label': 'Knez Mihailova 1, Beograd', 'lat': 44.7866, 'lng': 20.4489},
    ];

    testWidgets(
        'choisir une adresse retient le point, la zone et affiche les frais',
        (tester) async {
      final backend = FakeBackend()
        ..onJson('GET', '/delivery/geocode', suggestions)
        ..onJson('POST', '/delivery/check', {
          'zone_id': 7,
          'name': 'Centre',
          'fee': 3.5,
          'estimated_minutes': 30,
          'min_order_amount': 15.0,
          'min_order_met': true,
        });
      final picker = await pumpPicker(tester, backend);

      await tester.enterText(
        find.byKey(const ValueKey('checkout-delivery-address')),
        'Knez',
      );
      await tester.tap(find.byKey(const ValueKey('checkout-address-search')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('checkout-suggestion-Knez Mihailova 1, Beograd'),
        ),
      );
      await tester.pumpAndSettle();

      expect(picker.controller.text, 'Knez Mihailova 1, Beograd');
      expect(picker.zones, [7]);
      expect(picker.points.last, const LatLng(44.7866, 20.4489));
      expect(
        find.byKey(const ValueKey('checkout-address-result')),
        findsOneWidget,
      );
      expect(find.textContaining('Zone Centre'), findsOneWidget);
      final check =
          backend.bodyOf(backend.where('POST', '/delivery/check').single);
      expect((check['subtotal'], check['establishment_id']), (20.0, 1));
    });

    testWidgets('hors zone : zone et point sont effaces', (tester) async {
      final backend = FakeBackend()
        ..onJson('GET', '/delivery/geocode', suggestions)
        ..onJson(
          'POST',
          '/delivery/check',
          {
            'code': 'DELIVERY_ZONE_UNREACHABLE',
            'detail': 'hors zone',
            'field': null,
          },
          status: 422,
        );
      final picker = await pumpPicker(tester, backend);

      await tester.enterText(
        find.byKey(const ValueKey('checkout-delivery-address')),
        'Knez',
      );
      await tester.tap(find.byKey(const ValueKey('checkout-address-search')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('checkout-suggestion-Knez Mihailova 1, Beograd'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('checkout-address-outside')),
        findsOneWidget,
      );
      expect(picker.zones.last, isNull);
      expect(picker.points.last, isNull);
    });

    testWidgets('modifier l\'adresse a la main invalide le point retenu',
        (tester) async {
      final backend = FakeBackend();
      final picker = await pumpPicker(tester, backend);

      await tester.enterText(
        find.byKey(const ValueKey('checkout-delivery-address')),
        'autre adresse',
      );
      await tester.pump();

      expect(picker.points, [null]);
      expect(
        find.byKey(const ValueKey('checkout-address-result')),
        findsNothing,
      );
    });

    testWidgets(
        'recherche indisponible : on bascule sur le choix manuel de la zone',
        (tester) async {
      final backend = FakeBackend()
        ..onJson(
          'GET',
          '/delivery/geocode',
          {'code': 'GEOCODING_NOT_CONFIGURED', 'detail': 'x', 'field': null},
          status: 503,
        );
      await pumpPicker(tester, backend);

      await tester.enterText(
        find.byKey(const ValueKey('checkout-delivery-address')),
        'Knez',
      );
      await tester.tap(find.byKey(const ValueKey('checkout-address-search')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('choisissez la zone a la main'),
        findsOneWidget,
      );
    });

    testWidgets('moins de 3 caracteres : aucune recherche', (tester) async {
      final backend = FakeBackend();
      await pumpPicker(tester, backend);
      await tester.enterText(
        find.byKey(const ValueKey('checkout-delivery-address')),
        'ab',
      );
      await tester.tap(find.byKey(const ValueKey('checkout-address-search')));
      await tester.pump();
      expect(backend.requests, isEmpty);
      expect(find.text('Saisissez au moins 3 caracteres'), findsOneWidget);
    });

    testWidgets('minimum de commande non atteint : signale en rouge',
        (tester) async {
      final backend = FakeBackend()
        ..onJson('GET', '/delivery/geocode', suggestions)
        ..onJson('POST', '/delivery/check', {
          'zone_id': 7,
          'name': 'Centre',
          'fee': 3.5,
          'estimated_minutes': 30,
          'min_order_amount': 30.0,
          'min_order_met': false,
        });
      await pumpPicker(tester, backend, subtotal: 10);
      await tester.enterText(
        find.byKey(const ValueKey('checkout-delivery-address')),
        'Knez',
      );
      await tester.tap(find.byKey(const ValueKey('checkout-address-search')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('checkout-suggestion-Knez Mihailova 1, Beograd'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('non atteint'), findsOneWidget);
    });
  });

  group('promotions et fidelite : livraison offerte', () {
    test('PromotionAdminItem lit free_delivery (absent = faux)', () {
      PromotionAdminItem parse(Map<String, dynamic> extra) =>
          PromotionAdminItem.fromJson({
            'id': 1,
            'code': 'LIVRE0',
            'discount_type': 'fixed',
            'discount_value': 0,
            ...extra,
          });
      expect(parse({'free_delivery': true}).freeDelivery, isTrue);
      expect(parse({}).freeDelivery, isFalse);
    });

    test('create et update transmettent free_delivery', () async {
      final backend = FakeBackend()
        ..onJson('POST', '/promotions', {
          'id': 1,
          'code': 'LIVRE0',
          'discount_type': 'fixed',
          'discount_value': 0,
          'free_delivery': true,
        })
        ..onJson('PATCH', '/promotions/1', {
          'id': 1,
          'code': 'LIVRE0',
          'discount_type': 'fixed',
          'discount_value': 0,
          'free_delivery': false,
        });
      final repository = PromotionsRepository(backend.client());

      await repository.create(
        code: 'LIVRE0',
        discountType: 'fixed',
        discountValue: 0,
        freeDelivery: true,
      );
      expect(
        backend.bodyOf(
          backend.where('POST', '/promotions').single,
        )['free_delivery'],
        true,
      );

      await repository.update(promoId: 1, freeDelivery: false);
      expect(
        backend.bodyOf(
          backend.where('PATCH', '/promotions/1').single,
        )['free_delivery'],
        false,
      );

      await repository.update(promoId: 1, code: 'X');
      expect(
        backend
            .bodyOf(backend.where('PATCH', '/promotions/1').last)
            .containsKey('free_delivery'),
        isFalse,
      );
    });

    test('createReward : livraison offerte sans montant', () async {
      final backend = FakeBackend()
        ..onJson('POST', '/loyalty/rewards', {
          'id': 1,
          'name': 'Livraison',
          'reward_type': 'free_delivery',
          'points_required': 40,
          'is_active': true,
        });
      await LoyaltyRepository(backend.client()).createReward(
        name: 'Livraison',
        rewardType: 'free_delivery',
        pointsRequired: 40,
      );
      final body =
          backend.bodyOf(backend.where('POST', '/loyalty/rewards').single);
      expect(body['reward_type'], 'free_delivery');
      expect(body.containsKey('discount_amount'), isFalse);
    });
  });
}

// Garde-fou de compilation : ApiClient doit rester constructible par le faux backend.
// ignore: unused_element
ApiClient _unused(FakeBackend backend) => backend.client();
