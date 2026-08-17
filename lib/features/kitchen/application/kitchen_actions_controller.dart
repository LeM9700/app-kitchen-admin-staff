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
      final itemsToPatch = ticket.visibleItems
          .where((item) => item.preparationStatus != 'ready')
          .toList(growable: false);

      // Sequential PATCHes keep backend aggregate status recalculation
      // coherent until the future bulk station endpoint exists.
      for (var index = 0; index < itemsToPatch.length; index++) {
        final item = itemsToPatch[index];
        try {
          await repository.updateItemPreparation(
            orderId: orderId,
            itemId: item.id,
            status: 'ready',
          );
        } catch (error) {
          if (_isOfflineCompatible(error)) {
            _queueItemPreparationUpdates(
              orderId: orderId,
              items: itemsToPatch.skip(index),
              status: 'ready',
              lastError: error.toString(),
            );
            _storeOfflineQueuedMessage();
          } else {
            await _handleActionError(error, orderId: orderId);
          }
          return;
        }
      }

      final reloadedOrder = await repository.getOrder(orderId);
      if (reloadedOrder.status != 'ready' &&
          _allOrderItemsReady(reloadedOrder)) {
        try {
          await repository.updateStatus(orderId, 'ready');
        } catch (error) {
          if (_isOfflineCompatible(error)) {
            _queueOrderStatusUpdate(
              orderId: orderId,
              status: 'ready',
              label: 'Commande #$orderId -> PRETE',
              lastError: error.toString(),
            );
            _storeOfflineQueuedMessage();
          } else {
            await _handleActionError(error, orderId: orderId);
          }
          return;
        }
      }

      await _refreshAfterSuccessfulMutation(orderId);
    } catch (error) {
      await _handleActionError(error, orderId: orderId);
    } finally {
      _finishAction(key);
    }
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

  void _queueItemPreparationUpdates({
    required int orderId,
    required Iterable<OrderItem> items,
    required String status,
    required String lastError,
  }) {
    for (final item in items) {
      ref.read(syncQueueProvider.notifier).add(
            feature: 'kitchen',
            label: 'Commande #$orderId item #${item.id} -> PRETE',
            endpoint: ApiEndpoints.orderItemPreparation(orderId, item.id),
            method: 'PATCH',
            payload: {'status': status},
            lastError: lastError,
          );
    }
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
  final station = profile.station.trim().isEmpty
      ? _screenModeKey(profile.mode)
      : profile.station.trim();
  return 'order:$orderId:ready:$station';
}

bool _isPreparationScreen(KitchenScreenProfile profile) {
  return profile.mode == KitchenScreenMode.kitchen ||
      profile.mode == KitchenScreenMode.counter;
}

bool _allOrderItemsReady(OrderDetail order) {
  return order.items.isNotEmpty &&
      order.items.every((item) => item.preparationStatus == 'ready');
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
