import 'package:app_admin_staff/app/theme/app_theme.dart';
import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_repository.dart';
import 'package:app_admin_staff/features/kitchen/data/kitchen_remote_session_store.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kds_remote_scan_flow.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_remote_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('scan payload protege ouvre le remote avec code pre-rempli', (
    tester,
  ) async {
    final repository = _FakeKdsRepository()
      ..resolveResult = KdsPairingPayloadResolution(
        screenId: 12,
        code: '482731',
        expiresAt: DateTime.utc(2026, 9, 28, 12, 30),
        screen: _kdsScreen(),
      );

    await _pumpScanHarness(
      tester,
      repository,
      rawValue: '/kitchen/remote?pair=encrypted_payload_1234567890',
    );

    await tester.tap(find.byKey(const Key('kds-remote-scan-test-trigger')));
    await tester.pumpAndSettle();

    expect(repository.resolvedPayloads, ['encrypted_payload_1234567890']);
    final field = tester.widget<TextField>(
      find.byKey(const Key('kitchen-remote-pairing-code')),
    );
    expect(field.controller?.text, '482731');
    expect(repository.pairCodes, isEmpty);
  });

  testWidgets('scan code brut ouvre le remote sans resolution backend', (
    tester,
  ) async {
    final repository = _FakeKdsRepository();

    await _pumpScanHarness(tester, repository, rawValue: '928304');

    await tester.tap(find.byKey(const Key('kds-remote-scan-test-trigger')));
    await tester.pumpAndSettle();

    expect(repository.resolvedPayloads, isEmpty);
    final field = tester.widget<TextField>(
      find.byKey(const Key('kitchen-remote-pairing-code')),
    );
    expect(field.controller?.text, '928304');
  });

  testWidgets('scan QR invalide reste sur place et affiche un message', (
    tester,
  ) async {
    final repository = _FakeKdsRepository();

    await _pumpScanHarness(tester, repository, rawValue: 'pas un qr remote');

    await tester.tap(find.byKey(const Key('kds-remote-scan-test-trigger')));
    await tester.pumpAndSettle();

    expect(repository.resolvedPayloads, isEmpty);
    expect(find.text('QR REMOTE INVALIDE'), findsOneWidget);
    expect(
      find.byKey(const Key('kds-remote-scan-test-trigger')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('kitchen-remote-pairing-code')), findsNothing);
  });

  testWidgets('scan payload expire reste sur place et affiche CODE EXPIRE', (
    tester,
  ) async {
    final repository = _FakeKdsRepository()
      ..resolveError = const BusinessException(
        message: 'expired',
        code: 'KDS_PAIRING_PAYLOAD_EXPIRED',
        statusCode: 401,
      );

    await _pumpScanHarness(
      tester,
      repository,
      rawValue: '/kitchen/remote?pair=encrypted_payload_1234567890',
    );

    await tester.tap(find.byKey(const Key('kds-remote-scan-test-trigger')));
    await tester.pumpAndSettle();

    expect(repository.resolvedPayloads, ['encrypted_payload_1234567890']);
    expect(find.text('CODE EXPIRÉ'), findsOneWidget);
    expect(
      find.byKey(const Key('kds-remote-scan-test-trigger')),
      findsOneWidget,
    );
  });
}

Future<void> _pumpScanHarness(
  WidgetTester tester,
  _FakeKdsRepository repository, {
  required String rawValue,
}) async {
  addTearDown(tester.view.reset);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => _ScanHarness(rawValue: rawValue),
      ),
      GoRoute(
        path: '/kitchen/remote',
        builder: (context, state) {
          return KitchenRemotePage(
            initialPairingCode: state.uri.queryParameters['code'],
          );
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        kdsRepositoryProvider.overrideWithValue(repository),
        kitchenRemoteSessionStoreProvider.overrideWithValue(
          _MemoryRemoteSessionStore(),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
}

class _ScanHarness extends ConsumerWidget {
  const _ScanHarness({required this.rawValue});

  final String rawValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: const Key('kds-remote-scan-test-trigger'),
          onPressed: () {
            scanAndOpenKdsRemote(
              context,
              ref,
              scanReader: (_) async => rawValue,
            );
          },
          child: const Text('Scanner'),
        ),
      ),
    );
  }
}

KdsScreen _kdsScreen() {
  return const KdsScreen(
    id: 12,
    name: 'Cuisine principale',
    screenKey: 'kitchen-main',
    mode: 'kitchen',
    station: 'kitchen',
    interactionMode: 'wall',
    ticketsPerPage: 4,
    isActive: true,
  );
}

class _FakeKdsRepository extends KdsRepository {
  _FakeKdsRepository() : super(_unusedClient());

  KdsPairingPayloadResolution? resolveResult;
  Object? resolveError;
  final resolvedPayloads = <String>[];
  final pairCodes = <String>[];

  @override
  Future<KdsPairingPayloadResolution> resolvePairingPayload({
    required String pairingPayload,
  }) async {
    resolvedPayloads.add(pairingPayload);
    final error = resolveError;
    if (error != null) {
      throw error;
    }
    final result = resolveResult;
    if (result == null) {
      throw StateError('missing resolve result');
    }
    return result;
  }

  @override
  Future<KdsPairResult> pair({
    required String code,
    String? deviceLabel,
  }) async {
    pairCodes.add(code);
    return KdsPairResult(
      sessionToken: 'paired-token',
      expiresAt: DateTime.utc(2026, 9, 28, 18),
      screen: _kdsScreen(),
    );
  }
}

class _MemoryRemoteSessionStore extends KitchenRemoteSessionStore {
  _MemoryRemoteSessionStore() : super(const FlutterSecureStorage());

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> clearToken() async {}
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
