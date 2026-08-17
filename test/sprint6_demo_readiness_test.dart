import 'dart:async';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_page.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/orders/presentation/orders_board_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('service order status action is single-flight while pending',
      (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;

    final repository = _SlowStatusRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: OrdersBoardPage())),
      ),
    );
    await tester.pumpAndSettle();

    final confirmButton = find.widgetWithText(FilledButton, 'Confirmee');
    expect(confirmButton, findsOneWidget);

    await tester.tap(confirmButton);
    await repository.statusStarted.future;
    await tester.pump();
    await tester.tap(confirmButton);

    expect(repository.statusCalls, 1);
    repository.releaseStatus.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(repository.statusCalls, 1);
  });

  testWidgets('kitchen board is read-only for LOT 4', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;

    final repository = _ReadOnlyKitchenRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ordersRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: KitchenPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('À COMMENCER'), findsOneWidget);
    expect(find.text('1 × MARGHERITA'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pret'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'En prep'), findsNothing);
  });
}

class _SlowStatusRepository extends OrdersRepository {
  _SlowStatusRepository() : super(_unusedClient());

  final statusStarted = Completer<void>();
  final releaseStatus = Completer<void>();
  int statusCalls = 0;

  @override
  Future<List<OrderSummary>> listActiveOrders() async {
    return const [
      OrderSummary(
        id: 10,
        orderType: 'pickup',
        status: 'pending',
        paymentStatus: 'paid',
        source: 'customer',
        total: 18,
        deliveryFee: 0,
      ),
    ];
  }

  @override
  Future<OrderSummary> updateStatus(
    int orderId,
    String status, {
    String? note,
  }) async {
    statusCalls++;
    if (!statusStarted.isCompleted) {
      statusStarted.complete();
    }
    await releaseStatus.future;
    return OrderSummary(
      id: orderId,
      orderType: 'pickup',
      status: status,
      paymentStatus: 'paid',
      source: 'customer',
      total: 18,
      deliveryFee: 0,
    );
  }
}

class _ReadOnlyKitchenRepository extends OrdersRepository {
  _ReadOnlyKitchenRepository() : super(_unusedClient());

  String orderStatus = 'confirmed';
  String itemStatus = 'pending';

  @override
  Future<List<OrderSummary>> listActiveOrders() async {
    return [
      OrderSummary(
        id: 20,
        orderType: 'dine_in',
        status: orderStatus,
        paymentStatus: 'paid',
        source: 'manual',
        total: 14,
        deliveryFee: 0,
        tableNumber: '7',
      ),
    ];
  }

  @override
  Future<OrderDetail> getOrder(int orderId) async {
    return OrderDetail(
      id: orderId,
      orderType: 'dine_in',
      status: orderStatus,
      paymentStatus: 'paid',
      source: 'manual',
      total: 14,
      deliveryFee: 0,
      tableNumber: '7',
      items: [
        OrderItem(
          id: 201,
          productId: 3,
          quantity: 1,
          unitPrice: 14,
          total: 14,
          extras: const [],
          preparationStatus: itemStatus,
          preparationStation: 'kitchen',
          productName: 'Margherita',
        ),
      ],
      stationSummary: const [
        OrderStationSummary(
          station: 'kitchen',
          totalItems: 1,
          readyItems: 0,
          allReady: false,
        ),
      ],
    );
  }
}

ApiClient _unusedClient() {
  return ApiClient(
    Dio(BaseOptions(baseUrl: 'http://api.test')),
    const TokenStore(FlutterSecureStorage()),
  );
}
