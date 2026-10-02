import 'package:app_admin_staff/features/delivery/presentation/delivery_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'delivery_test_support.dart';

const _previewJson = {
  'polygon': {
    'type': 'Polygon',
    'coordinates': [
      [
        [20.45, 44.78],
        [20.47, 44.78],
        [20.47, 44.80],
        [20.45, 44.80],
        [20.45, 44.78],
      ],
    ],
  },
  'shape_kind': 'circle',
  'area_km2': 28.3,
  'points': 64,
};

Future<void> _pumpPage(
  WidgetTester tester,
  FakeBackend backend, {
  String role = 'admin',
  Size size = const Size(1400, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: deliveryOverrides(backend, role: role),
      child: const MaterialApp(home: Scaffold(body: DeliveryPage())),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openNewZone(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('delivery-new-zone')));
  await tester.pumpAndSettle();
}

Finder _field(String key) => find.byKey(ValueKey(key));

void main() {
  group('page Livraison', () {
    testWidgets(
        'liste les zones depuis l\'endpoint d\'administration, avec regles et carte',
        (tester) async {
      final backend = deliveryBackend(
        zones: [
          zoneJson(
            id: 7,
            name: 'Centre',
            rules: [
              {
                'id': 1,
                'label': 'Offerte des 25',
                'kind': 'free',
                'min_subtotal': 25.0,
                'priority': 0,
                'is_active': true,
              },
            ],
          ),
          zoneJson(
            id: 8,
            name: 'Banlieue',
            isActive: false,
            shapeKind: 'polygon',
          ),
        ],
      );
      await _pumpPage(tester, backend);

      expect(find.text('Centre'), findsOneWidget);
      expect(find.text('Banlieue'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.textContaining('Offerte des 25'), findsWidgets);
      expect(find.byKey(const ValueKey('delivery-zones-map')), findsOneWidget);
      expect(backend.where('GET', '/delivery/zones/manage'), hasLength(1));
    });

    testWidgets('le filtre « Inactives » montre enfin les zones desactivees',
        (tester) async {
      final backend = deliveryBackend(
        zones: [
          zoneJson(id: 7, name: 'Centre'),
          zoneJson(id: 8, name: 'Banlieue', isActive: false),
        ],
      );
      await _pumpPage(tester, backend);

      await tester.tap(find.text('Inactives'));
      await tester.pumpAndSettle();

      expect(find.text('Banlieue'), findsOneWidget);
      expect(find.text('Centre'), findsNothing);
    });

    testWidgets(
        'le personnel non administrateur ne voit aucune action de modification',
        (tester) async {
      final backend = deliveryBackend(zones: [zoneJson(id: 7, name: 'Centre')]);
      await _pumpPage(tester, backend, role: 'staff');

      expect(find.text('Centre'), findsOneWidget);
      expect(find.byKey(const ValueKey('delivery-new-zone')), findsNothing);
      expect(find.byKey(const ValueKey('zone-edit-7')), findsNothing);
      expect(find.byKey(const ValueKey('zone-toggle-7')), findsNothing);
      final switchTile = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('delivery-enabled-switch')),
      );
      expect(switchTile.onChanged, isNull);
    });

    testWidgets('desactiver une zone demande confirmation puis envoie un PATCH',
        (tester) async {
      final backend = deliveryBackend(zones: [zoneJson(id: 7, name: 'Centre')])
        ..onJson(
          'PATCH',
          '/delivery/zones/7',
          zoneJson(id: 7, name: 'Centre', isActive: false),
        );
      await _pumpPage(tester, backend);

      await tester.tap(find.byKey(const ValueKey('zone-toggle-7')));
      await tester.pumpAndSettle();
      expect(
        backend.where('PATCH', '/delivery/zones/7'),
        isEmpty,
      ); // pas sans confirmation
      expect(find.text('Desactiver Centre ?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('zone-deactivate-confirm')));
      await tester.pumpAndSettle();

      final patches = backend.where('PATCH', '/delivery/zones/7');
      expect(patches, hasLength(1));
      expect(backend.bodyOf(patches.single), {'is_active': false});
      expect(find.text('Zone desactivee'), findsOneWidget);
    });

    testWidgets('reactiver une zone ne demande pas de confirmation',
        (tester) async {
      final backend = deliveryBackend(
        zones: [zoneJson(id: 8, name: 'Banlieue', isActive: false)],
      )..onJson(
          'PATCH',
          '/delivery/zones/8',
          zoneJson(id: 8, name: 'Banlieue'),
        );
      await _pumpPage(tester, backend);

      await tester.tap(find.byKey(const ValueKey('zone-toggle-8')));
      await tester.pumpAndSettle();

      expect(
        backend.bodyOf(backend.where('PATCH', '/delivery/zones/8').single),
        {'is_active': true},
      );
      expect(find.text('Zone reactivee'), findsOneWidget);
    });

    testWidgets(
        'couper la livraison demande confirmation et envoie la version attendue',
        (tester) async {
      final backend = deliveryBackend(settingsVersion: 4)
        ..onJson(
          'PUT',
          '/delivery/settings',
          {'internal_enabled': false, 'version': 5},
        );
      await _pumpPage(tester, backend);

      await tester.tap(find.byKey(const ValueKey('delivery-enabled-switch')));
      await tester.pumpAndSettle();
      expect(backend.where('PUT', '/delivery/settings'), isEmpty);
      expect(find.text('Couper la livraison ?'), findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey('delivery-switch-confirm-off')));
      await tester.pumpAndSettle();

      final puts = backend.where('PUT', '/delivery/settings');
      expect(puts, hasLength(1));
      expect(
        backend.bodyOf(puts.single),
        {'internal_enabled': false, 'expected_version': 4},
      );
    });

    testWidgets('un conflit de version recharge les reglages et previent',
        (tester) async {
      final backend = deliveryBackend(settingsVersion: 1)
        ..onJson(
          'PUT',
          '/delivery/settings',
          {
            'code': 'DELIVERY_SETTINGS_CONFLICT',
            'detail': 'Les reglages ont ete modifies entre-temps',
            'field': null,
          },
          status: 409,
        );
      await _pumpPage(tester, backend);

      await tester.tap(find.byKey(const ValueKey('delivery-enabled-switch')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('delivery-switch-confirm-off')));
      await tester.pumpAndSettle();

      expect(find.textContaining('modifies entre-temps'), findsOneWidget);
      expect(
        backend.where('GET', '/delivery/settings'),
        hasLength(2),
      ); // recharge apres l'echec
    });

    testWidgets('livraison deja coupee : l\'interrupteur le dit',
        (tester) async {
      final backend = deliveryBackend(deliveryEnabled: false);
      await _pumpPage(tester, backend);
      expect(
        find.textContaining('seul le retrait est propose'),
        findsOneWidget,
      );
    });
  });

  group('editeur de zone', () {
    testWidgets(
        'creation par rayon : le serveur construit le contour, aucun GeoJSON saisi',
        (tester) async {
      final backend = deliveryBackend()
        ..onJson(
          'POST',
          '/delivery/zones',
          zoneJson(id: 1, name: 'Centre-ville'),
        );
      await _pumpPage(tester, backend);
      await _openNewZone(tester);

      await tester.enterText(_field('zone-name-field'), 'Centre-ville');
      await tester.enterText(_field('zone-fee-field'), '3,5');
      await tester.enterText(_field('zone-min-field'), '15');
      await tester.enterText(_field('zone-minutes-field'), '30');
      await tester.tap(_field('zone-save-button'));
      await tester.pumpAndSettle();

      final body =
          backend.bodyOf(backend.where('POST', '/delivery/zones').single);
      expect(body['name'], 'Centre-ville');
      expect(
        (body['fee'], body['min_order_amount'], body['estimated_minutes']),
        (3.5, 15.0, 30),
      );
      expect(body['is_active'], true);
      expect(body['establishment_id'], 1);
      expect(body.containsKey('polygon'), isFalse);
      final shape = Map<String, dynamic>.from(body['shape'] as Map);
      expect(shape['kind'], 'circle');
      expect(
        (shape['center_lat'], shape['center_lng']),
        (44.7866, 20.4489),
      ); // position du restaurant
      expect(shape['radius_m'], 3000.0);
      expect(body['rules'], isEmpty);
      expect(find.text('Zone creee'), findsOneWidget);
    });

    testWidgets(
        'un nom vide ou des montants invalides bloquent l\'enregistrement',
        (tester) async {
      final backend = deliveryBackend();
      await _pumpPage(tester, backend);
      await _openNewZone(tester);

      await tester.tap(_field('zone-save-button'));
      await tester.pump();
      expect(find.text('Nom obligatoire'), findsOneWidget);

      await tester.enterText(_field('zone-name-field'), 'Z');
      await tester.enterText(_field('zone-fee-field'), '-1');
      await tester.tap(_field('zone-save-button'));
      await tester.pump();
      expect(find.text('Montants invalides'), findsOneWidget);

      await tester.enterText(_field('zone-fee-field'), '2');
      await tester.enterText(_field('zone-minutes-field'), '0');
      await tester.tap(_field('zone-save-button'));
      await tester.pump();
      expect(find.textContaining('Delai invalide'), findsOneWidget);

      expect(backend.where('POST', '/delivery/zones'), isEmpty);
    });

    testWidgets(
        'sans position de restaurant, il faut choisir le centre sur la carte',
        (tester) async {
      final backend = deliveryBackend(
        establishments: [establishmentJson(withLocation: false)],
      );
      await _pumpPage(tester, backend);
      await _openNewZone(tester);
      await tester.enterText(_field('zone-name-field'), 'Zone');

      await tester.tap(_field('zone-save-button'));
      await tester.pump();

      expect(find.textContaining('centre de la zone'), findsOneWidget);
      expect(backend.where('POST', '/delivery/zones'), isEmpty);
      expect(_field('zone-set-restaurant-location'), findsOneWidget);
    });

    testWidgets(
        'toucher la carte place le centre et demande l\'apercu au serveur',
        (tester) async {
      final backend = deliveryBackend()
        ..onJson('POST', '/delivery/zones/preview', _previewJson);
      await _pumpPage(tester, backend);
      await _openNewZone(tester);

      await tapMapAt(tester, _field('zone-map'), offset: const Offset(80, 60));
      await tester.pumpAndSettle();

      final previews = backend.where('POST', '/delivery/zones/preview');
      expect(previews, hasLength(1));
      final shape = Map<String, dynamic>.from(
        backend.bodyOf(previews.single)['shape'] as Map,
      );
      expect(shape['kind'], 'circle');
      expect(shape['center_lat'], isNot(44.7866)); // le centre a bouge
      expect(find.text('Surface couverte : 28.3 km²'), findsOneWidget);
    });

    testWidgets('mode « temps de trajet » : envoie les minutes choisies',
        (tester) async {
      final backend = deliveryBackend()
        ..onJson(
          'POST',
          '/delivery/zones/preview',
          {..._previewJson, 'shape_kind': 'isochrone'},
        )
        ..onJson(
          'POST',
          '/delivery/zones',
          zoneJson(
            id: 2,
            name: '15 min',
            shapeKind: 'isochrone',
            shapeParams: {
              'center_lat': 44.7866,
              'center_lng': 20.4489,
              'minutes': 15,
            },
          ),
        );
      await _pumpPage(tester, backend);
      await _openNewZone(tester);

      await tester.tap(find.text('Temps de trajet'));
      await tester.pumpAndSettle();
      expect(find.text('Temps de trajet : 15 min'), findsOneWidget);
      expect(
        backend.where('POST', '/delivery/zones/preview'),
        hasLength(1),
      ); // apercu automatique au changement de mode

      await tester.enterText(_field('zone-name-field'), '15 min');
      await tester.tap(_field('zone-save-button'));
      await tester.pumpAndSettle();

      final shape = Map<String, dynamic>.from(
        backend.bodyOf(backend.where('POST', '/delivery/zones').single)['shape']
            as Map,
      );
      expect(shape, {
        'kind': 'isochrone',
        'center_lat': 44.7866,
        'center_lng': 20.4489,
        'minutes': 15,
      });
    });

    testWidgets(
        'dessin : trois points forment un polygone envoye en [lng, lat]',
        (tester) async {
      final backend = deliveryBackend()
        ..onJson(
          'POST',
          '/delivery/zones',
          zoneJson(id: 3, name: 'Dessin', shapeKind: 'polygon'),
        );
      await _pumpPage(tester, backend);
      await _openNewZone(tester);
      await tester.tap(find.text('Dessiner'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('zone-name-field'), 'Dessin');

      // Moins de 3 points : refus cote client.
      await tapMapAt(
        tester,
        _field('zone-map'),
        offset: const Offset(-80, -60),
      );
      await tapMapAt(tester, _field('zone-map'), offset: const Offset(80, -60));
      await tester.tap(_field('zone-save-button'));
      await tester.pump();
      expect(find.textContaining('au moins 3 points'), findsOneWidget);
      expect(backend.where('POST', '/delivery/zones'), isEmpty);

      await tapMapAt(tester, _field('zone-map'), offset: const Offset(0, 90));
      expect(find.text('3 point(s)'), findsOneWidget);
      await tester.tap(_field('zone-save-button'));
      await tester.pumpAndSettle();

      final shape = Map<String, dynamic>.from(
        backend.bodyOf(backend.where('POST', '/delivery/zones').single)['shape']
            as Map,
      );
      expect(shape['kind'], 'polygon');
      final ring =
          ((shape['polygon'] as Map)['coordinates'] as List).first as List;
      expect(
        ring,
        hasLength(3),
      ); // sans point de fermeture : le serveur ferme l'anneau
      for (final point in ring) {
        final p = point as List;
        expect(p[0], closeTo(20.4489, 0.2)); // longitude d'abord
        expect(p[1], closeTo(44.7866, 0.2));
      }
    });

    testWidgets('dessin : annuler le dernier point et tout effacer',
        (tester) async {
      final backend = deliveryBackend();
      await _pumpPage(tester, backend);
      await _openNewZone(tester);
      await tester.tap(find.text('Dessiner'));
      await tester.pumpAndSettle();

      await tapMapAt(
        tester,
        _field('zone-map'),
        offset: const Offset(-80, -60),
      );
      await tapMapAt(tester, _field('zone-map'), offset: const Offset(80, -60));
      await tapMapAt(tester, _field('zone-map'), offset: const Offset(0, 90));
      expect(find.text('3 point(s)'), findsOneWidget);

      await tester.tap(_field('zone-undo-point'));
      await tester.pump();
      expect(find.text('2 point(s)'), findsOneWidget);

      await tester.tap(_field('zone-clear-points'));
      await tester.pump();
      expect(find.text('0 point(s)'), findsOneWidget);
    });

    testWidgets('dessin : un point se deplace en le faisant glisser',
        (tester) async {
      final backend = deliveryBackend();
      await _pumpPage(tester, backend);
      await _openNewZone(tester);
      await tester.tap(find.text('Dessiner'));
      await tester.pumpAndSettle();
      await tapMapAt(
        tester,
        _field('zone-map'),
        offset: const Offset(-80, -60),
      );
      await tapMapAt(tester, _field('zone-map'), offset: const Offset(80, -60));
      await tapMapAt(tester, _field('zone-map'), offset: const Offset(0, 90));

      final before = tester.getCenter(_field('zone-point-0'));
      await tester.drag(_field('zone-point-0'), const Offset(30, 20));
      await tester.pump();
      final after = tester.getCenter(_field('zone-point-0'));

      expect(after.dx, closeTo(before.dx + 30, 2));
      expect(after.dy, closeTo(before.dy + 20, 2));
      expect(find.text('3 point(s)'), findsOneWidget); // deplace, pas ajoute
    });

    testWidgets(
        'une erreur serveur (contour qui se croise) s\'affiche et garde l\'editeur ouvert',
        (tester) async {
      final backend = deliveryBackend()
        ..onJson(
          'POST',
          '/delivery/zones',
          {
            'code': 'POLYGON_SELF_INTERSECTING',
            'detail': 'Le contour de la zone se croise lui-meme',
            'field': 'shape',
          },
          status: 422,
        );
      await _pumpPage(tester, backend);
      await _openNewZone(tester);
      await tester.enterText(_field('zone-name-field'), 'Noeud');

      await tester.tap(_field('zone-save-button'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('zone-message')), findsOneWidget);
      expect(find.textContaining('se croise'), findsOneWidget);
      expect(
        find.text('Nouvelle zone'),
        findsWidgets,
      ); // toujours dans l'editeur
      expect(find.text('Zone creee'), findsNothing);
    });

    testWidgets(
        'modifier une zone existante la rouvre telle qu\'elle a ete creee',
        (tester) async {
      final backend = deliveryBackend(
        zones: [
          zoneJson(
            id: 7,
            name: 'Nord',
            shapeParams: {
              'center_lat': 44.80,
              'center_lng': 20.46,
              'radius_m': 4500,
            },
            rules: [
              {
                'id': 1,
                'label': 'Offerte des 25',
                'kind': 'free',
                'min_subtotal': 25.0,
                'priority': 2,
                'is_active': true,
              },
            ],
          ),
        ],
      )..onJson(
          'PUT',
          '/delivery/zones/7',
          zoneJson(id: 7, name: 'Nord etendu'),
        );
      await _pumpPage(tester, backend);

      await tester.tap(find.byKey(const ValueKey('zone-edit-7')));
      await tester.pumpAndSettle();
      expect(find.text('Modifier Nord'), findsOneWidget);
      expect(find.text('Rayon : 4.5 km'), findsOneWidget);
      expect(find.byKey(const ValueKey('zone-rule-0')), findsOneWidget);

      await tester.enterText(_field('zone-name-field'), 'Nord etendu');
      await tester.tap(_field('zone-save-button'));
      await tester.pumpAndSettle();

      final puts = backend.where('PUT', '/delivery/zones/7');
      expect(puts, hasLength(1));
      final body = backend.bodyOf(puts.single);
      expect(body['name'], 'Nord etendu');
      final shape = Map<String, dynamic>.from(body['shape'] as Map);
      expect(
        (shape['center_lat'], shape['center_lng'], shape['radius_m']),
        (44.80, 20.46, 4500.0),
      );
      final rules = (body['rules'] as List).cast<Map>();
      expect(rules.single['label'], 'Offerte des 25');
      expect(rules.single['priority'], 2);
      expect(find.text('Zone mise a jour'), findsOneWidget);
    });

    testWidgets('on peut definir la position du restaurant depuis l\'editeur',
        (tester) async {
      final backend = deliveryBackend(
        establishments: [establishmentJson(withLocation: false)],
      )
        ..onJson(
          'PUT',
          '/delivery/establishments/1/location',
          {'id': 1, 'latitude': 44.8, 'longitude': 20.4},
        )
        ..onJson('POST', '/delivery/zones/preview', _previewJson);
      await _pumpPage(tester, backend);
      await _openNewZone(tester);

      await tapMapAt(tester, _field('zone-map'), offset: const Offset(40, 40));
      await tester.pumpAndSettle();
      await tester.tap(_field('zone-set-restaurant-location'));
      await tester.pumpAndSettle();

      final puts = backend.where('PUT', '/delivery/establishments/1/location');
      expect(puts, hasLength(1));
      expect(
        backend.bodyOf(puts.single).keys,
        containsAll(['latitude', 'longitude']),
      );
      expect(find.text('Position du restaurant enregistree'), findsOneWidget);
    });
  });

  group('regles de tarification', () {
    Future<void> openRuleDialog(WidgetTester tester) async {
      await tester.ensureVisible(_field('zone-add-rule'));
      await tester.tap(_field('zone-add-rule'));
      await tester.pumpAndSettle();
    }

    testWidgets('« livraison offerte des 25 » est envoyee avec la zone',
        (tester) async {
      final backend = deliveryBackend()
        ..onJson('POST', '/delivery/zones', zoneJson(id: 1, name: 'Centre'));
      await _pumpPage(tester, backend);
      await _openNewZone(tester);
      await tester.enterText(_field('zone-name-field'), 'Centre');

      await openRuleDialog(tester);
      await tester.enterText(_field('rule-label'), 'Offerte des 25');
      await tester.enterText(_field('rule-min-subtotal'), '25');
      await tester.tap(_field('rule-save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Offerte des 25'), findsWidgets);

      await tester.ensureVisible(_field('zone-save-button'));
      await tester.tap(_field('zone-save-button'));
      await tester.pumpAndSettle();

      final rules = (backend.bodyOf(
        backend.where('POST', '/delivery/zones').single,
      )['rules'] as List)
          .cast<Map>();
      expect(rules, hasLength(1));
      expect(
        (
          rules.single['label'],
          rules.single['kind'],
          rules.single['min_subtotal']
        ),
        ('Offerte des 25', 'free', 25.0),
      );
      expect(rules.single.containsKey('fee'), isFalse);
      expect(rules.single.containsKey('days_of_week'), isFalse);
    });

    testWidgets('des heures de debut et de fin identiques sont refusees',
        (tester) async {
      final backend = deliveryBackend()
        ..onJson('POST', '/delivery/zones', zoneJson(id: 1, name: 'Centre'));
      await _pumpPage(tester, backend);
      await _openNewZone(tester);
      await tester.enterText(_field('zone-name-field'), 'Centre');

      await openRuleDialog(tester);
      await tester.enterText(_field('rule-label'), 'Vendredi soir');
      await tester.tap(find.text('Autre tarif'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('rule-fee'), '6');
      await tester.tap(_field('rule-day-4'));
      await tester.pump();
      await tester.tap(_field('rule-start-time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(_field('rule-end-time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(_field('rule-save'));
      await tester.pumpAndSettle();

      // Les deux selecteurs valident l'heure proposee par defaut : debut = fin, refuse.
      expect(
        find.text('Debut et fin ne peuvent pas etre identiques'),
        findsOneWidget,
      );
    });

    testWidgets('validation de la regle : nom, tarif, heures', (tester) async {
      final backend = deliveryBackend();
      await _pumpPage(tester, backend);
      await _openNewZone(tester);
      await openRuleDialog(tester);

      await tester.tap(_field('rule-save'));
      await tester.pump();
      expect(find.text('Nom de la regle obligatoire'), findsOneWidget);

      await tester.enterText(_field('rule-label'), 'Tarif');
      await tester.tap(find.text('Autre tarif'));
      await tester.pumpAndSettle();
      await tester.tap(_field('rule-save'));
      await tester.pump();
      expect(find.text('Tarif invalide'), findsOneWidget);

      await tester.enterText(_field('rule-fee'), '4');
      await tester.enterText(_field('rule-min-subtotal'), 'abc');
      await tester.tap(_field('rule-save'));
      await tester.pump();
      expect(find.text('Montant de panier invalide'), findsOneWidget);

      await tester.enterText(_field('rule-min-subtotal'), '');
      await tester.enterText(_field('rule-priority'), '500');
      await tester.tap(_field('rule-save'));
      await tester.pump();
      expect(find.text('Priorite entre 0 et 100'), findsOneWidget);
    });

    testWidgets('on peut modifier puis supprimer une regle', (tester) async {
      final backend = deliveryBackend(
        zones: [
          zoneJson(
            id: 7,
            name: 'Nord',
            rules: [
              {
                'id': 1,
                'label': 'Ancienne',
                'kind': 'free',
                'priority': 0,
                'is_active': true,
              },
            ],
          ),
        ],
      )..onJson('PUT', '/delivery/zones/7', zoneJson(id: 7, name: 'Nord'));
      await _pumpPage(tester, backend);
      await tester.tap(find.byKey(const ValueKey('zone-edit-7')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(_field('zone-rule-0'));
      await tester.tap(_field('zone-rule-0'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('rule-label'), 'Renommee');
      await tester.tap(_field('rule-save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Renommee'), findsWidgets);

      await tester.tap(find.byTooltip('Supprimer la regle'));
      await tester.pumpAndSettle();
      expect(_field('zone-rule-0'), findsNothing);

      await tester.ensureVisible(_field('zone-save-button'));
      await tester.tap(_field('zone-save-button'));
      await tester.pumpAndSettle();
      expect(
        backend.bodyOf(
          backend.where('PUT', '/delivery/zones/7').single,
        )['rules'],
        isEmpty,
      );
    });
  });

  group('tester une adresse', () {
    const suggestionJson = [
      {'label': 'Knez Mihailova 1, Beograd', 'lat': 44.7866, 'lng': 20.4489},
    ];

    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('delivery-test-address')));
      await tester.pumpAndSettle();
    }

    testWidgets('adresse couverte : zone, frais et delai', (tester) async {
      final backend = deliveryBackend()
        ..onJson('GET', '/delivery/geocode', suggestionJson)
        ..onJson('POST', '/delivery/check', {
          'zone_id': 7,
          'name': 'Centre',
          'fee': 0.0,
          'base_fee': 3.5,
          'free_delivery': true,
          'applied': 'rule',
          'applied_label': 'Offerte des 25',
          'estimated_minutes': 25,
          'min_order_amount': 15.0,
          'min_order_met': true,
        });
      await _pumpPage(tester, backend);
      await openDialog(tester);

      await tester.enterText(_field('coverage-address'), 'Knez Mihailova');
      await tester.enterText(_field('coverage-subtotal'), '30');
      await tester.tap(_field('coverage-search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Knez Mihailova 1, Beograd').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Zone : Centre'), findsOneWidget);
      expect(
        find.textContaining('Livraison offerte (Offerte des 25)'),
        findsOneWidget,
      );
      expect(find.textContaining('25 min'), findsOneWidget);
      final body =
          backend.bodyOf(backend.where('POST', '/delivery/check').single);
      expect(
        (body['lat'], body['lng'], body['subtotal']),
        (44.7866, 20.4489, 30.0),
      );
    });

    testWidgets('adresse hors zone', (tester) async {
      final backend = deliveryBackend()
        ..onJson('GET', '/delivery/geocode', suggestionJson)
        ..onJson(
          'POST',
          '/delivery/check',
          {
            'code': 'DELIVERY_ZONE_UNREACHABLE',
            'detail': 'Adresse hors zone de livraison',
            'field': null,
          },
          status: 422,
        );
      await _pumpPage(tester, backend);
      await openDialog(tester);

      await tester.enterText(_field('coverage-address'), 'Knez Mihailova');
      await tester.tap(_field('coverage-search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Knez Mihailova 1, Beograd').last);
      await tester.pumpAndSettle();

      expect(_field('coverage-outside'), findsOneWidget);
    });

    testWidgets('recherche d\'adresse indisponible : message clair',
        (tester) async {
      final backend = deliveryBackend()
        ..onJson(
          'GET',
          '/delivery/geocode',
          {
            'code': 'GEOCODING_NOT_CONFIGURED',
            'detail': 'Le geocodage n\'est pas configure sur ce serveur',
            'field': null,
          },
          status: 503,
        );
      await _pumpPage(tester, backend);
      await openDialog(tester);

      await tester.enterText(_field('coverage-address'), 'Knez Mihailova');
      await tester.tap(_field('coverage-search'));
      await tester.pumpAndSettle();

      expect(find.textContaining('pas configure'), findsOneWidget);
    });

    testWidgets('moins de 3 caracteres : pas d\'appel', (tester) async {
      final backend = deliveryBackend();
      await _pumpPage(tester, backend);
      await openDialog(tester);

      await tester.enterText(_field('coverage-address'), 'ab');
      await tester.tap(_field('coverage-search'));
      await tester.pump();

      expect(find.text('Saisissez au moins 3 caracteres'), findsOneWidget);
      expect(backend.where('GET', '/delivery/geocode'), isEmpty);
    });
  });
}
