import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_repository.dart';
import 'package:app_admin_staff/features/kitchen/domain/kds_screen_key.dart';
import 'package:app_admin_staff/features/kitchen/presentation/settings/kds_settings_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'admin voit ajouter, modifier, code association et une action de '
    'desactivation sur chaque carte',
    (tester) async {
      final repository = _FakeKdsRepository()
        ..screensResult = [
          _screen(id: 1, name: 'Cuisine principale'),
          _screen(
            id: 2,
            name: 'Comptoir',
            mode: 'counter',
            station: 'counter',
            isActive: false,
          ),
        ];
      await _pumpSection(tester, isAdmin: true, repository: repository);

      expect(find.text('+ AJOUTER UN ÉCRAN'), findsOneWidget);
      expect(find.text('MODIFIER'), findsNWidgets(2));
      expect(find.text("CODE D'ASSOCIATION"), findsNWidgets(2));
      // Ecran 1 est actif -> action "DÉSACTIVER" ; ecran 2 est inactif ->
      // reactivation "ACTIVER" (pas de confirmation necessaire).
      expect(find.text('DÉSACTIVER'), findsOneWidget);
      expect(find.text('ACTIVER'), findsOneWidget);
      expect(find.text('Cuisine principale'), findsOneWidget);
      expect(find.text('Comptoir'), findsOneWidget);
    },
  );

  testWidgets(
    'staff avec ordersPreparation voit seulement les ecrans actifs et le '
    'code association, sans ajouter/modifier/desactiver',
    (tester) async {
      final repository = _FakeKdsRepository()
        ..screensResult = [
          _screen(id: 1, name: 'Cuisine principale'),
          _screen(id: 2, name: 'Ecran inactif', isActive: false),
        ];
      await _pumpSection(tester, isAdmin: false, repository: repository);

      expect(find.text('Cuisine principale'), findsOneWidget);
      expect(find.text('Ecran inactif'), findsNothing);
      expect(find.text("CODE D'ASSOCIATION"), findsOneWidget);
      expect(find.text('+ AJOUTER UN ÉCRAN'), findsNothing);
      expect(find.text('MODIFIER'), findsNothing);
      expect(find.text('DÉSACTIVER'), findsNothing);
      expect(find.text('ACTIVER'), findsNothing);
    },
  );

  testWidgets('etat vide admin affiche le message et le bouton ajouter',
      (tester) async {
    final repository = _FakeKdsRepository()..screensResult = [];
    await _pumpSection(tester, isAdmin: true, repository: repository);

    expect(find.text('Aucun écran KDS configuré.'), findsOneWidget);
    expect(find.text('+ AJOUTER UN ÉCRAN'), findsOneWidget);
  });

  testWidgets('etat vide staff affiche le message sans bouton ajouter',
      (tester) async {
    final repository = _FakeKdsRepository()..screensResult = [];
    await _pumpSection(tester, isAdmin: false, repository: repository);

    expect(find.text('Aucun écran disponible.'), findsOneWidget);
    expect(
      find.text('Demandez à un administrateur de configurer un écran.'),
      findsOneWidget,
    );
    expect(find.text('+ AJOUTER UN ÉCRAN'), findsNothing);
  });

  testWidgets(
    'le formulaire de creation appelle createScreen avec un screenKey '
    'genere automatiquement',
    (tester) async {
      final repository = _FakeKdsRepository()..screensResult = [];
      await _pumpSection(tester, isAdmin: true, repository: repository);

      await tester.tap(find.text('+ AJOUTER UN ÉCRAN'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Écran Terrasse');
      await tester.pumpAndSettle();

      await tester.tap(find.text('CRÉER'));
      await tester.pumpAndSettle();

      expect(repository.createScreenCalls, hasLength(1));
      final call = repository.createScreenCalls.single;
      expect(call['name'], 'Écran Terrasse');
      expect(call['screen_key'], buildKdsScreenKey('Écran Terrasse'));
      expect(call['mode'], 'kitchen');
      expect(call['station'], 'kitchen');
      expect(call['interaction_mode'], 'wall');
      expect(call['tickets_per_page'], 4);
    },
  );
}

Future<ProviderContainer> _pumpSection(
  WidgetTester tester, {
  required bool isAdmin,
  required _FakeKdsRepository repository,
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
  String name = 'Ecran',
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
  final List<Map<String, dynamic>> createScreenCalls = [];
  final List<Map<String, dynamic>> updateScreenCalls = [];

  @override
  Future<List<KdsScreen>> listScreens({bool includeInactive = false}) async {
    return screensResult;
  }

  @override
  Future<KdsScreen> createScreen({
    required String name,
    required String screenKey,
    required String mode,
    required String station,
    required String interactionMode,
    required int ticketsPerPage,
  }) async {
    createScreenCalls.add({
      'name': name,
      'screen_key': screenKey,
      'mode': mode,
      'station': station,
      'interaction_mode': interactionMode,
      'tickets_per_page': ticketsPerPage,
    });
    final created = KdsScreen(
      id: 900 + createScreenCalls.length,
      name: name,
      screenKey: screenKey,
      mode: mode,
      station: station,
      interactionMode: interactionMode,
      ticketsPerPage: ticketsPerPage,
      isActive: true,
    );
    screensResult = [...screensResult, created];
    return created;
  }

  @override
  Future<KdsScreen> updateScreen({
    required int screenId,
    String? name,
    String? screenKey,
    String? mode,
    String? station,
    String? interactionMode,
    int? ticketsPerPage,
    bool? isActive,
  }) async {
    updateScreenCalls.add({
      'screen_id': screenId,
      if (name != null) 'name': name,
      if (screenKey != null) 'screen_key': screenKey,
      if (mode != null) 'mode': mode,
      if (station != null) 'station': station,
      if (interactionMode != null) 'interaction_mode': interactionMode,
      if (ticketsPerPage != null) 'tickets_per_page': ticketsPerPage,
      if (isActive != null) 'is_active': isActive,
    });
    final current = screensResult.firstWhere((s) => s.id == screenId);
    final updated = KdsScreen(
      id: current.id,
      name: name ?? current.name,
      screenKey: current.screenKey,
      mode: mode ?? current.mode,
      station: station ?? current.station,
      interactionMode: interactionMode ?? current.interactionMode,
      ticketsPerPage: ticketsPerPage ?? current.ticketsPerPage,
      isActive: isActive ?? current.isActive,
    );
    screensResult = [
      for (final s in screensResult)
        if (s.id == screenId) updated else s,
    ];
    return updated;
  }

  @override
  Future<KdsPairingCode> generatePairingCode({required int screenId}) async {
    return KdsPairingCode(
      screenId: screenId,
      code: '123456',
      expiresAt: DateTime.utc(2026, 1, 1, 12),
    );
  }

  @override
  Future<int> revokeScreenSessions({required int screenId}) async => 0;
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
