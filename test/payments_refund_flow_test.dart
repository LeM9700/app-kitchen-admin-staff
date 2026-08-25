import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/payments/presentation/payments_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentsPage — flux remboursement', () {
    testWidgets(
        'remboursement total avec raison envoie le refund attendu et confirme',
        (tester) async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        if (options.method == 'GET' && options.path == ApiEndpoints.payments) {
          return _jsonResponse(_paginatedPayments());
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.paymentSummary) {
          return _jsonResponse(_summaryJson());
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.terminalReaders) {
          return _jsonResponse({'readers': <Object?>[]});
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.connectStatus) {
          return _jsonResponse(_connectStatusJson());
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.paymentDetail(42)) {
          return _jsonResponse(_detailJson(remainingRefundableCents: 4590));
        }
        if (options.method == 'POST' &&
            options.path == ApiEndpoints.paymentRefund(42)) {
          return _jsonResponse(_refundJson(
            amount: 4590,
            reason: (options.data as Map)['reason'] as String,
          ));
        }
        throw StateError(
          'requete inattendue ${options.method} ${options.path}',
        );
      });

      await _pumpPaymentsPage(tester, api);

      await tester.tap(find.byTooltip('Rembourser'));
      await tester.pumpAndSettle();

      expect(find.text('Remboursement #42'), findsOneWidget);

      await tester.enterText(
        find.widgetWithIcon(TextField, Icons.notes_outlined),
        'Client insatisfait',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Rembourser'));
      await tester.pumpAndSettle();

      final refundRequests = requests
          .where((r) => r.path == ApiEndpoints.paymentRefund(42))
          .toList();
      expect(refundRequests, hasLength(1));
      expect(refundRequests.single.data['reason'], 'Client insatisfait');
      expect(
        (refundRequests.single.data as Map).containsKey('amount'),
        isFalse,
        reason: 'un remboursement total ne doit pas envoyer de montant',
      );
      expect(find.text('Remboursement envoye'), findsOneWidget);
    });

    testWidgets('raison vide bloque le remboursement et ne contacte pas l\'API',
        (tester) async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        if (options.method == 'GET' && options.path == ApiEndpoints.payments) {
          return _jsonResponse(_paginatedPayments());
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.paymentSummary) {
          return _jsonResponse(_summaryJson());
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.terminalReaders) {
          return _jsonResponse({'readers': <Object?>[]});
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.connectStatus) {
          return _jsonResponse(_connectStatusJson());
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.paymentDetail(42)) {
          return _jsonResponse(_detailJson(remainingRefundableCents: 4590));
        }
        throw StateError(
          'requete inattendue ${options.method} ${options.path} '
          '(un remboursement sans raison ne doit jamais poster)',
        );
      });

      await _pumpPaymentsPage(tester, api);

      await tester.tap(find.byTooltip('Rembourser'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Rembourser'));
      await tester.pumpAndSettle();

      expect(find.text('Raison obligatoire'), findsOneWidget);
      expect(
        requests.where((r) => r.method == 'POST'),
        isEmpty,
      );
    });

    testWidgets(
        'remboursement partiel superieur au montant remboursable est rejete cote client',
        (tester) async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        if (options.method == 'GET' && options.path == ApiEndpoints.payments) {
          return _jsonResponse(_paginatedPayments());
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.paymentSummary) {
          return _jsonResponse(_summaryJson());
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.terminalReaders) {
          return _jsonResponse({'readers': <Object?>[]});
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.connectStatus) {
          return _jsonResponse(_connectStatusJson());
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.paymentDetail(42)) {
          return _jsonResponse(_detailJson(remainingRefundableCents: 4590));
        }
        throw StateError(
          'requete inattendue ${options.method} ${options.path} '
          '(un montant superieur au remboursable ne doit jamais poster)',
        );
      });

      await _pumpPaymentsPage(tester, api);

      await tester.tap(find.byTooltip('Rembourser'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Partiel'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithIcon(TextField, Icons.euro_outlined),
        '100',
      );
      await tester.enterText(
        find.widgetWithIcon(TextField, Icons.notes_outlined),
        'Erreur de saisie test',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Rembourser'));
      await tester.pumpAndSettle();

      expect(find.text('Montant superieur au remboursable'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    });
  });
}

// ─── Helpers ────────────────────────────────────────────────────────────────

Future<void> _pumpPaymentsPage(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        sessionControllerProvider.overrideWith(_AdminSessionController.new),
      ],
      child: const MaterialApp(home: Scaffold(body: PaymentsPage())),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _paymentListItemJson({
  int orderId = 42,
  String status = 'paid',
  int refundedAmountCents = 0,
}) {
  return {
    'id': 1,
    'order_id': orderId,
    'provider': 'stripe',
    'provider_payment_id': 'pi_123',
    'external_reference': null,
    'amount': 45.90,
    'amount_received': 45.90,
    'currency': 'eur',
    'status': status,
    'created_by_user_id': null,
    'created_at': '2026-08-20T10:00:00Z',
    'refunded_amount_cents': refundedAmountCents,
  };
}

Map<String, dynamic> _paginatedPayments() {
  return {
    'items': [_paymentListItemJson()],
    'total': 1,
    'page': 1,
    'page_size': 50,
  };
}

Map<String, dynamic> _summaryJson() {
  return {
    'collected_amount_cents': 4590,
    'refunded_amount_cents': 0,
    'net_amount_cents': 4590,
    'payment_count': 1,
    'refund_count': 0,
    'counts_by_status': {'paid': 1},
  };
}

Map<String, dynamic> _connectStatusJson() {
  return {
    'stripe_account_id': 'acct_123',
    'details_submitted': true,
    'payouts_enabled': true,
    'charges_enabled': true,
    'onboarding_complete': true,
  };
}

Map<String, dynamic> _detailJson({required int remainingRefundableCents}) {
  return {
    'order_id': 42,
    'payment': _paymentListItemJson(),
    'paid_amount_cents': 4590,
    'refunded_amount_cents': 4590 - remainingRefundableCents,
    'remaining_refundable_cents': remainingRefundableCents,
    'refunds': <Object?>[],
    'receipt_url': null,
  };
}

Map<String, dynamic> _refundJson({
  required int amount,
  required String reason,
}) {
  return {
    'id': 9,
    'order_id': 42,
    'amount': amount,
    'status': 'succeeded',
    'created_at': '2026-08-24T12:00:00Z',
    'reason': reason,
    'failure_reason': null,
    'created_by_user_id': 1,
  };
}

ApiClient _client(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = _FakeAdapter(handler);
  return ApiClient(dio, _MemoryTokenStore());
}

ResponseBody _jsonResponse(
  Object? body, {
  int statusCode = 200,
}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _MemoryTokenStore extends TokenStore {
  _MemoryTokenStore() : super(const FlutterSecureStorage());

  @override
  Future<String?> readAccessToken() async => 'access';

  @override
  Future<String?> readRefreshToken() async => 'refresh';

  @override
  Future<String?> readTenantSlug() async => 'pizza';
}

class _AdminSessionController extends SessionController {
  @override
  Future<SessionState> build() async {
    return SessionState.authenticated(
      user: const StaffUser(
        id: 1,
        email: 'admin@test.com',
        role: 'admin',
        tenantSlug: 'pizza',
        permissions: null,
        mustChangePassword: false,
      ),
      tenantSlug: 'pizza',
      sessionId: 1,
    );
  }
}
