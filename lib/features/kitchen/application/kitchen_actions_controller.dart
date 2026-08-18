import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _unset = Object();

final kitchenActionsProvider =
    NotifierProvider<KitchenActionsController, KitchenActionsState>(
  KitchenActionsController.new,
);

class KitchenActionsState {
  const KitchenActionsState({
    this.busyKeys = const <String>{},
    this.lastError,
  });

  final Set<String> busyKeys;
  final String? lastError;

  bool isOrderBusy(int orderId) {
    return busyKeys.any((key) => key.startsWith('order:$orderId:'));
  }

  bool isActionBusy(String key) {
    return busyKeys.contains(key);
  }

  KitchenActionsState copyWith({
    Set<String>? busyKeys,
    Object? lastError = _unset,
  }) {
    return KitchenActionsState(
      busyKeys: busyKeys ?? this.busyKeys,
      lastError: lastError == _unset ? this.lastError : lastError as String?,
    );
  }
}

class KitchenActionsController extends Notifier<KitchenActionsState> {
  @override
  KitchenActionsState build() {
    return const KitchenActionsState();
  }

  Future<void> startOrder({
    required int orderId,
  }) async {
    final key = kitchenStartOrderActionKey(orderId);
    if (!_startAction(key)) {
      return;
    }

    try {
      await ref.read(ordersRepositoryProvider).updateStatus(
            orderId,
            'preparing',
          );
      await _refreshAfterSuccessfulMutation(orderId);
    } catch (error) {
      if (_isOfflineCompatible(error)) {
        _queueOrderStatusUpdate(
          orderId: orderId,
          status: 'preparing',
          label: 'Commande #$orderId -> PREPARATION',
          lastError: error.toString(),
        );
        _storeOfflineQueuedMessage();
      } else {
        await _handleActionError(error, orderId: orderId);
      }
    } finally {
      _finishAction(key);
    }
  }

  /// Passe toute la station du profil courant a "ready", en un seul appel
  /// bulk. Le backend est desormais la seule source de verite pour la
  /// synchronisation du statut global (LOT 12) : plus de N PATCH item par
  /// item ni de second PATCH `updateStatus(orderId, 'ready')` cote client.
  Future<void> markStationReady({
    required KitchenTicketViewModel ticket,
    required KitchenScreenProfile profile,
  }) async {
    if (!_isPreparationScreen(profile)) {
      state = state.copyWith(
        lastError: 'Action indisponible sur cet ecran.',
      );
      return;
    }

    final orderId = ticket.order.id;
    final key = kitchenReadyStationActionKey(orderId, profile);
    if (!_startAction(key)) {
      return;
    }

    try {
      final repository = ref.read(ordersRepositoryProvider);
      await repository.updateStationPreparation(
        orderId: orderId,
        station: profile.station,
        status: 'ready',
      );
      await _refreshAfterSuccessfulMutation(orderId);
    } catch (error) {
      if (_isOfflineCompatible(error)) {
        _queueStationPreparationUpdate(
          orderId: orderId,
          station: profile.station,
          status: 'ready',
          label: 'Commande #$orderId poste ${profile.station} -> PRETE',
          lastError: error.toString(),
        );
        _storeOfflineQueuedMessage();
      } else {
        await _handleActionError(error, orderId: orderId);
      }
    } finally {
      _finishAction(key);
    }
  }

  /// Repasse la station du profil courant en "preparing" (correction
  /// operationnelle KDS, declenchee par un maintien de 2 secondes cote UI).
  /// Si le statut global etait "ready", le backend le fait redescendre a
  /// "preparing" atomiquement -- jamais via `updateStatus`, qui refuse
  /// toujours ready -> preparing.
  Future<void> reopenStation({
    required KitchenTicketViewModel ticket,
    required KitchenScreenProfile profile,
  }) async {
    if (!_isPreparationScreen(profile)) {
      state = state.copyWith(
        lastError: 'Action indisponible sur cet ecran.',
      );
      return;
    }
    if (!_canReopenStation(ticket)) {
      return;
    }

    final orderId = ticket.order.id;
    final key = kitchenReopenStationActionKey(orderId, profile);
    if (!_startAction(key)) {
      return;
    }

    const note = 'Reouverture du poste depuis le KDS';
    try {
      final repository = ref.read(ordersRepositoryProvider);
      await repository.updateStationPreparation(
        orderId: orderId,
        station: profile.station,
        status: 'preparing',
        note: note,
      );
      await _refreshAfterSuccessfulMutation(orderId);
      state = state.copyWith(lastError: 'POSTE REPASSE EN PREPARATION');
    } catch (error) {
      if (_isOfflineCompatible(error)) {
        _queueStationPreparationUpdate(
          orderId: orderId,
          station: profile.station,
          status: 'preparing',
          note: note,
          label:
              'Commande #$orderId poste ${profile.station} -> EN PREPARATION',
          lastError: error.toString(),
        );
        _storeOfflineQueuedMessage();
      } else {
        await _handleActionError(error, orderId: orderId);
      }
    } finally {
      _finishAction(key);
    }
  }

