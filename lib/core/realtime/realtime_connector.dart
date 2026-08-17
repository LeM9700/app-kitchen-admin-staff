import 'dart:async';

import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/realtime/notification_bus.dart';
import 'package:app_admin_staff/core/realtime/websocket_client.dart';
import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/hr/application/hr_realtime.dart';
import 'package:app_admin_staff/features/loyalty/data/loyalty_repository.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RealtimeConnector extends ConsumerStatefulWidget {
  const RealtimeConnector({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  ConsumerState<RealtimeConnector> createState() => _RealtimeConnectorState();
}

class _RealtimeConnectorState extends ConsumerState<RealtimeConnector>
    with WidgetsBindingObserver {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncConnection());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionControllerProvider, (previous, next) {
      _syncConnection();
    });
    ref.listen(notificationBusProvider, (previous, next) {
      if (next.isEmpty) {
        return;
      }
      final latest = next.first;
      if ((latest.event ?? '').startsWith('order.')) {
        final invalidation = resolveOrderRealtimeInvalidation(latest);
        if (invalidation.invalidateActiveOrders) {
          ref.invalidate(activeOrdersProvider);
        }
        final orderId = invalidation.orderId;
        if (orderId != null) {
          ref.invalidate(orderDetailProvider(orderId));
        }
        SystemSound.play(SystemSoundType.alert);
      }
      if ((latest.event ?? '').startsWith('hr.')) {
        invalidateHrProviders(ref);
      }
      if (latest.event == 'stock.low_alert') {
        ref.invalidate(ingredientsProvider);
        ref.invalidate(stockAlertsProvider);
        ref.invalidate(stockMovementsProvider);
      }
      if (latest.event == 'loyalty.points_expiring') {
        ref.invalidate(loyaltyStatsProvider);
      }
      if (latest.event == 'allergen_update') {
        ref.invalidate(catalogProductsProvider);
        ref.invalidate(catalogCategoriesProvider);
      }
      final title = _snackTitle(latest);
      if (title != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(title)),
        );
      }
    });
    return widget.child;
  }

  Future<void> _syncConnection() async {
    final session = ref.read(sessionControllerProvider).valueOrNull;
    final client = ref.read(realtimeClientProvider);
    if (session?.status == SessionStatus.authenticated) {
      await client.connect();
      _startPolling();
    } else {
      _stopPolling();
      await client.disconnect();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) {
        return;
      }
      ref.invalidate(activeOrdersProvider);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncConnection();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopPolling();
      ref.read(realtimeClientProvider).disconnect();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    ref.read(realtimeClientProvider).disconnect();
    super.dispose();
  }

  String? _snackTitle(RealtimeNotification notification) {
    if (notification.event == 'security_alert') {
      return 'Alerte securite';
    }
    return notification.title;
  }
}

class OrderRealtimeInvalidation {
  const OrderRealtimeInvalidation({
    required this.invalidateActiveOrders,
    this.orderId,
  });

  final bool invalidateActiveOrders;
  final int? orderId;
}

OrderRealtimeInvalidation resolveOrderRealtimeInvalidation(
  RealtimeNotification notification,
) {
  final event = notification.event ?? '';
  if (!event.startsWith('order.')) {
    return const OrderRealtimeInvalidation(invalidateActiveOrders: false);
  }

  return OrderRealtimeInvalidation(
    invalidateActiveOrders: true,
    orderId: notification.orderId,
  );
}
