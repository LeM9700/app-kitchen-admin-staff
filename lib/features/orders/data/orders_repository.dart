import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/api/paginated.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) {
  return OrdersRepository(ref.watch(apiClientProvider));
});

final activeOrdersProvider =
    FutureProvider.autoDispose<List<OrderSummary>>((ref) {
  return ref.watch(ordersRepositoryProvider).listActiveOrders();
});

final orderDetailProvider =
    FutureProvider.autoDispose.family<OrderDetail, int>((ref, orderId) {
  return ref.watch(ordersRepositoryProvider).getOrder(orderId);
});

class OrdersRepository {
  const OrdersRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<OrderSummary>> listActiveOrders() {
    return listOrders(
      status: 'pending,queued,confirmed,preparing,ready,out_for_delivery',
      pageSize: 100,
    );
  }

  Future<List<OrderSummary>> listOrders({
    String? status,
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.orders,
      queryParameters: {
        'page': page,
        'page_size': pageSize,
        if (status != null) 'status': status,
      },
    );
    final result = PaginatedResult.fromJson(
      response.data as Map<String, dynamic>,
      OrderSummary.fromJson,
    );
    return result.items;
  }

  Future<OrderDetail> getOrder(int orderId) async {
    final response = await _apiClient.get(ApiEndpoints.orderDetail(orderId));
    return OrderDetail.fromJson(response.data as Map<String, dynamic>);
  }

