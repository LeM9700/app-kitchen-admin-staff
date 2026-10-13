import 'dart:async';
import 'dart:io';

import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/delivery/presentation/delivery_map.dart';
import 'package:app_admin_staff/features/delivery/presentation/live_drivers_map.dart';
import 'package:app_admin_staff/features/driver/application/location_sharing.dart';
import 'package:app_admin_staff/features/driver/application/location_sharing_controller.dart';
import 'package:app_admin_staff/features/driver/presentation/driver_deliveries_page.dart';
import 'package:app_admin_staff/features/driver/presentation/driver_shell.dart';
import 'package:app_admin_staff/features/driver/presentation/location_sharing_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';

import 'delivery_test_support.dart' show FakeSession;

class _MockDispatchRepository extends Mock implements DispatchRepository {}

class _FakeSource implements PositionSource {
  _FakeSource([this.permission = PositionPermission.granted]);

  PositionPermission permission;
  // ignore: close_sinks
  final controller = StreamController<LocationSample>.broadcast();

  @override
  Future<PositionPermission> requestPermission() async => permission;

  @override
  Stream<LocationSample> watch() => controller.stream;

  bool get isListening => controller.hasListener;
}

LocationSample _sample([double lat = 48.86]) => LocationSample(
  lat: lat,
  lng: 2.35,
  recordedAt: DateTime.utc(2026, 10, 3, 12),
  accuracyM: 8,
);

DriverDelivery _delivery(int id, {String phase = 'en_route'}) => DriverDelivery(
  id: id,
  orderId: id + 1000,
  status: phase == 'en_route' ? 'out_for_delivery' : 'assigned',
  phase: phase,
  total: 25,
  amountDue: 0,
  paymentStatus: 'paid',
  deliveryAddress: '1 rue de la Paix',
);

const _consentedMe = DriverMe(
  id: 1,
  locationConsent: true,
  locationNoticeVersion: '2026-10-03-bg',
);

