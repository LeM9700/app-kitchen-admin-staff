import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:app_admin_staff/features/driver/application/location_sharing.dart'
    show LocationSample;
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dispatchRepositoryProvider = Provider<DispatchRepository>((ref) {
  return DispatchRepository(ref.watch(apiClientProvider));
});

/// Tableau du comptoir : commandes a attribuer, livraisons en cours, livreurs.
final dispatchBoardProvider = FutureProvider.autoDispose<DispatchBoard>((
  ref,
) async {
  return ref.watch(dispatchRepositoryProvider).board();
});

final driverDeliveriesProvider =
    FutureProvider.autoDispose<List<DriverDelivery>>((ref) async {
      return ref.watch(dispatchRepositoryProvider).driverDeliveries();
    });

/// Echecs de livraison a traiter (administrateur : rembourser, retenir, relivrer).
final deliveryFailuresProvider =
    FutureProvider.autoDispose<List<DeliveryFailure>>((ref) async {
      return ref.watch(dispatchRepositoryProvider).failures();
    });

/// Profil du livreur connecte, avec son accord de partage de position.
final driverMeProvider = FutureProvider.autoDispose<DriverMe>((ref) async {
  return ref.watch(dispatchRepositoryProvider).driverMe();
});

/// Carte du comptoir : livreurs actifs et positions, actualisee par la page de dispatch.
final liveDriversProvider = FutureProvider.autoDispose<List<LiveDriver>>((
  ref,
) async {
  return ref.watch(dispatchRepositoryProvider).liveDrivers();
});

/// Commandes que le livreur peut prendre lui-meme (vide hors mode libre-service).
final driverAvailableProvider = FutureProvider.autoDispose<AvailableOrders>((
  ref,
) async {
  return ref.watch(dispatchRepositoryProvider).driverAvailable();
});

/// Reglages de livraison d'un etablissement (mode, plafond, regles d'echec).
final dispatchSettingsProvider = FutureProvider.autoDispose
    .family<EstablishmentDispatchSettings, int>((ref, establishmentId) async {
      return ref
          .watch(dispatchRepositoryProvider)
          .dispatchSettings(establishmentId);
    });

