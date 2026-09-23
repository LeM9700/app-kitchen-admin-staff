import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/orders/presentation/orders_board_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('service detail does not expose KDS prepared action', (
    tester,
  ) async {
    await _pumpService(
      tester,
      repository: _FakeOrdersRepository(
        detail: _detail(
          stationSummary: const [
            OrderStationSummary(
              station: 'kitchen',
              totalItems: 2,
              readyItems: 2,
              allReady: true,
            ),
          ],
        ),
      ),
      orders: [_summary()],
    );

    await tester.tap(find.text('Commande #1'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Commande preparee'), findsNothing);
    expect(find.text('Preparation terminee'), findsOneWidget);
    expect(find.text('Imprimer'), findsNothing);
    expect(find.byTooltip('Imprimer'), findsOneWidget);
  });

  testWidgets('network failure queues service status action offline', (
    tester,
  ) async {
    final repository = _FakeOrdersRepository(
      updateError: const NetworkException(message: 'offline'),
    );

    await _pumpService(
      tester,
      repository: repository,
      orders: [_summary(orderType: 'delivery')],
      overrides: [syncQueueProvider.overrideWith(_TestSyncQueue.new)],
    );

    await tester.tap(find.text('DEPART LIVRAISON'));
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OrdersBoardPage)),
      listen: false,
    );
    final queued = container.read(syncQueueProvider);

    expect(repository.statusUpdates, isEmpty);
    expect(queued, hasLength(1));
    expect(queued.single.feature, 'orders');
    expect(queued.single.payload['status'], 'out_for_delivery');
    expect(find.text('Action mise en file offline'), findsOneWidget);
  });

  testWidgets('service board has no layout exceptions across target widths', (
    tester,
  ) async {
    for (final width in [390.0, 768.0, 1024.0, 1280.0, 1440.0, 1920.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;

      await _pumpService(
        tester,
        repository: _FakeOrdersRepository(),
        orders: [
          _summary(id: 1, orderType: 'dine_in'),
          _summary(id: 2, orderType: 'pickup'),
          _summary(id: 3, orderType: 'delivery'),
          _summary(
            id: 4,
            orderType: 'delivery',
            status: 'out_for_delivery',
          ),
        ],
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'No overflow or layout exception at ${width.toInt()} px.',
      );
    }
  });
}

Future<void> _pumpService(
  WidgetTester tester, {
  required _FakeOrdersRepository repository,
  required List<OrderSummary> orders,
  List<Override> overrides = const [],
}) async {
  addTearDown(tester.view.reset);
  tester.view.physicalSize = const Size(1024, 768);
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        availableEstablishmentsProvider.overrideWith(
          (ref) async => const [
            Establishment(
              id: 1,
              name: 'KOD MOME',
              timezone: 'Europe/Paris',
              isActive: true,
            ),
          ],
        ),
        activeOrdersProvider.overrideWith((ref) async => orders),
        ordersRepositoryProvider.overrideWith((ref) => repository),
        ...overrides,
      ],
      child: const MaterialApp(home: Scaffold(body: OrdersBoardPage())),
    ),
  );
  await tester.pump();
  await tester.pump();
}

OrderSummary _summary({
  int id = 1,
  String orderType = 'dine_in',
  String status = 'ready',
  DateTime? createdAt,
}) {
  return OrderSummary(
    id: id,
    orderType: orderType,
    status: status,
    paymentStatus: 'paid',
    source: 'customer',
    total: 24,
    deliveryFee: orderType == 'delivery' ? 4 : 0,
    tableNumber: orderType == 'dine_in' ? '12' : null,
    customerName: 'Malik B.',
    establishmentId: 1,
    createdAt: createdAt ?? DateTime.now().subtract(const Duration(minutes: 8)),
  );
}

OrderDetail _detail({
  List<OrderStationSummary> stationSummary = const [],
}) {
  final summary = _summary();
  return OrderDetail(
    id: summary.id,
    orderType: summary.orderType,
    status: summary.status,
    paymentStatus: summary.paymentStatus,
    source: summary.source,
    total: summary.total,
    deliveryFee: summary.deliveryFee,
    customerName: summary.customerName,
    establishmentId: summary.establishmentId,
    tableNumber: summary.tableNumber,
    createdAt: summary.createdAt,
    stationSummary: stationSummary,
    statusHistory: [
      OrderStatusHistory(
        status: 'ready',
        authority: 'system',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    ],
    items: const [
      OrderItem(
        id: 11,
        productId: 101,
        quantity: 2,
        unitPrice: 12,
        total: 24,
        extras: [],
        preparationStatus: 'ready',
        preparationStation: 'kitchen',
        productName: 'Margherita',
      ),
    ],
  );
}

class _FakeOrdersRepository implements OrdersRepository {
  _FakeOrdersRepository({
    OrderDetail? detail,
    this.updateError,
  }) : detail = detail ?? _detail();

  final OrderDetail detail;
  final Object? updateError;
  final statusUpdates = <String>[];

  @override
  Future<List<OrderSummary>> listActiveOrders({int? establishmentId}) async {
    return const [];
  }

  @override
  Future<List<OrderSummary>> listOrders({
    String? status,
    int? establishmentId,
    int page = 1,
    int pageSize = 50,
  }) async {
    return const [];
  }

  @override
  Future<OrderDetail> getOrder(int orderId) async => detail;

  @override
  Future<OrderSummary> updateStatus(
    int orderId,
    String status, {
    String? note,
  }) async {
    final error = updateError;
    if (error != null) {
      throw error;
    }
    statusUpdates.add(status);
    return _summary(id: orderId, status: status);
  }

  @override
  Future<void> confirmLocalTestPayment(int orderId) async {}

  @override
  Future<OrderItem> updateItemPreparation({
    required int orderId,
    required int itemId,
    required String status,
    String? note,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<OrderDetail> updateStationPreparation({
    required int orderId,
    required String station,
    required String status,
    String? note,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ManualOrderResult> createManualOrder(ManualOrderDraft draft) {
    throw UnimplementedError();
  }

  @override
  Future<String> exportCsv({
    String? status,
    String? paymentStatus,
    String? orderType,
  }) async {
    return 'id,status\n1,ready';
  }
}

class _TestSyncQueue extends SyncQueue {
  @override
  List<QueuedAction> build() => const [];

  @override
  void add({
    required String feature,
    required String label,
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
    String? lastError,
  }) {
    state = [
      QueuedAction(
        id: 'queued-${state.length + 1}',
        feature: feature,
        label: label,
        endpoint: endpoint,
        method: method,
        payload: payload,
        createdAt: DateTime(2026, 9, 23, 12),
        tenantSlug: 'pizza',
        userId: 1,
        sessionId: 1,
        idempotencyKey: idempotencyKey,
        lastError: lastError,
      ),
      ...state,
    ];
  }
}

class _TestSessionController extends SessionController {
  @override
  Future<SessionState> build() async {
    return const SessionState.authenticated(
      user: StaffUser(
        id: 1,
        email: 'staff@test.local',
        role: 'staff',
        tenantSlug: 'pizza',
        permissions: {'orders:read'},
        mustChangePassword: false,
      ),
      tenantSlug: 'pizza',
      sessionId: 1,
    );
  }
}
