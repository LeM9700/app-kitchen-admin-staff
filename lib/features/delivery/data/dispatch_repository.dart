import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dispatchRepositoryProvider = Provider<DispatchRepository>((ref) {
  return DispatchRepository(ref.watch(apiClientProvider));
});

/// Tableau du comptoir : commandes a attribuer, livraisons en cours, livreurs.
final dispatchBoardProvider =
    FutureProvider.autoDispose<DispatchBoard>((ref) async {
  return ref.watch(dispatchRepositoryProvider).board();
});

final driverDeliveriesProvider =
    FutureProvider.autoDispose<List<DriverDelivery>>((ref) async {
  return ref.watch(dispatchRepositoryProvider).driverDeliveries();
});

final driverRecapProvider =
    FutureProvider.autoDispose<DriverRecap>((ref) async {
  return ref.watch(dispatchRepositoryProvider).driverRecap();
});

class DispatchRepository {
  const DispatchRepository(this._apiClient);

  final ApiClient _apiClient;

  // ------------------------------------------------------------ comptoir / admin

  Future<DispatchBoard> board({int? establishmentId}) async {
    final response = await _apiClient.get(
      ApiEndpoints.dispatchBoard,
      queryParameters: {
        if (establishmentId != null) 'establishment_id': establishmentId,
      },
    );
    return DispatchBoard.fromJson(readMap(response.data));
  }

  /// Attribue une ou plusieurs commandes a un livreur (reattribue celles qui ne
  /// sont pas encore parties). Tout ou rien cote serveur.
  Future<void> assign({
    required List<int> orderIds,
    required int driverId,
  }) async {
    await _apiClient.post(
      ApiEndpoints.dispatchAssign,
      data: {'order_ids': orderIds, 'driver_id': driverId},
    );
  }

  Future<void> unassign(int orderId) async {
    await _apiClient.post(
      ApiEndpoints.dispatchUnassign,
      data: {'order_id': orderId},
    );
  }

  Future<CreatedDriver> createDriver({
    required String email,
    required String fullName,
    required int establishmentId,
    String? phone,
    String? vehicle,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.deliveryDrivers,
      data: {
        'email': email.trim(),
        'full_name': fullName.trim(),
        'establishment_id': establishmentId,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (vehicle != null && vehicle.trim().isNotEmpty)
          'vehicle': vehicle.trim(),
      },
    );
    return CreatedDriver.fromJson(readMap(response.data));
  }

  Future<DriverSummary> setDriverActive(int driverId, bool active) async {
    final response = await _apiClient.patch(
      ApiEndpoints.deliveryDriver(driverId),
      data: {'is_active': active},
    );
    return DriverSummary.fromJson(readMap(response.data));
  }

  // ------------------------------------------------------------ livreur