final driverRecapProvider = FutureProvider.autoDispose<DriverRecap>((
  ref,
) async {
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
        .map(
          (value) => DriverDelivery.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
  }

  /// Commandes prenables en libre-service, avec le plafond et la charge du livreur.
  Future<AvailableOrders> driverAvailable() async {
    final response = await _apiClient.get(ApiEndpoints.driverAvailable);
    return AvailableOrders.fromJson(readMap(response.data));
  }

  /// Prend une ou plusieurs commandes (tout ou rien cote serveur : plafond, commande deja prise).
  Future<void> claim(List<int> orderIds) async {
    await _apiClient.post(
      ApiEndpoints.driverClaim,
      data: {'order_ids': orderIds},
    );
  }

  /// Rend une commande prise en libre-service, tant qu'elle n'est pas partie.
  Future<void> release(int deliveryId) async {
    await _apiClient.post(ApiEndpoints.driverRelease(deliveryId));
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
  Future<void> delivered(
    int deliveryId, {
    double? cashReceived,
    String? code,
  }) async {
    await _apiClient.post(
      ApiEndpoints.driverDelivered(deliveryId),
      data: {
        if (cashReceived != null) 'cash_received': cashReceived,
        if (code != null && code.isNotEmpty) 'code': code,
      },
    );
  }

  /// Declare l'echec de la livraison. [callAttempts] : appels passes au client (exiges par le
  /// serveur pour « absent » et « injoignable »).
  Future<void> failed(
    int deliveryId, {
    required String reason,
    String? note,
    int callAttempts = 0,
  }) async {
    await _apiClient.post(
      ApiEndpoints.driverFailed(deliveryId),
      data: {
        'reason': reason,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        'call_attempts': callAttempts,
      },
    );
  }

  // ------------------------------------------------------------ GPS

  Future<DriverMe> driverMe() async {
    final response = await _apiClient.get(ApiEndpoints.driverMe);
    return DriverMe.fromJson(readMap(response.data));
  }

  /// Le livreur accepte le partage de sa position (version du texte d'information incluse).
  Future<void> grantLocationConsent(String version) async {
    await _apiClient.post(
      ApiEndpoints.driverLocationConsent,
      data: {'version': version},
    );
  }

  Future<void> withdrawLocationConsent() async {
    await _apiClient.delete(ApiEndpoints.driverLocationConsent);
  }

  /// Envoie un lot de positions (le telephone peut en accumuler hors reseau).
  Future<void> sendLocation(List<LocationSample> samples) async {
    await _apiClient.post(
      ApiEndpoints.driverLocation,
      data: {'points': samples.map((s) => s.toJson()).toList()},
    );
  }

  Future<List<LiveDriver>> liveDrivers() async {
    final response = await _apiClient.get(ApiEndpoints.deliveryLive);
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map((value) => LiveDriver.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  // ------------------------------------------------------------ echecs (admin)

  Future<List<DeliveryFailure>> failures({String status = 'pending'}) async {
    final response = await _apiClient.get(
      ApiEndpoints.deliveryFailures,
      queryParameters: {'status': status},
    );
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => DeliveryFailure.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
  }

  /// [action] : `refund`, `retain` (faute du client uniquement, [amountCents] et [note] requis)
  /// ou `redeliver`.
  Future<void> resolveFailure(
    int failureId, {
    required String action,
    int? amountCents,
    String? note,
  }) async {
    await _apiClient.post(
      ApiEndpoints.deliveryFailureResolve(failureId),
      data: {
        'action': action,
        if (amountCents != null) 'amount': amountCents,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }

  /// Conclut une livraison sans le code du client (administrateur, motif obligatoire).
  Future<void> deliverWithoutCode(int orderId, String reason) async {
    await _apiClient.post(
      ApiEndpoints.deliverWithoutCode(orderId),
      data: {'reason': reason.trim()},
    );
  }

  Future<DriverRecap> driverRecap() async {
    final response = await _apiClient.get(ApiEndpoints.driverRecap);
    return DriverRecap.fromJson(readMap(response.data));
  }

  // ------------------------------------------------------------ reglages par etablissement

  Future<EstablishmentDispatchSettings> dispatchSettings(
    int establishmentId,
  ) async {
    final response = await _apiClient.get(
      ApiEndpoints.dispatchSettings(establishmentId),
    );
    return EstablishmentDispatchSettings.fromJson(readMap(response.data));
  }

  /// N'envoie que les champs de [changes] ; [expectedVersion] protege contre une modification
  /// concurrente. Une valeur `null` pour une regle d'echec = revenir au reglage general.
  Future<EstablishmentDispatchSettings> updateDispatchSettings(
    int establishmentId, {
    required int expectedVersion,
    required Map<String, Object?> changes,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.dispatchSettings(establishmentId),
      data: {'expected_version': expectedVersion, ...changes},
    );
    return EstablishmentDispatchSettings.fromJson(readMap(response.data));
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
    this.arrivedAt,
    this.proofRequired = false,
    this.codeLocked = false,
    this.failureMinWaitMinutes = 5,
    this.failureMinCallAttempts = 1,
  });

  final int id;
  final int orderId;
  final String status;

  /// Le client doit donner son code a 4 chiffres pour que la livraison soit validee.
  final bool proofRequired;

  /// Trop d'essais de code : seul un administrateur peut conclure cette livraison.
  final bool codeLocked;
  final DateTime? arrivedAt;
  final int failureMinWaitMinutes;
  final int failureMinCallAttempts;

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
      arrivedAt: readDateTime(json['arrived_at']),
      proofRequired: readBool(json['proof_required']),
      codeLocked: readBool(json['code_locked']),
      failureMinWaitMinutes: readInt(
        json['failure_min_wait_minutes'],
        fallback: 5,
      ),
      failureMinCallAttempts: readInt(
        json['failure_min_call_attempts'],
        fallback: 1,
      ),
    );
  }
}

/// Echec de livraison declare par un livreur, a traiter par un administrateur.
class DeliveryFailure {
  const DeliveryFailure({
    required this.id,
    required this.orderId,
    required this.reason,
    required this.reasonLabel,
    required this.fault,
    required this.status,
    required this.total,
    required this.paymentStatus,
    this.driverName,
    this.note,
    this.callAttempts = 0,
    this.waitedSeconds,
    this.resolution,
    this.retainedAmount,
    this.createdAt,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
  });

  final int id;
  final int orderId;
  final String reason;
  final String reasonLabel;

  /// `customer` ou `restaurant` : aucun frais ne peut etre retenu si la faute est au restaurant.
  final String fault;
  final String status;
  final double total;
  final String paymentStatus;
  final String? driverName;
  final String? note;
  final int callAttempts;
  final int? waitedSeconds;
  final String? resolution;
  final double? retainedAmount;
  final DateTime? createdAt;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;

  bool get isPending => status == 'pending';
  bool get customerFault => fault == 'customer';

  /// Une commande qui n'est plus reglee (empreinte liberee...) ne peut pas etre relivree.
  bool get canRedeliver =>
      paymentStatus == 'paid' || paymentStatus == 'guaranteed';

  factory DeliveryFailure.fromJson(Map<String, dynamic> json) {
    return DeliveryFailure(
      id: readInt(json['id']),
      orderId: readInt(json['order_id']),
      reason: json['reason']?.toString() ?? 'other',
      reasonLabel: json['reason_label']?.toString() ?? 'Autre',
      fault: json['fault']?.toString() ?? 'customer',
      status: json['status']?.toString() ?? 'pending',
      total: readDouble(json['total']),
      paymentStatus: json['payment_status']?.toString() ?? 'pending',
      driverName: json['driver_name']?.toString(),
      note: json['note']?.toString(),
      callAttempts: readInt(json['call_attempts']),
      waitedSeconds: json['waited_seconds'] == null
          ? null
          : readInt(json['waited_seconds']),
      resolution: json['resolution']?.toString(),
      retainedAmount: json['retained_amount'] == null
          ? null
          : readDouble(json['retained_amount']),
      createdAt: readDateTime(json['created_at']),
      customerName: json['customer_name']?.toString(),
      customerPhone: json['customer_phone']?.toString(),
      deliveryAddress: json['delivery_address']?.toString(),
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
          .map(
            (value) =>
                DriverRecapItem.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
    );
  }
}

/// Le livreur connecte : etat de pointage et accord de partage de position.
class DriverMe {
  const DriverMe({
    required this.id,
    this.fullName,
    this.clockedIn = false,
    this.locationConsent = false,
    this.locationNoticeVersion = '',
    this.locationRetentionHours = 96,
    this.dispatchMode = 'counter',
    this.maxActiveDeliveries = 3,
    this.activeDeliveries = 0,
    this.remainingCapacity = 3,
  });

  /// `counter` : le comptoir attribue ; `self_assign` : le livreur prend lui-meme.
  final String dispatchMode;
  final int maxActiveDeliveries;
  final int activeDeliveries;
  final int remainingCapacity;

  bool get selfAssign => dispatchMode == 'self_assign';

  /// Duree de conservation des positions annoncee au livreur (donnee par le serveur).
  final int locationRetentionHours;

  final int id;
  final String? fullName;
  final bool clockedIn;

  /// Accord a la version courante du texte d'information : sans lui rien n'est partage.
  final bool locationConsent;

  /// Version du texte d'information que le serveur attend (renvoyee avec l'accord).
  final String locationNoticeVersion;

  factory DriverMe.fromJson(Map<String, dynamic> json) {
    return DriverMe(
      id: readInt(json['id']),
      fullName: json['full_name']?.toString(),
      clockedIn: readBool(json['clocked_in']),
      locationConsent: readBool(json['location_consent']),
      locationNoticeVersion: json['location_notice_version']?.toString() ?? '',
      locationRetentionHours: readInt(
        json['location_retention_hours'],
        fallback: 96,
      ),
      dispatchMode: json['dispatch_mode']?.toString() ?? 'counter',
      maxActiveDeliveries: readInt(json['max_active_deliveries'], fallback: 3),
      activeDeliveries: readInt(json['active_deliveries']),
      remainingCapacity: readInt(json['remaining_capacity'], fallback: 3),
    );
  }
}

/// Reponse de `driver/available` : commandes prenables et charge du livreur.
class AvailableOrders {
  const AvailableOrders({
    required this.enabled,
    required this.dispatchMode,
    required this.maxActiveDeliveries,
    required this.activeDeliveries,
    required this.remainingCapacity,
    required this.orders,
  });

  final bool enabled;
  final String dispatchMode;
  final int maxActiveDeliveries;
  final int activeDeliveries;
  final int remainingCapacity;
  final List<DispatchOrder> orders;

  factory AvailableOrders.fromJson(Map<String, dynamic> json) {
    return AvailableOrders(
      enabled: readBool(json['enabled']),
      dispatchMode: json['dispatch_mode']?.toString() ?? 'counter',
      maxActiveDeliveries: readInt(json['max_active_deliveries'], fallback: 3),
      activeDeliveries: readInt(json['active_deliveries']),
      remainingCapacity: readInt(json['remaining_capacity'], fallback: 3),
      orders: (json['orders'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => DispatchOrder.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
    );
  }
}

/// Reglages de livraison d'un etablissement (valeurs effectives, heritees comprises).
class EstablishmentDispatchSettings {
  const EstablishmentDispatchSettings({
    required this.establishmentId,
    required this.dispatchMode,
    required this.maxActiveDeliveries,
    required this.failureMinWaitMinutes,
    required this.failureMinCallAttempts,
    required this.failureRulesOverridden,
    required this.version,
  });

  final int establishmentId;
  final String dispatchMode;
  final int maxActiveDeliveries;
  final int failureMinWaitMinutes;
  final int failureMinCallAttempts;

  /// Vrai quand les regles d'echec sont propres a l'etablissement (faux = heritees du general).
  final bool failureRulesOverridden;
  final int version;

  bool get selfAssign => dispatchMode == 'self_assign';

  factory EstablishmentDispatchSettings.fromJson(Map<String, dynamic> json) {
    return EstablishmentDispatchSettings(
      establishmentId: readInt(json['establishment_id']),
      dispatchMode: json['dispatch_mode']?.toString() ?? 'counter',
      maxActiveDeliveries: readInt(json['max_active_deliveries'], fallback: 3),
      failureMinWaitMinutes: readInt(
        json['failure_min_wait_minutes'],
        fallback: 5,
      ),
      failureMinCallAttempts: readInt(
        json['failure_min_call_attempts'],
        fallback: 1,
      ),
      failureRulesOverridden: readBool(json['failure_rules_overridden']),
      version: readInt(json['version']),
    );
  }
}

class LiveDelivery {
  const LiveDelivery({
    required this.deliveryId,
    required this.orderId,
    required this.status,
    this.address,
    this.lat,
    this.lng,
  });

  final int deliveryId;
  final int orderId;
  final String status;
  final String? address;
  final double? lat;
  final double? lng;

  factory LiveDelivery.fromJson(Map<String, dynamic> json) {
    return LiveDelivery(
      deliveryId: readInt(json['delivery_id']),
      orderId: readInt(json['order_id']),
      status: json['status']?.toString() ?? 'assigned',
      address: json['address']?.toString(),
      lat: json['lat'] == null ? null : readDouble(json['lat']),
      lng: json['lng'] == null ? null : readDouble(json['lng']),
    );
  }
}

/// Un livreur sur la carte du comptoir. La position n'existe que pendant une livraison en route.
class LiveDriver {
  const LiveDriver({
    required this.driverId,
    required this.state,
    this.driverName,
    this.clockedIn = false,
    this.lat,
    this.lng,
    this.ageSeconds,
    this.stale = false,
    this.signalLost = false,
    this.sharingConsent = false,
    this.deliveries = const [],
  });

  final int driverId;
  final String? driverName;
  final bool clockedIn;

  /// `free`, `assigned` ou `en_route`.
  final String state;
  final double? lat;
  final double? lng;
  final int? ageSeconds;

  /// Position pas actualisee depuis plus d'une minute (ou jamais recue alors qu'il est parti).
  final bool stale;

  /// Plus de deux minutes sans signal en route : a verifier avec le livreur.
  final bool signalLost;
  final bool sharingConsent;
  final List<LiveDelivery> deliveries;

  bool get hasPosition => lat != null && lng != null;
  bool get isEnRoute => state == 'en_route';
  String get label => (driverName ?? 'Livreur #$driverId').trim();

  factory LiveDriver.fromJson(Map<String, dynamic> json) {
    final position = json['position'];
    final map = position is Map ? Map<String, dynamic>.from(position) : null;
    return LiveDriver(
      driverId: readInt(json['driver_id']),
      driverName: json['driver_name']?.toString(),
      clockedIn: readBool(json['clocked_in']),
      state: json['state']?.toString() ?? 'free',
      lat: map == null ? null : readDouble(map['lat']),
      lng: map == null ? null : readDouble(map['lng']),
      ageSeconds: json['age_seconds'] == null
          ? null
          : readInt(json['age_seconds']),
      stale: readBool(json['stale']),
      signalLost: readBool(json['signal_lost']),
      sharingConsent: readBool(json['sharing_consent']),
      deliveries: (json['deliveries'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => LiveDelivery.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(),
    );
  }
}
