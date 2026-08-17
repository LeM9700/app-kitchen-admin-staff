import 'dart:async';

import 'package:app_admin_staff/app/theme/app_theme.dart';
import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_actions_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_ticket_mapper.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_page.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const testKitchenProfile = KitchenScreenProfile(
  mode: KitchenScreenMode.kitchen,
  station: 'kitchen',
);

ProviderContainer createKitchenContainer(TestKitchenRepository repository) {
  return ProviderContainer(
    overrides: [
      ordersRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

Future<void> pumpKitchenPage(
  WidgetTester tester,
  ProviderContainer container, {
  Size size = const Size(1920, 1080),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const Scaffold(body: KitchenPage()),
      ),
    ),
  );

  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> pumpKitchenTicket(
  WidgetTester tester,
  KitchenTicketViewModel ticket, {
  KitchenScreenProfile profile = testKitchenProfile,
  KitchenActionsState actionsState = const KitchenActionsState(),
  VoidCallback? onStart,
  VoidCallback? onReady,
  Size size = const Size(720, 520),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: KitchenTicket(
              ticket: ticket,
              focused: false,
              profile: profile,
              actionsState: actionsState,
              onTap: () {},
              onStart: onStart,
              onReady: onReady,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

KitchenTicketViewModel testKitchenTicket({
  int id = 101,
  String status = 'preparing',
  String orderType = 'dine_in',
  String? tableNumber = '08',
  DateTime? confirmedAt,
  List<OrderItem>? items,
  String? customerName,
  String? customerEmail,
  String? customerPhone,
  double total = 18,
  KitchenScreenProfile profile = testKitchenProfile,
}) {
  return mapOrderToKitchenTicket(
    order: testKitchenOrder(
      id: id,
      status: status,
      orderType: orderType,
      tableNumber: tableNumber,
      confirmedAt: confirmedAt,
      items: items,
      customerName: customerName,
      customerEmail: customerEmail,
      customerPhone: customerPhone,
      total: total,
    ),
    profile: profile,
  );
}

OrderDetail testKitchenOrder({
  int id = 101,
  String status = 'preparing',
  String orderType = 'dine_in',
  String? tableNumber = '08',
  DateTime? createdAt,
  DateTime? confirmedAt,
  List<OrderItem>? items,
  String? customerName,
  String? customerEmail,
  String? customerPhone,
  double total = 18,
}) {
  return OrderDetail(
    id: id,
    orderType: orderType,
    status: status,
    paymentStatus: 'paid',
    source: 'customer',
    total: total,
    deliveryFee: 0,
    customerName: customerName,
    customerEmail: customerEmail,
    customerPhone: customerPhone,
    tableNumber: tableNumber,
    createdAt: createdAt ?? DateTime.utc(2026, 8, 17, 10),
    items: items ??
        [
          testKitchenItem(),
        ],
    stationSummary: const [],
    statusHistory: confirmedAt == null
        ? const []
        : [
            OrderStatusHistory(
              status: 'confirmed',
              authority: 'staff',
              createdAt: confirmedAt,
            ),
          ],
  );
}

OrderItem testKitchenItem({
  int id = 1001,
  int productId = 501,
  int quantity = 1,
  String productName = 'Margherita',
  String? variantName,
  List<OrderItemExtra> extras = const [],
  String preparationStatus = 'preparing',
  String preparationStation = 'kitchen',
  double unitPrice = 12,
  double total = 12,
}) {
  return OrderItem(
    id: id,
    productId: productId,
    quantity: quantity,
    unitPrice: unitPrice,
    total: total,
    extras: extras,
    preparationStatus: preparationStatus,
    preparationStation: preparationStation,
    productName: productName,
    variantName: variantName,
  );
}

OrderItemExtra testKitchenExtra({
  int id = 1,
  String name = 'Cheddar',
  int quantity = 1,
}) {
  return OrderItemExtra(
    extraId: id,
    name: name,
    quantity: quantity,
    unitPrice: 1,
    total: quantity.toDouble(),
  );
}

List<int> kitchenIds(int start, int end) {
  return [for (var id = start; id <= end; id++) id];
}

class TestKitchenRepository extends OrdersRepository {
  TestKitchenRepository() : super(_unusedClient());

  List<OrderSummary> summaries = const [];
  Map<int, OrderDetail> details = const {};
  Object? listError;
  Object? updateStatusError;
  Object? updateItemPreparationError;
  Completer<void>? updateStatusGate;
  Completer<void>? updateItemPreparationGate;
  final List<TestStatusUpdate> statusUpdates = [];
  final List<TestPreparationUpdate> preparationUpdates = [];
  int listCalls = 0;

  void setOrders(
    List<int> ids, {
    Map<int, String> statuses = const {},
    Map<int, String> orderTypes = const {},
    bool withTable = true,
  }) {
    summaries = [
      for (final id in ids)
        _summary(
          id,
          status: statuses[id] ?? 'preparing',
          orderType: orderTypes[id] ?? 'pickup',
          tableNumber: withTable ? '${id - 100}' : null,
        ),
    ];
    details = {
      for (final id in ids)
        id: testKitchenOrder(
          id: id,
          status: statuses[id] ?? 'preparing',
          orderType: orderTypes[id] ?? 'pickup',
          tableNumber: withTable ? '${id - 100}' : null,
          createdAt: DateTime.utc(2026, 8, 17, 10, id - 100),
          confirmedAt: statuses[id] == 'pending' || statuses[id] == 'queued'
              ? null
              : DateTime.utc(2026, 8, 17, 10, id - 100),
          items: [
            testKitchenItem(
              id: id * 10,
              productName: 'Pizza $id',
              preparationStatus:
                  statuses[id] == 'ready' ? 'ready' : 'preparing',
            ),
          ],
        ),
    };
  }

  @override
  Future<List<OrderSummary>> listActiveOrders() async {
    listCalls++;
    final error = listError;
    if (error != null) {
      throw error;
    }

    return summaries;
  }

  @override
  Future<OrderDetail> getOrder(int orderId) async {
    final detail = details[orderId];
    if (detail == null) {
      throw StateError('Order $orderId not found');
    }

    return detail;
  }

  @override
  Future<OrderSummary> updateStatus(
    int orderId,
    String status, {
    String? note,
  }) async {
    statusUpdates.add(
      TestStatusUpdate(orderId: orderId, status: status, note: note),
    );
    final error = updateStatusError;
    if (error != null) {
      throw error;
    }

    final gate = updateStatusGate;
    if (gate != null) {
      await gate.future;
    }

    final detail = details[orderId];
    if (detail != null) {
      details = {
        ...details,
        orderId: _copyOrderDetail(detail, status: status),
      };
    }
    summaries = [
      for (final summary in summaries)
        summary.id == orderId ? _copySummary(summary, status: status) : summary,
    ];

    return summaries.firstWhere(
      (summary) => summary.id == orderId,
      orElse: () => _summary(
        orderId,
        status: status,
        orderType: detail?.orderType ?? 'pickup',
        tableNumber: detail?.tableNumber,
      ),
    );
  }

  @override
  Future<OrderItem> updateItemPreparation({
    required int orderId,
    required int itemId,
    required String status,
    String? note,
  }) async {
    preparationUpdates.add(
      TestPreparationUpdate(
        orderId: orderId,
        itemId: itemId,
        status: status,
        note: note,
      ),
    );
    final error = updateItemPreparationError;
    if (error != null) {
      throw error;
    }

    final gate = updateItemPreparationGate;
    if (gate != null) {
      await gate.future;
    }

    final detail = details[orderId];
    if (detail == null) {
      throw StateError('Order $orderId not found');
    }

    late OrderItem updatedItem;
    final updatedItems = [
      for (final item in detail.items)
        if (item.id == itemId)
          updatedItem = _copyOrderItem(item, preparationStatus: status)
        else
          item,
    ];
    details = {
      ...details,
      orderId: _copyOrderDetail(detail, items: updatedItems),
    };

    return updatedItem;
  }
}

class TestStatusUpdate {
  const TestStatusUpdate({
    required this.orderId,
    required this.status,
    this.note,
  });

  final int orderId;
  final String status;
  final String? note;
}

class TestPreparationUpdate {
  const TestPreparationUpdate({
    required this.orderId,
    required this.itemId,
    required this.status,
    this.note,
  });

  final int orderId;
  final int itemId;
  final String status;
  final String? note;
}

OrderSummary _summary(
  int id, {
  required String status,
  required String orderType,
  String? tableNumber,
}) {
  return OrderSummary(
    id: id,
    orderType: orderType,
    status: status,
    paymentStatus: 'paid',
    source: 'customer',
    total: 18,
    deliveryFee: 0,
    tableNumber: tableNumber,
    createdAt: DateTime.utc(2026, 8, 17, 10, id - 100),
  );
}

OrderSummary _copySummary(
  OrderSummary order, {
  String? status,
}) {
  return OrderSummary(
    id: order.id,
    customerEmail: order.customerEmail,
    customerName: order.customerName,
    customerPhone: order.customerPhone,
    orderType: order.orderType,
    status: status ?? order.status,
    paymentStatus: order.paymentStatus,
    source: order.source,
    total: order.total,
    deliveryFee: order.deliveryFee,
    deliveryAddress: order.deliveryAddress,
    tableNumber: order.tableNumber,
    createdAt: order.createdAt,
  );
}

OrderDetail _copyOrderDetail(
  OrderDetail order, {
  String? status,
  List<OrderItem>? items,
}) {
  return OrderDetail(
    id: order.id,
    customerEmail: order.customerEmail,
    customerName: order.customerName,
    customerPhone: order.customerPhone,
    orderType: order.orderType,
    status: status ?? order.status,
    paymentStatus: order.paymentStatus,
    source: order.source,
    total: order.total,
    deliveryFee: order.deliveryFee,
    deliveryAddress: order.deliveryAddress,
    tableNumber: order.tableNumber,
    createdAt: order.createdAt,
    items: items ?? order.items,
    stationSummary: order.stationSummary,
    statusHistory: order.statusHistory,
  );
}

OrderItem _copyOrderItem(
  OrderItem item, {
  String? preparationStatus,
}) {
  return OrderItem(
    id: item.id,
    productId: item.productId,
    quantity: item.quantity,
    unitPrice: item.unitPrice,
    total: item.total,
    extras: item.extras,
    preparationStatus: preparationStatus ?? item.preparationStatus,
    preparationStation: item.preparationStation,
    productName: item.productName,
    variantName: item.variantName,
    preparedAt: item.preparedAt,
    preparedByUserId: item.preparedByUserId,
  );
}

ApiClient _unusedClient() {
  return ApiClient(
    Dio(BaseOptions(baseUrl: 'http://api.test')),
    const TokenStore(FlutterSecureStorage()),
  );
}
