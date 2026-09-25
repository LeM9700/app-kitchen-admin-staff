/// Service HACCP offline-first.
///
/// Toutes les mutations HACCP passent par ce service :
///   - Online  → appel API direct via [HaccpRepository]
///   - Offline → action mise en queue dans [SyncQueue] avec idempotency key
///
/// Les lectures (GET) restent dans [HaccpRepository] directement.
/// En cas d'erreur réseau sur un GET, l'UI affiche les dernières données
/// connues via le dernier état Riverpod (FutureProvider keep-last-value).
///
/// [⚠️ PROD] Les actions queued sont rejouées FIFO par [SyncWorker.flush()].
/// L'idempotency key (endpoint + timestamp + feature) garantit qu'un
/// double-flush ne crée pas de doublons côté serveur.
library haccp_offline_service;

import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Résultat d'une opération offline-first.
sealed class OfflineResult<T> {
  const OfflineResult();
}

/// L'opération a réussi en ligne — [data] contient la réponse serveur.
final class OnlineSuccess<T> extends OfflineResult<T> {
  const OnlineSuccess(this.data);
  final T data;
}

/// L'opération a été mise en queue — le résultat sera disponible après sync.
final class QueuedForSync<T> extends OfflineResult<T> {
  const QueuedForSync(this.label);
  final String label;
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final haccpOfflineServiceProvider = Provider<HaccpOfflineService>((ref) {
  final repo = ref.watch(haccpRepositoryProvider);
  final queue = ref.read(syncQueueProvider.notifier);
  final isOnline = ref.watch(onlineStatusProvider).valueOrNull ?? true;
  return HaccpOfflineService(repo: repo, queue: queue, isOnline: isOnline);
});

// ─── Service ──────────────────────────────────────────────────────────────────

class HaccpOfflineService {
  const HaccpOfflineService({
    required this.repo,
    required this.queue,
    required this.isOnline,
  });

  final HaccpRepository repo;
  final SyncQueue queue;
  final bool isOnline;

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _ikey(String feature, String action) =>
      'haccp_${feature}_${action}_${DateTime.now().microsecondsSinceEpoch}';

  void _enqueue({
    required String feature,
    required String label,
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
  }) {
    queue.add(
      feature: feature,
      label: label,
      endpoint: endpoint,
      method: method,
      payload: payload,
      idempotencyKey: idempotencyKey,
    );
  }

  // ── Démarrage de session ───────────────────────────────────────────────────

  /// Idempotent — safe to queue (le serveur retourne la session existante
  /// si elle existe déjà pour la date + type).
  Future<OfflineResult<HaccpCheckSession>> startSession(
    String sessionType,
  ) async {
    if (isOnline) {
      final result = await repo.startSession(sessionType);
      return OnlineSuccess(result);
    }
    _enqueue(
      feature: 'haccp',
      label: 'Démarrer session $sessionType',
      endpoint: '/haccp/sessions',
      method: 'POST',
      payload: {'session_type': sessionType},
      idempotencyKey: _ikey('session', sessionType),
    );
    return const QueuedForSync('Session mise en queue');
  }

  Future<OfflineResult<HaccpCheckSession>> completeSession(
    int sessionId, {
    String? notes,
    bool force = false,
  }) async {
    final payload = {
      if (notes != null) 'notes': notes,
      'force': force,
    };
    if (isOnline) {
      final result = await repo.completeSession(
        sessionId,
        notes: notes,
        force: force,
      );
      return OnlineSuccess(result);
    }
    _enqueue(
      feature: 'haccp',
      label: 'Valider session #$sessionId',
      endpoint: '/haccp/sessions/$sessionId/complete',
      method: 'PATCH',
      payload: payload,
      idempotencyKey: _ikey('session_complete', sessionId.toString()),
    );
    return const QueuedForSync('Validation de session mise en queue');
  }

  // ── Relevés de température ─────────────────────────────────────────────────

  Future<OfflineResult<HaccpTemperatureLog>> logTemperature(
    int sessionId, {
    required int equipmentId,
    required double measuredTemp,
    String? correctiveAction,
  }) async {
    final payload = {
      'equipment_id': equipmentId,
      'measured_temp': measuredTemp,
      if (correctiveAction != null) 'corrective_action': correctiveAction,
    };

    if (isOnline) {
      final result = await repo.logTemperature(
        sessionId,
        equipmentId: equipmentId,
        measuredTemp: measuredTemp,
        correctiveAction: correctiveAction,
      );
      return OnlineSuccess(result);
    }

    _enqueue(
      feature: 'haccp',
      label: 'T° ${measuredTemp.toStringAsFixed(1)}°C (équip. $equipmentId)',
      endpoint: '/haccp/sessions/$sessionId/temperatures',
      method: 'POST',
      payload: payload,
      idempotencyKey: _ikey('temp', '${sessionId}_$equipmentId'),
    );
    return const QueuedForSync('Relevé T° mis en queue');
  }

  // ── Vérifications DLC ──────────────────────────────────────────────────────

  Future<OfflineResult<HaccpDlcCheck>> logDlcCheck(
    int sessionId,
    Map<String, dynamic> body,
  ) async {
    if (isOnline) {
      final result = await repo.logDlcCheck(sessionId, body);
      return OnlineSuccess(result);
    }
    _enqueue(
      feature: 'haccp',
      label:
          'DLC ${body["ingredient_name"] ?? "produit"} (Niv. ${body["dlc_level"]})',
      endpoint: '/haccp/sessions/$sessionId/dlc',
      method: 'POST',
      payload: body,
      idempotencyKey: _ikey('dlc', '${sessionId}_${body["ingredient_name"]}'),
    );
    return const QueuedForSync('Vérification DLC mise en queue');
  }

