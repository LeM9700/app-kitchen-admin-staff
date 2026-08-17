import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_actions_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_connection.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_time.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_layout_policy.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_offline_banner.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_pagination_bar.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_status_header.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_grid.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class KitchenPage extends ConsumerWidget {
  const KitchenPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(
      kitchenActionsProvider.select((state) => state.lastError),
      (previous, next) {
        if (next == null || next == previous) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next)),
        );
        ref.read(kitchenActionsProvider.notifier).clearError();
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final policy = KitchenLayoutPolicy.fromConstraints(constraints);
        final profile = ref.watch(kitchenScreenProfileProvider);
        _syncProfileWithPolicy(ref, profile, policy);

        final queue = ref.watch(kitchenQueueProvider);

        return queue.when(
          data: (state) => _KitchenBoard(state: state, policy: policy),
          loading: () => _KitchenLoadingBoard(profile: profile),
          error: (error, stackTrace) => _KitchenErrorBoard(
            error: error,
            profile: profile,
          ),
        );
      },
    );
  }

  void _syncProfileWithPolicy(
    WidgetRef ref,
    KitchenScreenProfile profile,
    KitchenLayoutPolicy policy,
  ) {
    if (profile.ticketsPerPage == policy.ticketsPerPage) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(kitchenQueueProvider.notifier).setProfile(
            profile.copyWith(ticketsPerPage: policy.ticketsPerPage),
          );
    });
  }
}

class _KitchenBoard extends ConsumerWidget {
  const _KitchenBoard({
    required this.state,
    required this.policy,
  });

  final KitchenQueueState state;
  final KitchenLayoutPolicy policy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(kitchenQueueProvider.notifier);
    final actionsState = ref.watch(kitchenActionsProvider);
    final actionsController = ref.read(kitchenActionsProvider.notifier);
    final connection = ref.watch(kitchenConnectionStateProvider);
    final prepTimeNormalMinutes = _prepTimeNormalMinutes(
      ref.watch(tenantConfigProvider).valueOrNull?.prepTimeNormalMinutes,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitchenStatusHeader(
          profile: state.profile,
          totalWaiting: state.totalWaiting,
          totalPreparing: state.totalPreparing,
          totalNew: state.totalNew,
          connection: connection,
          onProfileSelected: controller.setProfile,
        ),
        KitchenOfflineBanner(connection: connection),
        Expanded(
          child: state.tickets.isEmpty
              ? const EmptyState(
                  icon: Icons.restaurant_menu_outlined,
                  title: 'AUCUNE COMMANDE EN COURS',
                )
              : KitchenTicketGrid(
                  tickets: state.currentPageTickets,
                  profile: state.profile,
                  policy: policy,
                  focusedOrderId: state.focusedOrderId,
                  actionsState: actionsState,
                  prepTimeNormalMinutes: prepTimeNormalMinutes,
                  onTicketTap: (ticket) {
                    controller.focusOrder(ticket.order.id);
                  },
                  onStart: (ticket) {
                    actionsController.startOrder(orderId: ticket.order.id);
                  },
                  onReady: (ticket) {
                    actionsController.markStationReady(
                      ticket: ticket,
                      profile: state.profile,
                    );
                  },
                ),
        ),
        KitchenPaginationBar(
          state: state,
          onPrevious: controller.previousPage,
          onNext: controller.nextPage,
        ),
      ],
    );
  }
}

int _prepTimeNormalMinutes(int? value) {
  if (value == null || value <= 0) {
    return defaultKitchenPrepTimeNormalMinutes;
  }
  return value;
}

class _KitchenLoadingBoard extends ConsumerWidget {
  const _KitchenLoadingBoard({required this.profile});

  final KitchenScreenProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(kitchenConnectionStateProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitchenStatusHeader(
          profile: profile,
          totalWaiting: 0,
          totalPreparing: 0,
          totalNew: 0,
          connection: connection,
          onProfileSelected: ref.read(kitchenQueueProvider.notifier).setProfile,
        ),
        KitchenOfflineBanner(connection: connection),
        const Expanded(
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}

class _KitchenErrorBoard extends ConsumerWidget {
  const _KitchenErrorBoard({
    required this.error,
    required this.profile,
  });

  final Object error;
  final KitchenScreenProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(kitchenConnectionStateProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitchenStatusHeader(
          profile: profile,
          totalWaiting: 0,
          totalPreparing: 0,
          totalNew: 0,
          connection: connection,
          onProfileSelected: ref.read(kitchenQueueProvider.notifier).setProfile,
        ),
        KitchenOfflineBanner(connection: connection),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 44,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'CHARGEMENT CUISINE IMPOSSIBLE',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        ref.read(kitchenQueueProvider.notifier).refresh();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('RÉESSAYER'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