void main() {
  late _MockDispatchRepository repo;

  setUp(() {
    repo = _MockDispatchRepository();
    when(() => repo.sendLocation(any())).thenAnswer((_) async {});
  });

  DriverLocationSharer makeSharer(_FakeSource source, {int maxBuffer = 30}) {
    final sharer = DriverLocationSharer(
      repo,
      source,
      flushInterval: const Duration(
        hours: 1,
      ), // le test declenche `flush()` lui-meme
      maxBuffer: maxBuffer,
    );
    addTearDown(sharer.dispose);
    return sharer;
  }

  group('LocationSample', () {
    test('serialise en UTC et omet les valeurs inutilisables', () {
      final json = LocationSample(
        lat: 48.86,
        lng: 2.35,
        recordedAt: DateTime.utc(2026, 10, 3, 12),
        accuracyM: 8,
        speedMps: -1, // l'API refuse une vitesse negative : GPS sans vitesse
        heading: -1, // idem pour un cap inconnu
      ).toJson();
      expect(json['recorded_at'], '2026-10-03T12:00:00.000Z');
      expect(json['accuracy_m'], 8);
      expect(json.containsKey('speed_mps'), isFalse);
      expect(json.containsKey('heading'), isFalse);
    });

    test('garde un cap et une vitesse valides', () {
      final json = LocationSample(
        lat: 1,
        lng: 2,
        recordedAt: DateTime.utc(2026),
        speedMps: 5.5,
        heading: 270,
      ).toJson();
      expect(json['speed_mps'], 5.5);
      expect(json['heading'], 270);
    });
  });

  group('DriverLocationSharer', () {
    test('ne lit aucune position tant qu\'il n\'est pas active', () async {
      final source = _FakeSource();
      final sharer = makeSharer(source);

      expect(sharer.state.status, SharingStatus.idle);
      expect(source.isListening, isFalse);
    });

    test('active : lit le GPS et envoie le lot', () async {
      final source = _FakeSource();
      final sharer = makeSharer(source);

      await sharer.setActive(true);
      expect(sharer.state.status, SharingStatus.sharing);
      expect(source.isListening, isTrue);

      source.controller.add(_sample());
      source.controller.add(_sample(48.87));
      await Future<void>.delayed(Duration.zero);
      expect(sharer.state.pending, 2);

      await sharer.flush();
      final sent =
          verify(() => repo.sendLocation(captureAny())).captured.single
              as List<LocationSample>;
      expect(sent.map((s) => s.lat), [48.86, 48.87]);
      expect(sharer.state.pending, 0);
      expect(sharer.state.lastSentAt, isNotNull);
    });

    test('rien a envoyer : aucun appel reseau', () async {
      final sharer = makeSharer(_FakeSource());
      await sharer.setActive(true);

      await sharer.flush();
      verifyNever(() => repo.sendLocation(any()));
    });

    test('autorisation refusee : rien n\'est lu ni envoye', () async {
      for (final permission in [
        PositionPermission.denied,
        PositionPermission.deniedForever,
        PositionPermission.serviceDisabled,
      ]) {
        final source = _FakeSource(permission);
        final sharer = makeSharer(source);

        await sharer.setActive(true);

        expect(
          sharer.state.status,
          SharingStatus.permissionDenied,
          reason: '$permission',
        );
        expect(sharer.state.lastError, isNotNull);
        expect(source.isListening, isFalse);
      }
      verifyNever(() => repo.sendLocation(any()));
    });

    test('desactive : ferme le GPS sur-le-champ et oublie le tampon', () async {
      final source = _FakeSource();
      final sharer = makeSharer(source);
      await sharer.setActive(true);
      source.controller.add(_sample());
      await Future<void>.delayed(Duration.zero);

      await sharer.setActive(false);

      expect(source.isListening, isFalse); // plus rien n'est lu hors livraison
      expect(sharer.state.status, SharingStatus.idle);
      await sharer.flush();
      verifyNever(() => repo.sendLocation(any())); // pas d'envoi apres la fin
    });

    test('hors reseau : le tampon est garde puis renvoye en entier', () async {
      final source = _FakeSource();
      final sharer = makeSharer(source);
      await sharer.setActive(true);
      when(
        () => repo.sendLocation(any()),
      ).thenThrow(Exception('pas de reseau'));
      source.controller.add(_sample());
      source.controller.add(_sample(48.87));
      await Future<void>.delayed(Duration.zero);

      await sharer.flush();
      expect(sharer.state.pending, 2);
      expect(sharer.state.lastError, contains('Hors reseau'));
      expect(sharer.state.isSharing, isTrue);

      when(() => repo.sendLocation(any())).thenAnswer((_) async {});
      source.controller.add(_sample(48.88));
      await Future<void>.delayed(Duration.zero);
      await sharer.flush();
      final sent =
          verify(() => repo.sendLocation(captureAny())).captured.last
              as List<LocationSample>;
      expect(sent.map((s) => s.lat), [48.86, 48.87, 48.88]);
      expect(sharer.state.pending, 0);
    });

    test(
      'le tampon est plafonne : les plus anciennes positions sont abandonnees',
      () async {
        final source = _FakeSource();
        final sharer = makeSharer(source, maxBuffer: 3);
        await sharer.setActive(true);
        for (var i = 0; i < 5; i++) {
          source.controller.add(_sample(48.0 + i));
        }
        await Future<void>.delayed(Duration.zero);

        expect(sharer.state.pending, 3);
        await sharer.flush();
        final sent =
            verify(() => repo.sendLocation(captureAny())).captured.single
                as List<LocationSample>;
        expect(sent.map((s) => s.lat), [50.0, 51.0, 52.0]);
      },
    );

    test(
      'le serveur dit « plus de livraison en route » : on s\'arrete',
      () async {
        final source = _FakeSource();
        final sharer = makeSharer(source);
        await sharer.setActive(true);
        when(() => repo.sendLocation(any())).thenThrow(
          const ApiError(
            message: 'Aucune livraison en cours',
            code: 'LOCATION_NOT_ACTIVE',
            statusCode: 409,
          ),
        );
        source.controller.add(_sample());
        await Future<void>.delayed(Duration.zero);

        await sharer.flush();

        expect(sharer.state.status, SharingStatus.idle);
        expect(source.isListening, isFalse);
      },
    );

    test('accord retire cote serveur : on s\'arrete et on le dit', () async {
      final source = _FakeSource();
      final sharer = makeSharer(source);
      await sharer.setActive(true);
      when(() => repo.sendLocation(any())).thenThrow(
        const ApiError(
          message: 'Accord requis',
          code: 'LOCATION_CONSENT_REQUIRED',
          statusCode: 403,
        ),
      );
      source.controller.add(_sample());
      await Future<void>.delayed(Duration.zero);

      await sharer.flush();

      expect(sharer.state.status, SharingStatus.consentRequired);
      expect(source.isListening, isFalse);
    });

    test('une autre erreur serveur garde le tampon et reste actif', () async {
      final source = _FakeSource();
      final sharer = makeSharer(source);
      await sharer.setActive(true);
      when(() => repo.sendLocation(any())).thenThrow(
        const ApiError(
          message: 'Service indisponible',
          code: 'INTERNAL',
          statusCode: 503,
        ),
      );
      source.controller.add(_sample());
      await Future<void>.delayed(Duration.zero);

      await sharer.flush();

      expect(sharer.state.isSharing, isTrue);
      expect(sharer.state.pending, 1);
      expect(source.isListening, isTrue);
    });

    test('reactiver apres un refus redemande l\'autorisation', () async {
      final source = _FakeSource(PositionPermission.denied);
      final sharer = makeSharer(source);
      await sharer.setActive(true);
      expect(sharer.state.status, SharingStatus.permissionDenied);

      source.permission = PositionPermission.granted;
      await sharer.setActive(true);

      expect(sharer.state.status, SharingStatus.sharing);
      expect(source.isListening, isTrue);
    });
  });

  group('panneau de consentement', () {
    late _FakeSource source;

    setUp(() {
      source = _FakeSource();
      when(() => repo.grantLocationConsent(any())).thenAnswer((_) async {});
      when(() => repo.withdrawLocationConsent()).thenAnswer((_) async {});
    });

    Future<void> pump(WidgetTester tester, DriverMe me) async {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      when(() => repo.driverMe()).thenAnswer((_) async => me);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dispatchRepositoryProvider.overrideWithValue(repo),
            positionSourceProvider.overrideWithValue(source),
          ],
          child: const MaterialApp(
            home: Scaffold(body: LocationSharingPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    test('le texte annonce la duree reelle donnee par le serveur', () {
      expect(locationNoticeText(96), contains('4 jours (96 h)'));
      expect(locationNoticeText(200), contains('200 heures'));
      expect(
        locationNoticeText(96),
        contains('Rien n\'est partage en dehors d\'une livraison'),
      );
      expect(locationNoticeText(96), contains('retirer votre accord'));
    });

    testWidgets(
      'sans accord : le texte d\'information et un bouton, rien d\'autre',
      (tester) async {
        await pump(
          tester,
          const DriverMe(
            id: 1,
            locationNoticeVersion: '2026-10-03-bg',
            locationRetentionHours: 96,
          ),
        );

        expect(find.byKey(const ValueKey('location-notice')), findsOneWidget);
        expect(find.textContaining('4 jours (96 h)'), findsOneWidget);
        expect(find.byKey(const ValueKey('sharing-status')), findsNothing);

        await tester.tap(find.byKey(const ValueKey('grant-location-consent')));
        await tester.pumpAndSettle();
        // L'accord part avec la version du texte que le livreur vient de lire.
        verify(() => repo.grantLocationConsent('2026-10-03-bg')).called(1);
      },
    );

    testWidgets('avec accord : etat du partage et retrait possible', (
      tester,
    ) async {
      await pump(tester, _consentedMe);

      expect(find.byKey(const ValueKey('location-notice')), findsNothing);
      expect(
        find.textContaining('que pendant une livraison en route'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('withdraw-location-consent')));
      await tester.pumpAndSettle();
      verifyNever(() => repo.withdrawLocationConsent()); // il faut confirmer
      await tester.tap(find.byKey(const ValueKey('confirm-withdraw-consent')));
      await tester.pumpAndSettle();

      verify(() => repo.withdrawLocationConsent()).called(1);
    });

    testWidgets('annuler le retrait ne change rien', (tester) async {
      await pump(tester, _consentedMe);

      await tester.tap(find.byKey(const ValueKey('withdraw-location-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.withdrawLocationConsent());
    });
  });

  group('reglages GPS par plateforme (arriere-plan)', () {
    test(
      'Android : service de premier plan avec notification permanente et wake lock',
      () {
        final settings =
            buildLocationSettings(TargetPlatform.android) as AndroidSettings;
        final notification = settings.foregroundNotificationConfig!;
        expect(notification.notificationTitle, 'Livraison en cours');
        expect(
          notification.notificationText,
          contains('position est partagee'),
        );
        expect(notification.enableWakeLock, isTrue);
        expect(notification.setOngoing, isTrue);
        expect(settings.distanceFilter, 10);
      },
    );

    test(
      'iPhone : mises a jour en arriere-plan, indicateur visible, jamais de pause automatique',
      () {
        for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
          final settings = buildLocationSettings(platform) as AppleSettings;
          expect(
            settings.allowBackgroundLocationUpdates,
            isTrue,
            reason: '$platform',
          );
          expect(settings.showBackgroundLocationIndicator, isTrue);
          expect(settings.pauseLocationUpdatesAutomatically, isFalse);
        }
      },
    );

    test('web et bureau : reglages simples', () {
      expect(
        buildLocationSettings(TargetPlatform.android, isWeb: true),
        isNot(isA<AndroidSettings>()),
      );
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        final settings = buildLocationSettings(platform);
        expect(settings, isNot(isA<AndroidSettings>()));
        expect(settings, isNot(isA<AppleSettings>()));
      }
    });

    test(
      'le manifeste Android declare les permissions du service de premier plan',
      () {
        // Sans FOREGROUND_SERVICE_LOCATION, Android 14 refuse de demarrer le service du plugin.
        final manifest = File(
          'android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync();
        for (final permission in [
          'ACCESS_FINE_LOCATION',
          'FOREGROUND_SERVICE',
          'FOREGROUND_SERVICE_LOCATION',
          'POST_NOTIFICATIONS',
        ]) {
          expect(
            manifest,
            contains('android.permission.$permission'),
            reason: permission,
          );
        }
      },
    );

    test(
      'Info.plist autorise la localisation en arriere-plan et explique son usage',
      () {
        final plist = File('ios/Runner/Info.plist').readAsStringSync();
        expect(plist, contains('<key>UIBackgroundModes</key>'));
        expect(
          RegExp(
            r'UIBackgroundModes</key>\s*<array>[^<]*(<string>[^<]*</string>\s*)*<string>location</string>',
          ).hasMatch(plist),
          isTrue,
        );
        expect(plist, contains('NSLocationWhenInUseUsageDescription'));
        expect(plist, contains('meme ecran verrouille'));
      },
    );
  });

  group('reverification de l\'autorisation', () {
    test(
      'autorisation retiree pendant l\'arriere-plan : le flux est ferme et l\'etat le dit',
      () async {
        final source = _FakeSource();
        final sharer = makeSharer(source);
        await sharer.setActive(true);
        expect(source.isListening, isTrue);

        source.permission = PositionPermission.denied;
        await sharer.recheckPermission();

        expect(sharer.state.status, SharingStatus.permissionDenied);
        expect(sharer.state.lastError, contains('retiree'));
        expect(source.isListening, isFalse);
      },
    );

    test('autorisation toujours valide : rien ne change', () async {
      final source = _FakeSource();
      final sharer = makeSharer(source);
      await sharer.setActive(true);

      await sharer.recheckPermission();

      expect(sharer.state.status, SharingStatus.sharing);
      expect(source.isListening, isTrue);
    });

    test('sans partage actif : aucune verification', () async {
      final source = _FakeSource(PositionPermission.denied);
      final sharer = makeSharer(source);

      await sharer.recheckPermission();

      expect(sharer.state.status, SharingStatus.idle);
    });
  });

  group('coque livreur : le partage vit avec elle', () {
    late _FakeSource source;

    setUp(() {
      source = _FakeSource();
      when(() => repo.grantLocationConsent(any())).thenAnswer((_) async {});
    });

    Widget app({required String location, required Widget child}) =>
        ProviderScope(
          overrides: [
            dispatchRepositoryProvider.overrideWithValue(repo),
            positionSourceProvider.overrideWithValue(source),
            sessionControllerProvider.overrideWith(() => FakeSession('driver')),
          ],
          child: MaterialApp(
            home: DriverShell(location: location, child: child),
          ),
        );

    Future<void> pump(
      WidgetTester tester, {
      required List<DriverDelivery> deliveries,
      required DriverMe me,
    }) async {
      tester.view.physicalSize = const Size(700, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      when(() => repo.driverDeliveries()).thenAnswer((_) async => deliveries);
      when(() => repo.driverMe()).thenAnswer((_) async => me);
      await tester.pumpWidget(
        app(location: '/driver', child: const DriverDeliveriesPage()),
      );
      await tester.pumpAndSettle();
    }

    SharingState sharing(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byType(DriverShell)),
    ).read(driverLocationSharerProvider);

    testWidgets('livraison en route + accord : la position est partagee', (
      tester,
    ) async {
      await pump(tester, deliveries: [_delivery(1)], me: _consentedMe);

      expect(source.isListening, isTrue);
      expect(find.textContaining('Position partagee'), findsOneWidget);
      expect(find.textContaining('meme ecran verrouille'), findsOneWidget);
    });

    testWidgets('sans accord : jamais de lecture du GPS, meme en livraison', (
      tester,
    ) async {
      await pump(
        tester,
        deliveries: [_delivery(1)],
        me: const DriverMe(id: 1, locationNoticeVersion: '2026-10-03-bg'),
      );

      expect(source.isListening, isFalse);
      expect(
        find.byKey(const ValueKey('grant-location-consent')),
        findsOneWidget,
      );
    });

    testWidgets('accord mais aucune livraison en route : rien n\'est lu', (
      tester,
    ) async {
      await pump(
        tester,
        deliveries: [
          _delivery(1, phase: 'ready'),
          _delivery(2, phase: 'upcoming'),
        ],
        me: _consentedMe,
      );

      expect(source.isListening, isFalse);
    });

    testWidgets('changer d\'onglet ne coupe pas le partage', (tester) async {
      await pump(tester, deliveries: [_delivery(1)], me: _consentedMe);
      expect(source.isListening, isTrue);

      // Le livreur ouvre « Recap » : la page des livraisons disparait, la coque reste.
      await tester.pumpWidget(
        app(location: '/driver/recap', child: const Text('recap')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DriverDeliveriesPage), findsNothing);
      expect(source.isListening, isTrue);
    });

    testWidgets(
      'la fin de la livraison arrete le partage, sans action de l\'utilisateur',
      (tester) async {
        await pump(tester, deliveries: [_delivery(1)], me: _consentedMe);
        expect(source.isListening, isTrue);

        when(() => repo.driverDeliveries()).thenAnswer((_) async => []);
        await tester.pump(driverLocationWatchInterval);
        await tester.pumpAndSettle();

        expect(source.isListening, isFalse);
        expect(sharing(tester).status, SharingStatus.idle);
      },
    );

    testWidgets('quitter la coque (deconnexion) ferme le GPS immediatement', (
      tester,
    ) async {
      await pump(tester, deliveries: [_delivery(1)], me: _consentedMe);
      expect(source.isListening, isTrue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dispatchRepositoryProvider.overrideWithValue(repo),
            positionSourceProvider.overrideWithValue(source),
            sessionControllerProvider.overrideWith(() => FakeSession('driver')),
          ],
          child: const MaterialApp(home: Text('ecran de connexion')),
        ),
      );
      await tester.pumpAndSettle();

      expect(source.isListening, isFalse);
    });

    testWidgets(
      'retour au premier plan : autorisation reverifiee et envoi immediat',
      (tester) async {
        await pump(tester, deliveries: [_delivery(1)], me: _consentedMe);
        source.controller.add(_sample());
        await tester.pump();

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        verify(
          () => repo.sendLocation(any()),
        ).called(1); // ce qui attendait part tout de suite
        expect(source.isListening, isTrue);

        // L'autorisation a ete retiree pendant l'arriere-plan.
        source.permission = PositionPermission.denied;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        expect(sharing(tester).status, SharingStatus.permissionDenied);
        expect(source.isListening, isFalse);
      },
    );
  });

  group('carte des livreurs (comptoir)', () {
    LiveDriver driver(
      int id, {
      String state = 'en_route',
      bool signalLost = false,
      bool stale = false,
      double? lat = 48.86,
      int? age = 5,
      bool consent = true,
    }) => LiveDriver(
      driverId: id,
      driverName: 'Livreur $id',
      clockedIn: true,
      state: state,
      lat: lat,
      lng: lat == null ? null : 2.35,
      ageSeconds: age,
      signalLost: signalLost,
      stale: stale,
      sharingConsent: consent,
      deliveries: [
        LiveDelivery(
          deliveryId: id,
          orderId: id + 100,
          status: 'out_for_delivery',
          lat: 48.87,
          lng: 2.36,
        ),
      ],
    );

    Future<void> pump(WidgetTester tester, List<LiveDriver> drivers) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveDriversProvider.overrideWith((ref) async => drivers),
            deliveryTileLayerProvider.overrideWithValue(
              const SizedBox.shrink(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: LiveDriversSection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    test('libelles et couleurs d\'etat', () {
      expect(liveDriverStatusLabel(driver(1)), 'En route');
      expect(
        liveDriverStatusLabel(driver(1, stale: true)),
        'En route : position ancienne',
      );
      expect(
        liveDriverStatusLabel(driver(1, signalLost: true, age: 190)),
        'En route : signal perdu depuis 4 min',
      );
      expect(
        liveDriverStatusLabel(
          driver(1, signalLost: true, lat: null, age: null),
        ),
        'En route : aucune position recue',
      );
      expect(liveDriverStatusLabel(driver(1, state: 'free')), 'Disponible');
      expect(
        liveDriverStatusLabel(driver(1, state: 'assigned')),
        'Livraison attribuee',
      );
      expect(
        liveDriverColor(driver(1)),
        isNot(liveDriverColor(driver(1, stale: true))),
      );
      expect(
        liveDriverColor(driver(1, stale: true)),
        isNot(liveDriverColor(driver(1, signalLost: true))),
      );
    });

    test('un livreur se lit depuis l\'API, position comprise', () {
      final parsed = LiveDriver.fromJson({
        'driver_id': 3,
        'driver_name': 'Marc',
        'clocked_in': true,
        'state': 'en_route',
        'position': {'lat': 48.86, 'lng': 2.35},
        'age_seconds': 7,
        'stale': false,
        'signal_lost': false,
        'sharing_consent': true,
        'deliveries': [
          {
            'delivery_id': 1,
            'order_id': 9,
            'status': 'out_for_delivery',
            'lat': 48.87,
            'lng': 2.36,
          },
        ],
      });
      expect(parsed.hasPosition, isTrue);
      expect(parsed.deliveries.single.orderId, 9);
      expect(
        LiveDriver.fromJson({
          'driver_id': 4,
          'state': 'free',
          'position': null,
        }).hasPosition,
        isFalse,
      );
    });

    testWidgets('un repere par livreur en route', (tester) async {
      await pump(tester, [driver(1), driver(2, lat: 48.9)]);

      expect(find.text('Livreurs en route (2)'), findsOneWidget);
      expect(find.byKey(const ValueKey('live-map')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-driver-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-driver-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-signal-alert')), findsNothing);
    });

    testWidgets('signal perdu : alerte visible', (tester) async {
      await pump(tester, [driver(1, signalLost: true, age: 400)]);

      expect(find.byKey(const ValueKey('live-signal-alert')), findsOneWidget);
      expect(find.text('Signal perdu : Livreur 1'), findsOneWidget);
      expect(find.text('En route : signal perdu depuis 7 min'), findsOneWidget);
    });

    testWidgets('livreur parti sans aucune position : liste, pas de carte', (
      tester,
    ) async {
      await pump(tester, [driver(1, lat: null, age: null, signalLost: true)]);

      expect(find.byKey(const ValueKey('live-map')), findsNothing);
      expect(
        find.text('Aucune position recue pour le moment.'),
        findsOneWidget,
      );
    });

    testWidgets('personne en route : aucune section', (tester) async {
      await pump(tester, [
        driver(1, state: 'free', lat: null),
        driver(2, state: 'assigned', lat: null),
      ]);

      expect(find.textContaining('Livreurs en route'), findsNothing);
      expect(find.byKey(const ValueKey('live-map')), findsNothing);
    });

    testWidgets('on signale un livreur qui n\'a pas accepte le partage', (
      tester,
    ) async {
      await pump(tester, [
        driver(1, lat: null, age: null, signalLost: true, consent: false),
      ]);

      expect(find.textContaining('pas accepte le partage'), findsOneWidget);
    });
  });
}
