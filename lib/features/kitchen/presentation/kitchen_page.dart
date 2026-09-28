import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_elevation.dart';
import 'package:app_admin_staff/features/kitchen/application/kds_active_screens_provider.dart';
import 'package:app_admin_staff/features/kitchen/application/kds_screen_management_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_actions_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_connection.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_time.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_repository.dart';
import 'package:app_admin_staff/features/kitchen/domain/kds_screen_profile_mapper.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_screen_presets.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_layout_policy.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kds_remote_scan_flow.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_visuals.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kds_pairing_dialog.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_offline_banner.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_pagination_bar.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_status_header.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_grid.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _kitchenRemotePairingBusyProvider = StateProvider<bool>((ref) => false);

class KitchenPage extends ConsumerWidget {
  const KitchenPage({
    this.screenMode = KitchenScreenMode.kitchen,
    super.key,
  });

  final KitchenScreenMode screenMode;

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

    // Kitchen is a real-time board — depth stays subtle so live status/
    // countdown text is never competing with decorative shadow.
    return NeumorphicIntensityScope(
      intensity: NeumorphicIntensity.subtle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final policy = KitchenLayoutPolicy.fromConstraints(constraints);
          final profile = ref.watch(
            kitchenScreenProfileProviderFor(screenMode),
          );
          _syncProfileWithPolicy(
            ref,
            profile,
            policy,
            screenMode,
          );

          final queue = ref.watch(kitchenQueueProviderFor(screenMode));

          return ColoredBox(
            color: KitchenVisuals.boardBackground,
            child: queue.when(
              data: (state) => _KitchenBoard(
                state: state,
                policy: policy,
                screenMode: screenMode,
              ),
              loading: () => _KitchenLoadingBoard(
                profile: profile,
                screenMode: screenMode,
              ),
              error: (error, stackTrace) => _KitchenErrorBoard(
                error: error,
                profile: profile,
                screenMode: screenMode,
              ),
            ),
          );
        },
      ),
    );
  }

  void _syncProfileWithPolicy(
    WidgetRef ref,
    KitchenScreenProfile profile,
    KitchenLayoutPolicy policy,
    KitchenScreenMode screenMode,
  ) {
    if (profile.ticketsPerPage == policy.ticketsPerPage) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(kitchenQueueProviderFor(screenMode).notifier).setProfile(
            profile.copyWith(ticketsPerPage: policy.ticketsPerPage),
          );
    });
  }
}

class _KitchenBoard extends ConsumerWidget {
  const _KitchenBoard({
    required this.state,
    required this.policy,
    required this.screenMode,
  });

  final KitchenQueueState state;
  final KitchenLayoutPolicy policy;
  final KitchenScreenMode screenMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(kitchenQueueProviderFor(screenMode).notifier);
    final actionsState = ref.watch(kitchenActionsProvider);
    final actionsController = ref.read(kitchenActionsProvider.notifier);
    final connection = ref.watch(kitchenConnectionStateProvider);
    final selectedScreen = ref.watch(
      kitchenSelectedScreenProviderFor(screenMode),
    );
    final remotePairingBusy = ref.watch(_kitchenRemotePairingBusyProvider);
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
          selectedScreen: selectedScreen,
          screenMode: screenMode,
          onRemotePairingRequested: () => _showKitchenRemotePairing(
            context,
            ref,
            selectedScreen,
            screenMode,
          ),
          onRemoteScanRequested: policy.compact
              ? () => scanAndOpenKdsRemote(context, ref)
              : null,
          remotePairingBusy: remotePairingBusy,
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
                  onReopen: (ticket) {
                    actionsController.reopenStation(
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

String _rawScreenMode(KitchenScreenMode mode) {
  return switch (mode) {
    KitchenScreenMode.kitchen => 'kitchen',
    KitchenScreenMode.counter => 'counter',
    KitchenScreenMode.service => 'service',
  };
}

Future<void> _showKitchenRemotePairing(
  BuildContext context,
  WidgetRef ref,
  KdsScreen? selectedScreen,
  KitchenScreenMode screenMode,
) async {
  if (ref.read(_kitchenRemotePairingBusyProvider)) {
    return;
  }

  ref.read(_kitchenRemotePairingBusyProvider.notifier).state = true;
  try {
    final screen = await _resolveKitchenRemoteScreen(
      context,
      ref,
      selectedScreen,
      screenMode,
    );
    if (screen == null) {
      return;
    }
    final code = await ref
        .read(kdsRepositoryProvider)
        .generatePairingCode(screenId: screen.id);
    if (!context.mounted) {
      return;
    }
    ref.read(_kitchenRemotePairingBusyProvider.notifier).state = false;
    await showDialog<void>(
      context: context,
      builder: (context) => KdsPairingDialog(
        screen: screen,
        initialCode: code,
        onRegenerate: () => ref
            .read(kdsRepositoryProvider)
            .generatePairingCode(screenId: screen.id),
      ),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mapKdsError(error))),
    );
  } finally {
    ref.read(_kitchenRemotePairingBusyProvider.notifier).state = false;
  }
}

Future<KdsScreen?> _resolveKitchenRemoteScreen(
  BuildContext context,
  WidgetRef ref,
  KdsScreen? selectedScreen,
  KitchenScreenMode screenMode,
) async {
  final rawMode = _rawScreenMode(screenMode);
  final modeLabel = kitchenScreenModeLabel(screenMode);
  if (selectedScreen != null &&
      selectedScreen.isActive &&
      selectedScreen.remoteEnabled &&
      selectedScreen.mode == rawMode) {
    return selectedScreen;
  }
  if (selectedScreen != null && !selectedScreen.isActive) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ÉCRAN INACTIF')),
    );
    return null;
  }
  if (selectedScreen != null && !selectedScreen.remoteEnabled) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('REMOTE DÉSACTIVÉ POUR CET ÉCRAN')),
    );
    return null;
  }

  final screens = await ref.read(kdsActiveScreensProvider.future);
  final candidates = screens
      .where(
        (screen) =>
            screen.isActive &&
            screen.remoteEnabled &&
            screen.mode == rawMode,
      )
      .toList();
  if (candidates.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AUCUN ÉCRAN $modeLabel REMOTE DISPONIBLE')),
      );
    }
    return null;
  }
  if (candidates.length == 1) {
    _selectKitchenRemoteScreen(ref, candidates.first, screenMode);
    return candidates.first;
  }
  if (!context.mounted) {
    return null;
  }
  final picked = await showModalBottomSheet<KdsScreen>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ÉCRAN $modeLabel REMOTE',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            for (final screen in candidates)
              ListTile(
                key: Key('kitchen-remote-screen-option-${screen.id}'),
                leading: const Icon(Icons.desktop_windows_outlined),
                title: Text(screen.name),
                subtitle: Text('${screen.ticketsPerPage} commandes/page'),
                onTap: () => Navigator.of(context).pop(screen),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked != null) {
    _selectKitchenRemoteScreen(ref, picked, screenMode);
  }
  return picked;
}