  Future<List<DriverDelivery>> driverDeliveries() async {
    final response = await _apiClient.get(ApiEndpoints.driverDeliveries);
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map((value) => DriverDelivery.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  Future<void> depart(List<int> deliveryIds) async {
    await _apiClient.post(
      ApiEndpoints.driverDepart,
      data: {'delivery_ids': deliveryIds},
    );
  }

  Future<void> arrived(int deliveryId) async {
    await _apiClient.post(ApiEndpoints.driverArrived(deliveryId));
  }

  /// Valide la livraison. Pour une commande a regler a la remise,
  /// [cashReceived] (especes recues) est obligatoire cote serveur.
  Future<void> delivered(int deliveryId, {double? cashReceived}) async {
    await _apiClient.post(
      ApiEndpoints.driverDelivered(deliveryId),
      data: {if (cashReceived != null) 'cash_received': cashReceived},
    );
  }

  Future<DriverRecap> driverRecap() async {
    final response = await _apiClient.get(ApiEndpoints.driverRecap);
    return DriverRecap.fromJson(readMap(response.data));
  }
}

// --------------------------------------------------------------------------- modeles

class DriverSummary {
  const DriverSummary({
    required this.id,
    required this.userId,
    required this.establishmentId,
    required this.isActive,
    this.fullName,
    this.email,
    this.phone,
    this.vehicle,
    this.clockedIn = false,
    this.onBreak = false,
    this.activeDeliveries = 0,
    this.deliveredToday = 0,
  });

  final int id;
  final int userId;
  final int establishmentId;
  final bool isActive;
  final String? fullName;
  final String? email;
  final String? phone;
  final String? vehicle;

  /// Pointe (pause comprise) : seul un livreur pointe peut recevoir une livraison.
  final bool clockedIn;
  final bool onBreak;
  final int activeDeliveries;
  final int deliveredToday;

  String get label => (fullName ?? email ?? 'Livreur #$id').trim();

  /// Peut recevoir une livraison maintenant.
  bool get assignable => isActive && clockedIn;

  factory DriverSummary.fromJson(Map<String, dynamic> json) {
    return DriverSummary(
      id: readInt(json['id']),
      userId: readInt(json['user_id']),
      establishmentId: readInt(json['establishment_id']),
      isActive: readBool(json['is_active'], fallback: true),
      fullName: json['full_name']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      vehicle: json['vehicle']?.toString(),
      clockedIn: readBool(json['clocked_in']),
      onBreak: readBool(json['on_break']),
      activeDeliveries: readInt(json['active_deliveries']),
      deliveredToday: readInt(json['delivered_today']),
    );
  }
}

class CreatedDriver {
  const CreatedDriver({required this.driver, required this.temporaryPassword});

  final DriverSummary driver;

  /// Affiche une seule fois : le livreur doit le changer a sa premiere connexion.
  final String temporaryPassword;

  factory CreatedDriver.fromJson(Map<String, dynamic> json) {
    return CreatedDriver(
      driver: DriverSummary.fromJson(json),
      temporaryPassword: json['temporary_password']?.toString() ?? '',
    );
  }
}

class DispatchOrder {
  const DispatchOrder({
    required this.orderId,
    required this.status,
    required this.total,
    required this.paymentStatus,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    this.deliveryInstructions,
    this.itemsCount = 0,
    this.createdAt,
    this.estimatedDeliveryAt,
  });

  final int orderId;
  final String status;
  final double total;
  final String paymentStatus;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  final String? deliveryInstructions;
  final int itemsCount;
  final DateTime? createdAt;
  final DateTime? estimatedDeliveryAt;

  /// Reste a encaisser a la remise (empreinte bancaire = especes).
  bool get dueOnDelivery => paymentStatus == 'guaranteed';

  factory DispatchOrder.fromJson(Map<String, dynamic> json) {
    return DispatchOrder(
      orderId: readInt(json['order_id']),
      status: json['status']?.toString() ?? '',
      total: readDouble(json['total']),
      paymentStatus: json['payment_status']?.toString() ?? 'pending',
      customerName: json['customer_name']?.toString(),
      customerPhone: json['customer_phone']?.toString(),
      deliveryAddress: json['delivery_address']?.toString(),
      deliveryInstructions: json['delivery_instructions']?.toString(),
      itemsCount: readInt(json['items_count']),
      createdAt: readDateTime(json['created_at']),
      estimatedDeliveryAt: readDateTime(json['estimated_delivery_at']),
    );
  }
}

class DispatchDelivery {
  const DispatchDelivery({
    required this.id,
    required this.status,
    required this.driverId,
    required this.order,
    this.driverName,
  });

  final int id;
  final String status;
  final int driverId;
  final String? driverName;
  final DispatchOrder order;

  /// Seule une livraison pas encore partie peut etre retiree ou reattribuee.
  bool get canReassign => status == 'assigned';

  factory DispatchDelivery.fromJson(Map<String, dynamic> json) {
    return DispatchDelivery(
      id: readInt(json['id']),
      status: json['status']?.toString() ?? 'assigned',
      driverId: readInt(json['driver_id']),
      driverName: json['driver_name']?.toString(),
      order: DispatchOrder.fromJson(readMap(json['order'])),
    );
  }
}

class DispatchBoard {
  const DispatchBoard({
    required this.dispatchEnabled,
    required this.unassigned,
    required this.deliveries,
    required this.drivers,
  });

  final bool dispatchEnabled;
  final List<DispatchOrder> unassigned;
  final List<DispatchDelivery> deliveries;
  final List<DriverSummary> drivers;

  factory DispatchBoard.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
      return (raw as List? ?? const [])
          .whereType<Map>()
          .map((value) => parse(Map<String, dynamic>.from(value)))
          .toList();
    }

    return DispatchBoard(
      dispatchEnabled: readBool(json['dispatch_enabled']),
      unassigned: list(json['unassigned'], DispatchOrder.fromJson),
      deliveries: list(json['deliveries'], DispatchDelivery.fromJson),
      drivers: list(json['drivers'], DriverSummary.fromJson),
    );
  }
}

