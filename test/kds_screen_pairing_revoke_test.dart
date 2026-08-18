// app-admin-staff/test/kds_screen_pairing_revoke_test.dart
//
// Couvre le dialog "CODE D'ASSOCIATION" (countdown, expiration,
// regeneration) et l'action "RÉVOQUER LES TÉLÉCOMMANDES" ajoutés en Task 5
// à `kds_settings_section.dart`. Séparé de `kds_settings_section_test.dart`
// (Task 4) car cette responsabilité (pairing/revocation) est distincte de
// la gestion CRUD des écrans que couvre déjà ce fichier — nommé selon son
// contenu réel plutôt que juste "pairing" puisqu'il couvre aussi la
// révocation.
import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_repository.dart';
import 'package:app_admin_staff/features/kitchen/presentation/settings/kds_settings_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'le code "004281" est affiche avec le zero initial visible',
    (tester) async {
      final repository = _FakeKdsRepository()
        ..screensResult = [_screen(id: 1)]
        ..pairingCode = KdsPairingCode(
          screenId: 1,
          code: '004281',
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );
      await _pumpSection(tester, repository: repository);

      await tester.tap(find.text("CODE D'ASSOCIATION"));
      await tester.pumpAndSettle();

      expect(find.text('004 281'), findsOneWidget);
      expect(find.text('4281'), findsNothing);
      expect(find.text('4 281'), findsNothing);
    },
  );

  testWidgets(
    'le countdown affiche "Expire dans" puis "CODE EXPIRÉ" apres expiration',
    (tester) async {
      final repository = _FakeKdsRepository()
        ..screensResult = [_screen(id: 1)]
        ..pairingCode = KdsPairingCode(
          screenId: 1,
          code: '123456',
          expiresAt: DateTime.now().add(const Duration(milliseconds: 200)),
        );
      await _pumpSection(tester, repository: repository);

      await tester.tap(find.text("CODE D'ASSOCIATION"));
      await tester.pumpAndSettle();

      expect(find.textContaining('Expire dans'), findsOneWidget);
      expect(find.text('CODE EXPIRÉ'), findsNothing);

      await _advancePastExpiry(tester);

      expect(find.text('CODE EXPIRÉ'), findsOneWidget);
      expect(find.text('GÉNÉRER UN NOUVEAU CODE'), findsOneWidget);
      expect(find.textContaining('Expire dans'), findsNothing);
    },
  );

  testWidgets(
    'regenerer un code expire remplace entierement l ancien code',
    (tester) async {
      final repository = _FakeKdsRepository()
        ..screensResult = [_screen(id: 1)]
        ..pairingCode = KdsPairingCode(
          screenId: 1,
          code: '111111',
          expiresAt: DateTime.now().add(const Duration(milliseconds: 200)),
        );
      await _pumpSection(tester, repository: repository);

      await tester.tap(find.text("CODE D'ASSOCIATION"));
      await tester.pumpAndSettle();
      expect(find.text('111 111'), findsOneWidget);

      await _advancePastExpiry(tester);
      expect(find.text('CODE EXPIRÉ'), findsOneWidget);

      // Le prochain appel a generatePairingCode renverra un nouveau code.
      repository.pairingCode = KdsPairingCode(
        screenId: 1,
        code: '222222',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await tester.tap(find.text('GÉNÉRER UN NOUVEAU CODE'));
      await tester.pumpAndSettle();

      expect(find.text('222 222'), findsOneWidget);
      expect(find.text('111 111'), findsNothing);
      expect(find.text('CODE EXPIRÉ'), findsNothing);
      expect(find.textContaining('Expire dans'), findsOneWidget);
      expect(repository.generatePairingCodeCalls, 2);
    },
  );

  // Copier utilise `Clipboard.setData` (package:flutter/services.dart, pas
  // de package supplementaire). Ce SDK Flutter (3.44) ne fournit PAS de
  // handler par defaut pour le canal `SystemChannels.platform` en test
  // widget (verifie empiriquement : sans mock, le Future de
  // `Clipboard.setData` ne se resout jamais). On enregistre donc ici un
  // mock method-call handler standard (technique documentee par Flutter
  // pour tester le presse-papiers) : ca permet de tester de façon fiable
  // a la fois le SnackBar "CODE COPIÉ" ET que c'est bien le code brut sans
  // espace ("654321", pas "654 321") qui est copie.
  testWidgets(
    'le bouton COPIER copie le code brut et affiche "CODE COPIÉ"',
    (tester) async {
      final copiedTexts = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<Object?, Object?>;
            copiedTexts.add(args['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final repository = _FakeKdsRepository()
        ..screensResult = [_screen(id: 1)]
        ..pairingCode = KdsPairingCode(
          screenId: 1,
          code: '654321',
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );
      await _pumpSection(tester, repository: repository);

      await tester.tap(find.text("CODE D'ASSOCIATION"));
      await tester.pumpAndSettle();

      await tester.tap(find.text('COPIER'));
      await tester.pumpAndSettle();

      expect(copiedTexts, ['654321']);
      expect(find.text('CODE COPIÉ'), findsOneWidget);
    },
  );

  testWidgets(
    'revoquer : annuler la confirmation ne declenche pas revokeScreenSessions',
    (tester) async {
      final repository = _FakeKdsRepository()..screensResult = [_screen(id: 1)];
      await _pumpSection(tester, repository: repository);

      await tester.tap(find.text('RÉVOQUER LES TÉLÉCOMMANDES'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Révoquer toutes les télécommandes associées à '
          '« Cuisine principale » ?',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(repository.revokeScreenSessionsCalls, isEmpty);
    },
  );

  testWidgets(
    'revoquer : confirmer avec 3 sessions actives affiche le message au pluriel',
    (tester) async {
      final repository = _FakeKdsRepository()
        ..screensResult = [_screen(id: 1)]
        ..revokeResult = 3;
      await _pumpSection(tester, repository: repository);

      await tester.tap(find.text('RÉVOQUER LES TÉLÉCOMMANDES'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Révoquer'));
      await tester.pumpAndSettle();

      expect(repository.revokeScreenSessionsCalls, [1]);
      expect(find.text('3 télécommande(s) révoquée(s)'), findsOneWidget);
    },
  );

  testWidgets(
    'revoquer : confirmer sans session active affiche "Aucune télécommande active"',
    (tester) async {
      final repository = _FakeKdsRepository()
        ..screensResult = [_screen(id: 1)]
        ..revokeResult = 0;
      await _pumpSection(tester, repository: repository);

      await tester.tap(find.text('RÉVOQUER LES TÉLÉCOMMANDES'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Révoquer'));
      await tester.pumpAndSettle();

      expect(repository.revokeScreenSessionsCalls, [1]);
      expect(find.text('Aucune télécommande active'), findsOneWidget);
    },
  );

  testWidgets(
    'RÉVOQUER LES TÉLÉCOMMANDES n est pas propose au staff non-admin',
    (tester) async {
      final repository = _FakeKdsRepository()..screensResult = [_screen(id: 1)];
      await _pumpSection(tester, repository: repository, isAdmin: false);

      expect(find.text('RÉVOQUER LES TÉLÉCOMMANDES'), findsNothing);
    },
  );
}

/// `_PairingCountdown` calcule le temps restant avec `DateTime.now()` (pas
/// `clock.now()`), qui n'est pas simulé par `WidgetTester.pump(Duration)`
/// (vérifié empiriquement : `pump` avance l'horloge virtuelle des Timers
/// mais pas l'horloge système). Donc pour observer une vraie expiration en
/// test, il faut laisser du temps *réel* s'écouler via `tester.runAsync`,
/// puis `pump` d'une seconde pour déclencher le prochain tick du
/// `Timer.periodic` interne qui relit alors `DateTime.now()`.
Future<void> _advancePastExpiry(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

Future<ProviderContainer> _pumpSection(
  WidgetTester tester, {
  required _FakeKdsRepository repository,
  bool isAdmin = true,
}) async {
  final container = ProviderContainer(
    overrides: [kdsRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);

  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: KdsSettingsSection(isAdmin: isAdmin),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

KdsScreen _screen({
  required int id,
  String name = 'Cuisine principale',
  String mode = 'kitchen',
  String station = 'kitchen',
  String interactionMode = 'wall',
  int ticketsPerPage = 4,
  bool isActive = true,
}) {
  return KdsScreen(
    id: id,
    name: name,
    screenKey: 'ecran-$id',
    mode: mode,
    station: station,
    interactionMode: interactionMode,
    ticketsPerPage: ticketsPerPage,
    isActive: isActive,
  );
}

class _FakeKdsRepository extends KdsRepository {
  _FakeKdsRepository() : super(_unusedClient());

  List<KdsScreen> screensResult = const [];
  KdsPairingCode? pairingCode;
  int revokeResult = 0;
  int generatePairingCodeCalls = 0;
  final List<int> revokeScreenSessionsCalls = [];

  @override
  Future<List<KdsScreen>> listScreens({bool includeInactive = false}) async {
    return screensResult;
  }

  @override
  Future<KdsPairingCode> generatePairingCode({required int screenId}) async {
    generatePairingCodeCalls++;
    final code = pairingCode;
    if (code == null) {
      throw StateError('pairingCode not configured in fake');
    }
    return code;
  }

  @override
  Future<int> revokeScreenSessions({required int screenId}) async {
    revokeScreenSessionsCalls.add(screenId);
    return revokeResult;
  }
}

ApiClient _unusedClient() {
  return ApiClient(
    Dio(BaseOptions(baseUrl: 'http://api.test')),
    _MemoryTokenStore(),
  );
}

class _MemoryTokenStore extends TokenStore {
  _MemoryTokenStore() : super(const FlutterSecureStorage());
}