void _selectKitchenRemoteScreen(
  WidgetRef ref,
  KdsScreen screen,
  KitchenScreenMode screenMode,
) {
  ref.read(kitchenSelectedScreenProviderFor(screenMode).notifier).state = screen;
  ref.read(kitchenQueueProviderFor(screenMode).notifier).setProfile(
        profileFromKdsScreen(screen),
      );
}

class _KitchenLoadingBoard extends ConsumerWidget {
  const _KitchenLoadingBoard({
    required this.profile,
    required this.screenMode,
  });

  final KitchenScreenProfile profile;
  final KitchenScreenMode screenMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(kitchenConnectionStateProvider);
    final selectedScreen = ref.watch(
      kitchenSelectedScreenProviderFor(screenMode),
    );
    final remotePairingBusy = ref.watch(_kitchenRemotePairingBusyProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitchenStatusHeader(
          profile: profile,
          totalWaiting: 0,
          totalPreparing: 0,
          totalNew: 0,
          connection: connection,
          onProfileSelected:
              ref.read(kitchenQueueProviderFor(screenMode).notifier).setProfile,
          selectedScreen: selectedScreen,
          screenMode: screenMode,
          onRemotePairingRequested: () => _showKitchenRemotePairing(
            context,
            ref,
            selectedScreen,
            screenMode,
          ),
          onRemoteScanRequested: MediaQuery.sizeOf(context).width < 760
              ? () => scanAndOpenKdsRemote(context, ref)
              : null,
          remotePairingBusy: remotePairingBusy,
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
    required this.screenMode,
  });

  final Object error;
  final KitchenScreenProfile profile;
  final KitchenScreenMode screenMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(kitchenConnectionStateProvider);
    final modeLabel = kitchenScreenModeLabel(screenMode);
    final selectedScreen = ref.watch(
      kitchenSelectedScreenProviderFor(screenMode),
    );
    final remotePairingBusy = ref.watch(_kitchenRemotePairingBusyProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitchenStatusHeader(
          profile: profile,
          totalWaiting: 0,
          totalPreparing: 0,
          totalNew: 0,
          connection: connection,
          onProfileSelected:
              ref.read(kitchenQueueProviderFor(screenMode).notifier).setProfile,
          selectedScreen: selectedScreen,
          screenMode: screenMode,
          onRemotePairingRequested: () => _showKitchenRemotePairing(
            context,
            ref,
            selectedScreen,
            screenMode,
          ),
          onRemoteScanRequested: MediaQuery.sizeOf(context).width < 760
              ? () => scanAndOpenKdsRemote(context, ref)
              : null,
          remotePairingBusy: remotePairingBusy,
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
                      'CHARGEMENT $modeLabel IMPOSSIBLE',
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
                        ref
                            .read(kitchenQueueProviderFor(screenMode).notifier)
                            .refresh();
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
