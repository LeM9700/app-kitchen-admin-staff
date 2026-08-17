import 'package:app_admin_staff/core/api/api_error.dart';
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
      _storeActionError(error);
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
      for (final item in itemsToPatch) {
        await repository.updateItemPreparation(
          orderId: orderId,
          itemId: item.id,
          status: 'ready',
        );
      }

      final reloadedOrder = await repository.getOrder(orderId);
      if (reloadedOrder.status != 'ready' &&
          _allOrderItemsReady(reloadedOrder)) {
        await repository.updateStatus(orderId, 'ready');
      }

      await _refreshAfterSuccessfulMutation(orderId);
    } catch (error) {
      _storeActionError(error);
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

String _screenModeKey(KitchenScreenMode mode) {
  return switch (mode) {
    KitchenScreenMode.kitchen => 'kitchen',
    KitchenScreenMode.counter => 'counter',
    KitchenScreenMode.service => 'service',
  };
}