  Future<OrderSummary> updateStatus(
    int orderId,
    String status, {
    String? note,
  }) async {
    final response = await _apiClient.patch(
      ApiEndpoints.orderStatus(orderId),
      data: {
        'status': status,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return OrderSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> confirmLocalTestPayment(int orderId) async {
    await _apiClient.post(
      ApiEndpoints.localTestPaymentConfirm,
      data: {'order_id': orderId},
    );
  }

  Future<OrderItem> updateItemPreparation({
    required int orderId,
    required int itemId,
    required String status,
    String? note,
  }) async {
    final response = await _apiClient.patch(
      ApiEndpoints.orderItemPreparation(orderId, itemId),
      data: {
        'status': status,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return OrderItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ManualOrderResult> createManualOrder(ManualOrderDraft draft) async {
    final response = await _apiClient.post(
      ApiEndpoints.manualOrder,
      data: draft.toJson(),
      idempotencyKey: draft.idempotencyKey,
    );
    return ManualOrderResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<String> exportCsv({
    String? status,
    String? paymentStatus,
    String? orderType,
  }) {
    return _apiClient.getText(
      ApiEndpoints.ordersExportCsv,
      queryParameters: {
        if (status != null && status.isNotEmpty) 'status': status,
        if (paymentStatus != null && paymentStatus.isNotEmpty)
          'payment_status': paymentStatus,
        if (orderType != null && orderType.isNotEmpty) 'order_type': orderType,
      },
    );
  }
}

class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.orderType,
    required this.status,
    required this.paymentStatus,
    required this.source,
    required this.total,
    required this.deliveryFee,
    this.customerEmail,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    this.tableNumber,
    this.createdAt,
  });

  final int id;
  final String? customerEmail;
  final String? customerName;
  final String? customerPhone;
  final String orderType;
  final String status;
  final String paymentStatus;
  final String source;
  final double total;
  final double deliveryFee;
  final String? deliveryAddress;
  final String? tableNumber;
  final DateTime? createdAt;

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    return OrderSummary(
      id: readInt(json['id']),
      customerEmail: json['customer_email']?.toString(),
      customerName: json['customer_name']?.toString(),
      customerPhone: json['customer_phone']?.toString(),
      orderType: json['order_type']?.toString() ?? 'delivery',
      status: json['status']?.toString() ?? 'pending',
      paymentStatus: json['payment_status']?.toString() ?? 'pending',
      source: json['source']?.toString() ?? 'customer',
      total: readDouble(json['total']),
      deliveryFee: readDouble(json['delivery_fee']),
      deliveryAddress: json['delivery_address']?.toString(),
      tableNumber: json['table_number']?.toString(),
      createdAt: readDateTime(json['created_at']),
    );
  }
}

class OrderDetail extends OrderSummary {
  const OrderDetail({
    required super.id,
    required super.orderType,
    required super.status,
    required super.paymentStatus,
    required super.source,
    required super.total,
    required super.deliveryFee,
    required this.items,
    required this.stationSummary,
    this.statusHistory = const [],
    super.customerEmail,
    super.customerName,
    super.customerPhone,
    super.deliveryAddress,
    super.tableNumber,
    super.createdAt,
  });

  final List<OrderItem> items;
  final List<OrderStationSummary> stationSummary;
  final List<OrderStatusHistory> statusHistory;

  factory OrderDetail.fromJson(Map<String, dynamic> json) {
    final summary = OrderSummary.fromJson(json);
    return OrderDetail(
      id: summary.id,
      customerEmail: summary.customerEmail,
      customerName: summary.customerName,
      customerPhone: summary.customerPhone,
      orderType: summary.orderType,
      status: summary.status,
      paymentStatus: summary.paymentStatus,
      source: summary.source,
      total: summary.total,
      deliveryFee: summary.deliveryFee,
      deliveryAddress: summary.deliveryAddress,
      tableNumber: summary.tableNumber,
      createdAt: summary.createdAt,
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => OrderItem.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
      stationSummary: (json['station_summary'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => OrderStationSummary.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList(),
      statusHistory: (json['status_history'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => OrderStatusHistory.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList(),
    );
  }
}

class OrderStatusHistory {
  const OrderStatusHistory({
    required this.status,
    required this.authority,
    this.note,
    this.createdAt,
  });

  final String status;
  final String? note;
  final String authority;
  final DateTime? createdAt;

  factory OrderStatusHistory.fromJson(Map<String, dynamic> json) {
    return OrderStatusHistory(
      status: json['status']?.toString() ?? '',
      note: json['note']?.toString(),
      authority: json['authority']?.toString() ?? 'internal',
      createdAt: readDateTime(json['created_at']),
    );
  }
}

class OrderItem {
  const OrderItem({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    required this.extras,
    required this.preparationStatus,
    required this.preparationStation,
    this.productName,
    this.variantName,
    this.preparedAt,
    this.preparedByUserId,
  });

  final int id;
  final int productId;
  final int quantity;
  final double unitPrice;
  final double total;
  final List<OrderItemExtra> extras;
  final String preparationStatus;
  final String preparationStation;
  final String? productName;
  final String? variantName;
  final DateTime? preparedAt;
  final int? preparedByUserId;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: readInt(json['id']),
      productId: readInt(json['product_id']),
      quantity: readInt(json['quantity']),
      unitPrice: readDouble(json['unit_price']),
      total: readDouble(json['total']),
      extras: (json['extras'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => OrderItemExtra.fromJson(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList(),
      preparationStatus: json['preparation_status']?.toString() ?? 'pending',
      preparationStation: json['preparation_station']?.toString() ?? 'kitchen',
      productName: json['product_name']?.toString(),
      variantName: json['variant_name']?.toString(),
      preparedAt: readDateTime(json['prepared_at']),
      preparedByUserId: json['prepared_by_user_id'] == null
          ? null
          : readInt(json['prepared_by_user_id']),
    );
  }
}

class OrderItemExtra {
  const OrderItemExtra({
    required this.extraId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  final int extraId;
  final String name;
  final int quantity;
  final double unitPrice;
  final double total;

  factory OrderItemExtra.fromJson(Map<String, dynamic> json) {
    return OrderItemExtra(
      extraId: readInt(json['extra_id']),
      name: json['name']?.toString() ?? '',
      quantity: readInt(json['quantity']),
      unitPrice: readDouble(json['unit_price']),
      total: readDouble(json['total']),
    );
  }
}

class OrderStationSummary {
  const OrderStationSummary({
    required this.station,
    required this.totalItems,
    required this.readyItems,
    required this.allReady,
  });

  final String station;
  final int totalItems;
  final int readyItems;
  final bool allReady;

  factory OrderStationSummary.fromJson(Map<String, dynamic> json) {
    return OrderStationSummary(
      station: json['station']?.toString() ?? 'kitchen',
      totalItems: readInt(json['total_items']),
      readyItems: readInt(json['ready_items']),
      allReady: readBool(json['all_ready']),
    );
  }
}

class ManualOrderResult {
  const ManualOrderResult({
    required this.order,
    required this.payment,
    required this.receipt,
  });

  final OrderDetail order;
  final PaymentListItem payment;
  final Map<String, dynamic> receipt;

  factory ManualOrderResult.fromJson(Map<String, dynamic> json) {
    return ManualOrderResult(
      order: OrderDetail.fromJson(readMap(json['order'])),
      payment: PaymentListItem.fromJson(readMap(json['payment'])),
      receipt: readMap(json['receipt']),
    );
  }
}

class ManualOrderLine {
  const ManualOrderLine({
    required this.productId,
    required this.quantity,
    this.extras = const [],
    this.variantId,
  });

  final int productId;
  final int quantity;
  final int? variantId;
  final List<ManualOrderExtraLine> extras;

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      if (variantId != null) 'variant_id': variantId,
      'quantity': quantity,
      'extras': extras.map((extra) => extra.toJson()).toList(),
    };
  }
}

class ManualOrderExtraLine {
  const ManualOrderExtraLine({
    required this.extraId,
    this.quantity = 1,
  });

  final int extraId;
  final int quantity;

  Map<String, dynamic> toJson() {
    return {
      'extra_id': extraId,
      'quantity': quantity,
    };
  }
}

class ManualOrderDraft {
  const ManualOrderDraft({
    required this.idempotencyKey,
    required this.orderType,
    required this.items,
    required this.paymentMethod,
    this.tableNumber,
    this.deliveryAddress,
    this.deliveryZoneId,
    this.customerEmail,
    this.customerName,
    this.customerPhone,
    this.externalReference,
    this.amountReceived,
    this.promoCode,
    this.loyaltyUserId,
    this.loyaltyPointsToUse,
    this.note,
  });

  final String idempotencyKey;
  final String orderType;
  final List<ManualOrderLine> items;
  final String paymentMethod;
  final String? tableNumber;
  final String? deliveryAddress;
  final int? deliveryZoneId;
  final String? customerEmail;
  final String? customerName;
  final String? customerPhone;
  final String? externalReference;
  final double? amountReceived;
  final String? promoCode;
  final int? loyaltyUserId;
  final int? loyaltyPointsToUse;
  final String? note;

  Map<String, dynamic> toJson() {
    final isDelivery = orderType == 'delivery';
    return {
      'order_type': orderType,
      'items': items.map((item) => item.toJson()).toList(),
      'delivery_fee': isDelivery ? null : 0,
      if (isDelivery && deliveryAddress != null)
        'delivery_address': deliveryAddress,
      if (isDelivery && deliveryZoneId != null)
        'delivery_zone_id': deliveryZoneId,
      if (!isDelivery) 'delivery_zone_id': null,
      if (orderType == 'dine_in' && tableNumber != null)
        'table_number': tableNumber,
      if (customerEmail != null ||
          customerName != null ||
          customerPhone != null)
        'customer': {
          if (customerEmail != null) 'email': customerEmail,
          if (customerName != null) 'full_name': customerName,
          if (customerPhone != null) 'phone': customerPhone,
        },
      'payment': {
        'method': paymentMethod,
        if (externalReference != null && externalReference!.trim().isNotEmpty)
          'external_reference': externalReference!.trim(),
        if (amountReceived != null) 'amount_received': amountReceived,
      },
      if (promoCode != null && promoCode!.trim().isNotEmpty)
        'promo_code': promoCode!.trim(),
      if (loyaltyUserId != null) 'loyalty_user_id': loyaltyUserId,
      if (loyaltyPointsToUse != null)
        'loyalty_points_to_use': loyaltyPointsToUse,
      if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
    }..removeWhere((key, value) => value == null);
  }
}
