import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Repository ───────────────────────────────────────────────────────────────

final haccpRepositoryProvider = Provider<HaccpRepository>((ref) {
  return HaccpRepository(ref.watch(apiClientProvider));
});

class HaccpRepository {
  const HaccpRepository(this._api);

  final ApiClient _api;

  // ── Status (gate bloquant) ─────────────────────────────────────────────────

  /// Récupère l'état HACCP du jour : avancement sessions ouverture/fermeture,
  /// can_open, can_close, nombre de NC ouvertes.
  Future<HaccpStatus> getStatusToday() async {
    final response = await _api.get(ApiEndpoints.haccpStatusToday);
    return HaccpStatus.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Sessions ───────────────────────────────────────────────────────────────

  /// Démarre (ou récupère) la session du jour pour [sessionType] (opening|closing).
  Future<HaccpCheckSession> startSession(String sessionType) async {
    final response = await _api.post(ApiEndpoints.haccpSessions, data: {
      'session_type': sessionType,
    });
    return HaccpCheckSession.fromJson(response.data as Map<String, dynamic>);
  }

  /// Récupère les sessions du jour.
  Future<List<HaccpCheckSession>> getTodaySessions() async {
    final response = await _api.get(ApiEndpoints.haccpSessionsToday);
    return (response.data as List)
        .map((e) => HaccpCheckSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Valide une session (débloque le gate ouverture/fermeture).
  /// [force] = true si on veut valider même avec des éléments manquants.
  Future<HaccpCheckSession> completeSession(
    int sessionId, {
    String? notes,
    bool force = false,
  }) async {
    final response = await _api.patch(
      ApiEndpoints.haccpSessionComplete(sessionId),
      data: {
        if (notes != null) 'notes': notes,
        'force': force,
      },
    );
    return HaccpCheckSession.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Equipment ─────────────────────────────────────────────────────────────

  Future<List<HaccpEquipment>> listEquipment({bool activeOnly = true}) async {
    final response = await _api.get(
      ApiEndpoints.haccpEquipment,
      queryParameters: {'active_only': activeOnly},
    );
    return (response.data as List)
        .map((e) => HaccpEquipment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<HaccpEquipment> createEquipment(Map<String, dynamic> body) async {
    final response = await _api.post(ApiEndpoints.haccpEquipment, data: body);
    return HaccpEquipment.fromJson(response.data as Map<String, dynamic>);
  }

  Future<HaccpEquipment> updateEquipment(
      int id, Map<String, dynamic> body) async {
    final response =
        await _api.patch(ApiEndpoints.haccpEquipmentItem(id), data: body);
    return HaccpEquipment.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Temperature Logs ───────────────────────────────────────────────────────

  Future<HaccpTemperatureLog> logTemperature(
    int sessionId, {
    required int equipmentId,
    required double measuredTemp,
    String? correctiveAction,
  }) async {
    final response = await _api.post(
      ApiEndpoints.haccpSessionTemperatures(sessionId),
      data: {
        'equipment_id': equipmentId,
        'measured_temp': measuredTemp,
        if (correctiveAction != null) 'corrective_action': correctiveAction,
      },
    );
    return HaccpTemperatureLog.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<HaccpTemperatureLog>> listTemperatures(int sessionId) async {
    final response =
        await _api.get(ApiEndpoints.haccpSessionTemperatures(sessionId));
    return (response.data as List)
        .map((e) => HaccpTemperatureLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── DLC Checks ─────────────────────────────────────────────────────────────

  Future<HaccpDlcCheck> logDlcCheck(
    int sessionId,
    Map<String, dynamic> body,
  ) async {
    final response =
        await _api.post(ApiEndpoints.haccpSessionDlc(sessionId), data: body);
    return HaccpDlcCheck.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<HaccpDlcCheck>> listDlcChecks(int sessionId) async {
    final response = await _api.get(ApiEndpoints.haccpSessionDlc(sessionId));
    return (response.data as List)
        .map((e) => HaccpDlcCheck.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Toutes les vérifications DLC du tenant, hors contexte session -- pour
  /// l'onglet Stock. [ingredientId]/[isCompliant] filtrent si fournis.
  Future<List<HaccpDlcCheck>> listAllDlcChecks({
    int? ingredientId,
    bool? isCompliant,
  }) async {
    final response = await _api.get(
      ApiEndpoints.haccpDlc,
      queryParameters: {
        if (ingredientId != null) 'ingredient_id': ingredientId,
        if (isCompliant != null) 'is_compliant': isCompliant,
      },
    );
    return (response.data as List)
        .map((e) => HaccpDlcCheck.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Crée une vérification DLC hors session (onglet Stock).
  Future<HaccpDlcCheck> createStandaloneDlcCheck(
      Map<String, dynamic> body) async {
    final response = await _api.post(ApiEndpoints.haccpDlc, data: body);
    return HaccpDlcCheck.fromJson(response.data as Map<String, dynamic>);
  }

  Future<HaccpDlcCheck> updateDlcCheck(
      int id, Map<String, dynamic> body) async {
    final response =
        await _api.patch(ApiEndpoints.haccpDlcItem(id), data: body);
    return HaccpDlcCheck.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteDlcCheck(int id) async {
    await _api.delete(ApiEndpoints.haccpDlcItem(id));
  }

  // ── Cleaning Tasks & Logs ─────────────────────────────────────────────────

  Future<List<HaccpCleaningTask>> listCleaningTasks({
    String? sessionType,
  }) async {
    final response = await _api.get(
      ApiEndpoints.haccpCleaningTasks,
      queryParameters: {
        if (sessionType != null) 'session_type': sessionType,
      },
    );
    return (response.data as List)
        .map((e) => HaccpCleaningTask.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<HaccpCleaningTask> createCleaningTask(
      Map<String, dynamic> body) async {
    final response =
        await _api.post(ApiEndpoints.haccpCleaningTasks, data: body);
    return HaccpCleaningTask.fromJson(response.data as Map<String, dynamic>);
  }

  Future<HaccpCleaningTask> updateCleaningTask(
      int id, Map<String, dynamic> body) async {
    final response =
        await _api.patch(ApiEndpoints.haccpCleaningTask(id), data: body);
    return HaccpCleaningTask.fromJson(response.data as Map<String, dynamic>);
  }

  Future<HaccpCleaningLog> logCleaning(
    int sessionId, {
    required int taskId,
    String? notes,
    bool isCompliant = true,
  }) async {
    final response = await _api.post(
      ApiEndpoints.haccpSessionCleaning(sessionId),
      data: {
        'task_id': taskId,
        if (notes != null) 'notes': notes,
        'is_compliant': isCompliant,
      },
    );
    return HaccpCleaningLog.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<HaccpCleaningLog>> listCleaningLogs(int sessionId) async {
    final response =
        await _api.get(ApiEndpoints.haccpSessionCleaning(sessionId));
    return (response.data as List)
        .map((e) => HaccpCleaningLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Frying Oil ────────────────────────────────────────────────────────────

  Future<HaccpFryingOilLog> logFryingOil(
    int sessionId, {
    required double polarityPercent,
    String? color,
    String? odor,
    String? correctiveAction,
  }) async {
    final response = await _api.post(
      ApiEndpoints.haccpSessionOil(sessionId),
      data: {
        'polarity_percent': polarityPercent,
        if (color != null) 'color': color,
        if (odor != null) 'odor': odor,
        if (correctiveAction != null) 'corrective_action': correctiveAction,
      },
    );
    return HaccpFryingOilLog.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<HaccpFryingOilLog>> listFryingOilLogs(int sessionId) async {
    final response = await _api.get(ApiEndpoints.haccpSessionOil(sessionId));
    return (response.data as List)
        .map((e) => HaccpFryingOilLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Reception Controls ────────────────────────────────────────────────────

  Future<HaccpReceptionControl> createReceptionControl(
      Map<String, dynamic> body) async {
    final response =
        await _api.post(ApiEndpoints.haccpReceptionControls, data: body);
    return HaccpReceptionControl.fromJson(
        response.data as Map<String, dynamic>);
  }

  Future<List<HaccpReceptionControl>> listReceptionControls({
    DateTime? date,
  }) async {
    final response = await _api.get(
      ApiEndpoints.haccpReceptionControls,
      queryParameters: {
        if (date != null)
          'date':
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      },
    );
    return (response.data as List)
        .map((e) => HaccpReceptionControl.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Cooling Logs ──────────────────────────────────────────────────────────

  Future<HaccpCoolingLog> startCooling(Map<String, dynamic> body) async {
    final response = await _api.post(ApiEndpoints.haccpCooling, data: body);
    return HaccpCoolingLog.fromJson(response.data as Map<String, dynamic>);
  }

  Future<HaccpCoolingLog> completeCooling(
    int id, {
    required double tempFinal,
    String? correctiveAction,
  }) async {
    final response = await _api.patch(
      ApiEndpoints.haccpCoolingItem(id),
      data: {
        'temp_final': tempFinal,
        if (correctiveAction != null) 'corrective_action': correctiveAction,
      },
    );
    return HaccpCoolingLog.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<HaccpCoolingLog>> listCoolingLogs(
      {bool activeOnly = false}) async {
    final response = await _api.get(
      ApiEndpoints.haccpCooling,
      queryParameters: {if (activeOnly) 'active_only': true},
    );
    return (response.data as List)
        .map((e) => HaccpCoolingLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Training Records ──────────────────────────────────────────────────────

  Future<HaccpTrainingRecord> createTrainingRecord(
      Map<String, dynamic> body) async {
    final response = await _api.post(ApiEndpoints.haccpTraining, data: body);
    return HaccpTrainingRecord.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<HaccpTrainingRecord>> listTrainingRecords({
    int? userId,
  }) async {
    final response = await _api.get(
      ApiEndpoints.haccpTraining,
      queryParameters: {if (userId != null) 'user_id': userId},
    );
    return (response.data as List)
        .map((e) => HaccpTrainingRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Non-Conformities ───────────────────────────────────────────────────────

  Future<List<HaccpNonConformity>> listNonConformities({
    String? status,
  }) async {
    final response = await _api.get(
      ApiEndpoints.haccpNonConformities,
      queryParameters: {if (status != null) 'status': status},
    );
    return (response.data as List)
        .map((e) => HaccpNonConformity.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<HaccpNonConformity> updateNonConformity(
    int id, {
    String? correctiveAction,
    String? status,
  }) async {
    final response = await _api.patch(
      ApiEndpoints.haccpNonConformity(id),
      data: {
        if (correctiveAction != null) 'corrective_action': correctiveAction,
        if (status != null) 'status': status,
      },
    );
    return HaccpNonConformity.fromJson(response.data as Map<String, dynamic>);
  }
}

// ─── Providers Riverpod ───────────────────────────────────────────────────────

/// État HACCP du jour — rechargeable manuellement.
final haccpStatusProvider = FutureProvider.autoDispose<HaccpStatus>((ref) {
  return ref.watch(haccpRepositoryProvider).getStatusToday();
});

/// Sessions du jour.
final haccpTodaySessionsProvider =
    FutureProvider.autoDispose<List<HaccpCheckSession>>((ref) {
  return ref.watch(haccpRepositoryProvider).getTodaySessions();
});

/// Équipements actifs.
final haccpEquipmentProvider =
    FutureProvider.autoDispose<List<HaccpEquipment>>((ref) {
  return ref.watch(haccpRepositoryProvider).listEquipment();
});

/// Tâches ND pour le type de session actif.
final haccpCleaningTasksProvider =
    FutureProvider.autoDispose.family<List<HaccpCleaningTask>, String>(
  (ref, sessionType) {
    return ref
        .watch(haccpRepositoryProvider)
        .listCleaningTasks(sessionType: sessionType);
  },
);

/// NC ouvertes.
final haccpOpenNcProvider =
    FutureProvider.autoDispose<List<HaccpNonConformity>>((ref) {
  return ref.watch(haccpRepositoryProvider).listNonConformities(status: 'open');
});

/// Relevés de température pour une session.
final haccpTemperatureLogsProvider =
    FutureProvider.autoDispose.family<List<HaccpTemperatureLog>, int>(
  (ref, sessionId) {
    return ref.watch(haccpRepositoryProvider).listTemperatures(sessionId);
  },
);

/// Logs ND pour une session.
final haccpCleaningLogsProvider =
    FutureProvider.autoDispose.family<List<HaccpCleaningLog>, int>(
  (ref, sessionId) {
    return ref.watch(haccpRepositoryProvider).listCleaningLogs(sessionId);
  },
);

/// DLC checks pour une session.
final haccpDlcChecksProvider =
    FutureProvider.autoDispose.family<List<HaccpDlcCheck>, int>(
  (ref, sessionId) {
    return ref.watch(haccpRepositoryProvider).listDlcChecks(sessionId);
  },
);

/// Logs huile friteuse pour une session.
final haccpOilLogsProvider =
    FutureProvider.autoDispose.family<List<HaccpFryingOilLog>, int>(
  (ref, sessionId) {
    return ref.watch(haccpRepositoryProvider).listFryingOilLogs(sessionId);
  },
);

/// Contrôles réception du jour.
final haccpReceptionTodayProvider =
    FutureProvider.autoDispose<List<HaccpReceptionControl>>((ref) {
  return ref
      .watch(haccpRepositoryProvider)
      .listReceptionControls(date: DateTime.now());
});

/// Refroidissements en cours (active_only=true).
final haccpActiveCoolingProvider =
    FutureProvider.autoDispose<List<HaccpCoolingLog>>((ref) {
  return ref.watch(haccpRepositoryProvider).listCoolingLogs(activeOnly: true);
});

/// Tous les refroidissements.
final haccpAllCoolingProvider =
    FutureProvider.autoDispose<List<HaccpCoolingLog>>((ref) {
  return ref.watch(haccpRepositoryProvider).listCoolingLogs();
});

/// Registre de formation hygiène.
final haccpTrainingProvider =
    FutureProvider.autoDispose<List<HaccpTrainingRecord>>((ref) {
  return ref.watch(haccpRepositoryProvider).listTrainingRecords();
});

/// Scorecard HACCP pour une période donnée [from, to] en ISO 8601 (YYYY-MM-DD).
final haccpStatsProvider = FutureProvider.autoDispose
    .family<HaccpStatsData, ({String from, String to})>(
  (ref, period) async {
    final api = ref.watch(apiClientProvider);
    final response = await api.get(
      ApiEndpoints.haccpStats,
      queryParameters: {'from': period.from, 'to': period.to},
    );
    return HaccpStatsData.fromJson(response.data as Map<String, dynamic>);
  },
);