  bool _canReopenStation(KitchenTicketViewModel ticket) {
    if (!ticket.stationReady || ticket.visibleItems.isEmpty) {
      return false;
    }
    return ticket.state == KitchenTicketState.preparing ||
        ticket.state == KitchenTicketState.ready;
  }

  void clearError() {
    if (state.lastError != null) {
      state = state.copyWith(lastError: null);
    }
  }

  bool _startAction(String key) {
    if (state.busyKeys.contains(key)) {
      return false;
    }

    state = state.copyWith(
      busyKeys: Set.unmodifiable({...state.busyKeys, key}),
      lastError: null,
    );
    return true;
  }

  void _finishAction(String key) {
    if (!state.busyKeys.contains(key)) {
      return;
    }

    final nextBusyKeys = {...state.busyKeys}..remove(key);
    state = state.copyWith(busyKeys: Set.unmodifiable(nextBusyKeys));
  }

  Future<void> _refreshAfterSuccessfulMutation(int orderId) async {
    ref.invalidate(orderDetailProvider(orderId));
    // The queue controller owns the single activeOrders invalidation/rebuild
    // path so LOT 5 actions do not stack duplicate refresh calls.
    await ref.read(kitchenQueueProvider.notifier).refresh(
          preserveCurrentOnError: true,
        );
  }

  Future<void> _refreshAfterConflict(int orderId) async {
    ref.invalidate(orderDetailProvider(orderId));
    try {
      await ref.read(kitchenQueueProvider.notifier).refresh(
            preserveCurrentOnError: true,
          );
    } catch (_) {
      // Keep the current board usable if the conflict refresh also fails.
    }
  }

  Future<void> _handleActionError(
    Object error, {
    required int orderId,
  }) async {
    if (error is ConflictException) {
      state = state.copyWith(lastError: 'DEJA MISE A JOUR');
      await _refreshAfterConflict(orderId);
      return;
    }

    _storeActionError(error);
  }

  void _queueOrderStatusUpdate({
    required int orderId,
    required String status,
    required String label,
    required String lastError,
  }) {
    ref.read(syncQueueProvider.notifier).add(
          feature: 'kitchen',
          label: label,
          endpoint: ApiEndpoints.orderStatus(orderId),
          method: 'PATCH',
          payload: {'status': status},
          lastError: lastError,
        );
  }

  void _queueStationPreparationUpdate({
    required int orderId,
    required String station,
    required String status,
    required String label,
    required String lastError,
    String? note,
  }) {
    ref.read(syncQueueProvider.notifier).add(
          feature: 'kitchen',
          label: label,
          endpoint: ApiEndpoints.orderStationPreparation(orderId, station),
          method: 'PATCH',
          payload: {
            'status': status,
            if (note != null) 'note': note,
          },
          lastError: lastError,
        );
  }

  void _storeOfflineQueuedMessage() {
    state = state.copyWith(lastError: 'Action mise en file offline.');
  }

  void _storeActionError(Object error) {
    state = state.copyWith(lastError: _actionErrorMessage(error));
  }
}

String kitchenStartOrderActionKey(int orderId) {
  return 'order:$orderId:start';
}

String kitchenReadyStationActionKey(
  int orderId,
  KitchenScreenProfile profile,
) {
  return 'order:$orderId:ready:${_stationKey(profile)}';
}

String kitchenReopenStationActionKey(
  int orderId,
  KitchenScreenProfile profile,
) {
  return 'order:$orderId:reopen:${_stationKey(profile)}';
}

String _stationKey(KitchenScreenProfile profile) {
  return profile.station.trim().isEmpty
      ? _screenModeKey(profile.mode)
      : profile.station.trim();
}

bool _isPreparationScreen(KitchenScreenProfile profile) {
  return profile.mode == KitchenScreenMode.kitchen ||
      profile.mode == KitchenScreenMode.counter;
}

String _actionErrorMessage(Object error) {
  if (error is AppException && error.message.trim().isNotEmpty) {
    return error.message;
  }

  return 'Impossible de mettre a jour la commande.';
}

bool _isOfflineCompatible(Object error) {
  return error is NetworkException;
}

String _screenModeKey(KitchenScreenMode mode) {
  return switch (mode) {
    KitchenScreenMode.kitchen => 'kitchen',
    KitchenScreenMode.counter => 'counter',
    KitchenScreenMode.service => 'service',
  };
}