  // ── Nettoyage ──────────────────────────────────────────────────────────────

  Future<OfflineResult<HaccpCleaningLog>> logCleaning(
    int sessionId, {
    required int taskId,
    String? notes,
    bool isCompliant = true,
  }) async {
    final payload = {
      'task_id': taskId,
      if (notes != null) 'notes': notes,
      'is_compliant': isCompliant,
    };
    if (isOnline) {
      final result = await repo.logCleaning(
        sessionId,
        taskId: taskId,
        notes: notes,
        isCompliant: isCompliant,
      );
      return OnlineSuccess(result);
    }
    _enqueue(
      feature: 'haccp',
      label: 'Nettoyage tâche #$taskId',
      endpoint: '/haccp/sessions/$sessionId/cleaning',
      method: 'POST',
      payload: payload,
      idempotencyKey: _ikey('cleaning', '${sessionId}_$taskId'),
    );
    return const QueuedForSync('Nettoyage mis en queue');
  }

  // ── Huile friteuse ─────────────────────────────────────────────────────────

  Future<OfflineResult<HaccpFryingOilLog>> logFryingOil(
    int sessionId, {
    required double polarityPercent,
    String? color,
    String? odor,
    String? correctiveAction,
  }) async {
    final payload = {
      'polarity_percent': polarityPercent,
      if (color != null) 'color': color,
      if (odor != null) 'odor': odor,
      if (correctiveAction != null) 'corrective_action': correctiveAction,
    };
    if (isOnline) {
      final result = await repo.logFryingOil(
        sessionId,
        polarityPercent: polarityPercent,
        color: color,
        odor: odor,
        correctiveAction: correctiveAction,
      );
      return OnlineSuccess(result);
    }
    _enqueue(
      feature: 'haccp',
      label: 'Huile friteuse ${polarityPercent.toStringAsFixed(1)}%',
      endpoint: '/haccp/sessions/$sessionId/oil',
      method: 'POST',
      payload: payload,
      idempotencyKey: _ikey('oil', sessionId.toString()),
    );
    return const QueuedForSync('Relevé huile mis en queue');
  }

  // ── Réception fournisseur ──────────────────────────────────────────────────

  Future<OfflineResult<HaccpReceptionControl>> createReceptionControl(
    Map<String, dynamic> body,
  ) async {
    if (isOnline) {
      final result = await repo.createReceptionControl(body);
      return OnlineSuccess(result);
    }
    _enqueue(
      feature: 'haccp',
      label: 'Réception ${body["supplier_name"]} — ${body["product_name"]}',
      endpoint: '/haccp/reception-controls',
      method: 'POST',
      payload: body,
      idempotencyKey: _ikey(
        'reception',
        '${body["supplier_name"]}_${body["product_name"]}',
      ),
    );
    return const QueuedForSync('Contrôle réception mis en queue');
  }

  // ── Refroidissement rapide ─────────────────────────────────────────────────

  Future<OfflineResult<HaccpCoolingLog>> startCooling(
    Map<String, dynamic> body,
  ) async {
    if (isOnline) {
      final result = await repo.startCooling(body);
      return OnlineSuccess(result);
    }
    _enqueue(
      feature: 'haccp',
      label:
          'Refroidissement ${body["product_name"]} (${body["temp_initial"]}°C)',
      endpoint: '/haccp/cooling',
      method: 'POST',
      payload: body,
      idempotencyKey: _ikey('cooling_start', body["product_name"].toString()),
    );
    return const QueuedForSync('Début refroidissement mis en queue');
  }

  Future<OfflineResult<HaccpCoolingLog>> completeCooling(
    int id, {
    required double tempFinal,
    String? correctiveAction,
  }) async {
    final payload = {
      'temp_final': tempFinal,
      if (correctiveAction != null) 'corrective_action': correctiveAction,
    };
    if (isOnline) {
      final result = await repo.completeCooling(
        id,
        tempFinal: tempFinal,
        correctiveAction: correctiveAction,
      );
      return OnlineSuccess(result);
    }
    _enqueue(
      feature: 'haccp',
      label:
          'T° finale refroidissement #$id : ${tempFinal.toStringAsFixed(1)}°C',
      endpoint: '/haccp/cooling/$id',
      method: 'PATCH',
      payload: payload,
      idempotencyKey: _ikey('cooling_end', id.toString()),
    );
    return const QueuedForSync('T° finale mise en queue');
  }

  // ── Non-conformités ────────────────────────────────────────────────────────

  Future<OfflineResult<HaccpNonConformity>> updateNonConformity(
    int id, {
    String? correctiveAction,
    String? status,
  }) async {
    final payload = {
      if (correctiveAction != null) 'corrective_action': correctiveAction,
      if (status != null) 'status': status,
    };
    if (isOnline) {
      final result = await repo.updateNonConformity(
        id,
        correctiveAction: correctiveAction,
        status: status,
      );
      return OnlineSuccess(result);
    }
    _enqueue(
      feature: 'haccp',
      label: 'NC #$id → ${status ?? "mise à jour"}',
      endpoint: '/haccp/non-conformities/$id',
      method: 'PATCH',
      payload: payload,
      idempotencyKey: _ikey('nc_update', '${id}_$status'),
    );
    return const QueuedForSync('Mise à jour NC mise en queue');
  }
}

// ─── Provider : compte actions HACCP en attente ───────────────────────────────

/// Nombre d'actions HACCP dans la queue (badge dans l'AppBar).
final haccpPendingSyncCountProvider = Provider<int>((ref) {
  final actions = ref.watch(syncQueueProvider);
  return pendingSyncCountForFeature(actions, 'haccp');
});