/// Une livraison vue par le livreur : de quoi livrer, rien de plus.
class DriverDelivery {
  const DriverDelivery({
    required this.id,
    required this.orderId,
    required this.status,
    required this.phase,
    required this.total,
    required this.amountDue,
    required this.paymentStatus,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    this.deliveryLat,
    this.deliveryLng,
    this.deliveryInstructions,
    this.itemsCount = 0,
    this.estimatedDeliveryAt,
  });

  final int id;
  final int orderId;
  final String status;

  /// `upcoming` (en preparation), `ready` (peut partir), `en_route`, `arrived`.
  final String phase;
  final double total;

  /// Especes a encaisser a la remise ; 0 si deja paye.
  final double amountDue;
  final String paymentStatus;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;
  final String? deliveryInstructions;
  final int itemsCount;
  final DateTime? estimatedDeliveryAt;

  bool get isOngoing => phase == 'en_route' || phase == 'arrived';
  bool get canDepart => phase == 'ready';
  bool get hasPoint => deliveryLat != null && deliveryLng != null;

  factory DriverDelivery.fromJson(Map<String, dynamic> json) {
    return DriverDelivery(
      id: readInt(json['id']),
      orderId: readInt(json['order_id']),
      status: json['status']?.toString() ?? 'assigned',
      phase: json['phase']?.toString() ?? 'upcoming',
      total: readDouble(json['total']),
      amountDue: readDouble(json['amount_due']),
      paymentStatus: json['payment_status']?.toString() ?? 'pending',
      customerName: json['customer_name']?.toString(),
      customerPhone: json['customer_phone']?.toString(),
      deliveryAddress: json['delivery_address']?.toString(),
      deliveryLat: json['delivery_lat'] == null
          ? null
          : readDouble(json['delivery_lat']),
      deliveryLng: json['delivery_lng'] == null
          ? null
          : readDouble(json['delivery_lng']),
      deliveryInstructions: json['delivery_instructions']?.toString(),
      itemsCount: readInt(json['items_count']),
      estimatedDeliveryAt: readDateTime(json['estimated_delivery_at']),
    );
  }
}

class DriverRecapItem {
  const DriverRecapItem({
    required this.deliveryId,
    required this.orderId,
    required this.total,
    this.deliveryAddress,
    this.finishedAt,
  });

  final int deliveryId;
  final int orderId;
  final double total;
  final String? deliveryAddress;
  final DateTime? finishedAt;

  factory DriverRecapItem.fromJson(Map<String, dynamic> json) {
    return DriverRecapItem(
      deliveryId: readInt(json['delivery_id']),
      orderId: readInt(json['order_id']),
      total: readDouble(json['total']),
      deliveryAddress: json['delivery_address']?.toString(),
      finishedAt: readDateTime(json['finished_at']),
    );
  }
}

class DriverRecap {
  const DriverRecap({
    required this.deliveredCount,
    required this.runsCount,
    required this.cashCollected,
    required this.deliveries,
  });

  final int deliveredCount;
  final int runsCount;

  /// Especes encaissees aujourd'hui : a remettre au restaurant.
  final double cashCollected;
  final List<DriverRecapItem> deliveries;

  factory DriverRecap.fromJson(Map<String, dynamic> json) {
    return DriverRecap(
      deliveredCount: readInt(json['delivered_count']),
      runsCount: readInt(json['runs_count']),
      cashCollected: readDouble(json['cash_collected']),
      deliveries: (json['deliveries'] as List? ?? const [])
          .whereType<Map>()
          .map((value) => DriverRecapItem.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
    );
  }
}
