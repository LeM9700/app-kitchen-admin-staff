import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_actions_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_connection.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_remote_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_remote_navigation.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_time.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_remote_session.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_offline_banner.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_station_status.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_header.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_items.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

class KitchenRemotePage extends ConsumerWidget {
  const KitchenRemotePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(kitchenRemoteSessionProvider);

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: remote.when(
        loading: () => const _KitchenRemoteRestoringView(),
        error: (_, __) {
          return const _KitchenRemoteControllerErrorView();
        },
        data: (state) {
          final session = state.session;
          if (state.phase == KitchenRemotePhase.connected && session != null) {
            return _KitchenRemoteSessionView(session: session);
          }
          if (state.phase == KitchenRemotePhase.unavailable) {
            if (session != null) {
              return _KitchenRemoteUnavailableView(
                session: session,
                message: state.message,
              );
            }
            return _KitchenRemoteRestoreUnavailableView(message: state.message);
          }
          return _KitchenRemoteAssociationView(state: state);
        },
      ),
    );
  }
}

class _KitchenRemoteAssociationView extends ConsumerStatefulWidget {
  const _KitchenRemoteAssociationView({required this.state});

  final KitchenRemoteState state;

  @override
  ConsumerState<_KitchenRemoteAssociationView> createState() {
    return _KitchenRemoteAssociationViewState();
  }
}

class _KitchenRemoteAssociationViewState
    extends ConsumerState<_KitchenRemoteAssociationView> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final codeReady = RegExp(r'^\d{6}$').hasMatch(_codeController.text);
    final isPairing = widget.state.isPairing;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
        children: [
          Icon(
            Icons.phonelink_setup_outlined,
            color: scheme.primary,
            size: 42,
          ),
          const SizedBox(height: 16),
          Text(
            'AUCUN ÉCRAN ASSOCIÉ',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'ENTREZ LE CODE AFFICHÉ SUR L’ÉCRAN KDS',
            style: KitchenTypography.meta(context).copyWith(
              color: scheme.onSurface.withValues(alpha: 0.64),
            ),
          ),
          if (widget.state.message != null) ...[
            const SizedBox(height: 16),
            _RemoteMessageBanner(message: widget.state.message!),
          ],
          const SizedBox(height: 22),
          TextField(
            key: const Key('kitchen-remote-pairing-code'),
            controller: _codeController,
            enabled: !isPairing,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
            decoration: const InputDecoration(
              counterText: '',
              hintText: '_ _ _ _ _ _',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              key: const Key('kitchen-remote-pair-submit'),
              onPressed: codeReady && !isPairing
                  ? () {
                      ref
                          .read(kitchenRemoteSessionProvider.notifier)
                          .pairWithCode(code: _codeController.text);
                    }
                  : null,
              icon: isPairing
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimaryContainer,
                      ),
                    )
                  : const Icon(Icons.link),
              label: const Text('ASSOCIER'),
            ),
          ),
        ],
      ),
    );
  }
}

class _KitchenRemoteSessionView extends StatelessWidget {
  const _KitchenRemoteSessionView({required this.session});

  final KitchenRemoteSession session;

  @override
  Widget build(BuildContext context) {
    if (session.status == KitchenRemoteSessionStatus.unavailable) {
      return _KitchenRemoteUnavailableView(session: session);
    }

    return ProviderScope(
      key: ValueKey(session.providerScopeKey),
      overrides: [
        kitchenScreenProfileProvider.overrideWith(
          () => _LockedKitchenScreenProfileController(session.profile),
        ),
        kitchenQueueProvider.overrideWith(KitchenQueueController.new),
        kitchenActionsProvider.overrideWith(KitchenActionsController.new),
      ],
      child: _KitchenRemoteConnectedView(session: session),
    );
  }
}

class _KitchenRemoteRestoringView extends StatelessWidget {
  const _KitchenRemoteRestoringView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _KitchenRemoteControllerErrorView extends ConsumerWidget {
  const _KitchenRemoteControllerErrorView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
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
              'SESSION À VÉRIFIER',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () {
                ref.read(kitchenRemoteSessionProvider.notifier).retry();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('RÉESSAYER'),
            ),
          ],
        ),
      ),
    );
  }
}

class _KitchenRemoteRestoreUnavailableView extends ConsumerWidget {
  const _KitchenRemoteRestoreUnavailableView({this.message});

  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = message ?? 'SESSION À VÉRIFIER';

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_outlined,
                size: 46,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 14),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('kitchen-remote-retry'),
                  onPressed: () {
                    ref.read(kitchenRemoteSessionProvider.notifier).retry();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('RÉESSAYER'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref
                        .read(kitchenRemoteSessionProvider.notifier)
                        .disconnect();
                  },
                  icon: const Icon(Icons.link_off),
                  label: const Text('ASSOCIER UN ÉCRAN'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteMessageBanner extends StatelessWidget {
  const _RemoteMessageBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: scheme.error),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: KitchenTypography.meta(context).copyWith(
            color: scheme.onErrorContainer,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _LockedKitchenScreenProfileController
    extends KitchenScreenProfileController {
  _LockedKitchenScreenProfileController(this._profile);

  final KitchenScreenProfile _profile;

  @override
  KitchenScreenProfile build() {
    return _profile;
  }

  @override
  void setProfile(KitchenScreenProfile profile) {}
}

class _KitchenRemoteConnectedView extends ConsumerWidget {
  const _KitchenRemoteConnectedView({required this.session});

  final KitchenRemoteSession session;

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

    final queue = ref.watch(kitchenQueueProvider);
    final connection = ref.watch(kitchenConnectionStateProvider);

    return Column(
      key: const Key('kitchen-remote-board'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RemoteSessionHeader(
          session: session,
          connection: connection,
          onDisconnect: () => _confirmDisconnect(context, ref, session),
        ),
        KitchenOfflineBanner(connection: connection),
        Expanded(
          child: queue.when(
            data: (state) => _KitchenRemoteQueueBody(
              session: session,
              state: state,
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => _KitchenRemoteErrorBody(error: error),
          ),
        ),
      ],
    );
  }
}

class _KitchenRemoteQueueBody extends ConsumerWidget {
  const _KitchenRemoteQueueBody({
    required this.session,
    required this.state,
  });

  final KitchenRemoteSession session;
  final KitchenQueueState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = resolveRemoteNavigationState(state);
    final ticket = navigation.currentTicket;
    final prepTimeNormalMinutes = _prepTimeNormalMinutes(
      ref.watch(tenantConfigProvider).valueOrNull?.prepTimeNormalMinutes,
    );

    if (ticket == null) {
      return const EmptyState(
        icon: Icons.restaurant_menu_outlined,
        title: 'AUCUNE COMMANDE EN COURS',
      );
    }

    return Column(
      children: [
        if (state.queueChangedWhileBrowsing)
          _RemoteQueueChangedBanner(
            onReturnToLive: () {
              final controller = ref.read(kitchenQueueProvider.notifier);
              controller.goToPage(0);
              controller.clearFocus();
            },
          ),
        Expanded(
          child: _KitchenRemoteTicketPanel(
            ticket: ticket,
            profile: session.profile,
            prepTimeNormalMinutes: prepTimeNormalMinutes,
          ),
        ),
        _KitchenRemoteNavigationBar(
          state: state,
          navigation: navigation,
        ),
      ],
    );
  }
}

class _KitchenRemoteTicketPanel extends ConsumerWidget {
  const _KitchenRemoteTicketPanel({
    required this.ticket,
    required this.profile,
    required this.prepTimeNormalMinutes,
  });

  final KitchenTicketViewModel ticket;
  final KitchenScreenProfile profile;
  final int prepTimeNormalMinutes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final actionsState = ref.watch(kitchenActionsProvider);
    final actionsController = ref.read(kitchenActionsProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide(color: scheme.primary, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitchenTicketHeader(
              ticket: ticket,
              compact: true,
              prepTimeNormalMinutes: prepTimeNormalMinutes,
            ),
            Expanded(
              child: KitchenTicketItems(
                items: ticket.visibleItems,
                compact: true,
              ),
            ),
            if (profile.mode == KitchenScreenMode.service)
              KitchenStationStatus(order: ticket.order, compact: true),
            _RemoteTicketMeta(ticket: ticket),
            KitchenRemoteActions(
              ticket: ticket,
              profile: profile,
              actionsState: actionsState,
              onStart: () {
                actionsController.startOrder(orderId: ticket.order.id);
              },
              onReady: () {
                actionsController.markStationReady(
                  ticket: ticket,
                  profile: profile,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

@visibleForTesting
class KitchenRemoteActions extends StatelessWidget {
  const KitchenRemoteActions({
    required this.ticket,
    required this.profile,
    required this.actionsState,
    this.onStart,
    this.onReady,
    super.key,
  });

  final KitchenTicketViewModel ticket;
  final KitchenScreenProfile profile;
  final KitchenActionsState actionsState;
  final VoidCallback? onStart;
  final VoidCallback? onReady;

  @override
  Widget build(BuildContext context) {
    if (profile.mode == KitchenScreenMode.service || ticket.isLocked) {
      return const SizedBox.shrink();
    }

    if (ticket.state == KitchenTicketState.ready) {
      return const _RemoteActionStateLabel(label: '✓ PRÊTE');
    }

    if (ticket.stationReady) {
      return const _RemoteActionStateLabel(label: '✓ POSTE PRÊT');
    }

    if (ticket.canStart) {
      final key = kitchenStartOrderActionKey(ticket.order.id);
      return _RemoteActionButton(
        key: const Key('kitchen-remote-start'),
        label: 'COMMENCER',
        icon: Icons.play_arrow_rounded,
        busy: actionsState.isActionBusy(key),
        onPressed: onStart,
      );
    }

    if (ticket.canMarkReady) {
      final key = kitchenReadyStationActionKey(ticket.order.id, profile);
      return _RemoteActionButton(
        key: const Key('kitchen-remote-ready'),
        label: 'PRÊTE',
        icon: Icons.check_rounded,
        busy: actionsState.isActionBusy(key),
        onPressed: onReady,
      );
    }

    return const SizedBox.shrink();
  }
}

class _RemoteActionButton extends StatelessWidget {
  const _RemoteActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            textStyle: KitchenTypography.meta(context),
            disabledBackgroundColor:
                scheme.primaryContainer.withValues(alpha: 0.72),
            disabledForegroundColor: scheme.onPrimaryContainer,
          ),
          icon: busy
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimaryContainer,
                  ),
                )
              : Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }
}

class _RemoteActionStateLabel extends StatelessWidget {
  const _RemoteActionStateLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: scheme.primary),
        ),
        child: SizedBox(
          height: 46,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KitchenTypography.meta(context).copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KitchenRemoteNavigationBar extends ConsumerWidget {
  const _KitchenRemoteNavigationBar({
    required this.state,
    required this.navigation,
  });

  final KitchenQueueState state;
  final KitchenRemoteNavigationState navigation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(kitchenQueueProvider.notifier);
    final currentTicket = navigation.currentTicket;
    final focusedOrderId = state.focusedOrderId;
    final focusEnabled = currentTicket != null &&
        focusedOrderId != currentTicket.order.id &&
        state.currentPageTickets.any(
          (ticket) => ticket.order.id == currentTicket.order.id,
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('kitchen-remote-previous'),
                  onPressed: navigation.canGoPrevious
                      ? controller.focusPreviousOrder
                      : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('PRÉCÉDENTE'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('kitchen-remote-focus'),
                tooltip: 'Focaliser',
                onPressed: focusEnabled
                    ? () => controller.focusOrder(currentTicket.order.id)
                    : null,
                icon: const Icon(Icons.center_focus_strong),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('kitchen-remote-next'),
                  onPressed:
                      navigation.canGoNext ? controller.focusNextOrder : null,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('SUIVANTE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteSessionHeader extends StatelessWidget {
  const _RemoteSessionHeader({
    required this.session,
    required this.connection,
    required this.onDisconnect,
  });

  final KitchenRemoteSession session;
  final KitchenConnectionState connection;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final title = _RemoteScreenTitle(
                    session: session,
                    color: scheme.onSurface.withValues(alpha: 0.62),
                  );
                  final badge = _RemoteConnectionBadge(connection: connection);

                  if (constraints.maxWidth < 430) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 8),
                        badge,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 12),
                      badge,
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _remoteSessionStatusLabel(session.status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KitchenTypography.meta(context).copyWith(
                        color: _remoteSessionStatusColor(session.status),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('kitchen-remote-disconnect'),
                    onPressed: onDisconnect,
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('DISSOCIER'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoteScreenTitle extends StatelessWidget {
  const _RemoteScreenTitle({
    required this.session,
    required this.color,
  });

  final KitchenRemoteSession session;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ÉCRAN ASSOCIÉ',
          style: KitchenTypography.meta(context).copyWith(
            color: color,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          session.screenName.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
        ),
      ],
    );
  }
}

class _RemoteConnectionBadge extends StatelessWidget {
  const _RemoteConnectionBadge({required this.connection});

  final KitchenConnectionState connection;

  @override
  Widget build(BuildContext context) {
    final colors = _connectionColors(connection.status);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: colors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(colors.icon, size: 15, color: colors.foreground),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  kitchenRemoteConnectionLabel(connection),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KitchenTypography.meta(context).copyWith(
                    color: colors.foreground,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
String kitchenRemoteConnectionLabel(KitchenConnectionState connection) {
  final base = switch (connection.status) {
    KitchenConnectionStatus.online => 'ONLINE',
    KitchenConnectionStatus.reconnecting => 'RECONNEXION',
    KitchenConnectionStatus.offline => 'HORS CONNEXION',
  };

  final pending = connection.pendingActions;
  if (pending <= 0) {
    return base;
  }

  final suffix = pending == 1 ? 'ACTION EN ATTENTE' : 'ACTIONS EN ATTENTE';
  return '$base · $pending $suffix';
}

class _RemoteQueueChangedBanner extends StatelessWidget {
  const _RemoteQueueChangedBanner({required this.onReturnToLive});

  final VoidCallback onReturnToLive;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.infoBg,
        border: Border(bottom: BorderSide(color: AppColors.infoAlt)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            const Icon(Icons.sync_outlined, color: AppColors.infoAlt, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'FILE MISE À JOUR',
                style: KitchenTypography.meta(context).copyWith(
                  color: AppColors.infoAlt,
                  fontSize: 12,
                ),
              ),
            ),
            TextButton(
              key: const Key('kitchen-remote-return-live'),
              onPressed: onReturnToLive,
              child: const Text('REVENIR AU DIRECT'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteTicketMeta extends StatelessWidget {
  const _RemoteTicketMeta({required this.ticket});

  final KitchenTicketViewModel ticket;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tableNumber = ticket.order.tableNumber?.trim();
    final label = tableNumber != null && tableNumber.isNotEmpty
        ? 'TABLE $tableNumber'
        : humanOrderType(ticket.order.orderType).toUpperCase();

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KitchenTypography.meta(context).copyWith(
              color: scheme.onSurface.withValues(alpha: 0.70),
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _KitchenRemoteUnavailableView extends ConsumerWidget {
  const _KitchenRemoteUnavailableView({
    required this.session,
    this.message,
  });

  final KitchenRemoteSession session;
  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(kitchenConnectionStateProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RemoteSessionHeader(
          session: session,
          connection: connection,
          onDisconnect: () => _confirmDisconnect(context, ref, session),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.phonelink_erase_outlined,
                    size: 46,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message ?? 'SESSION INDISPONIBLE',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('kitchen-remote-retry'),
                      onPressed: () {
                        ref.read(kitchenRemoteSessionProvider.notifier).retry();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('RÉESSAYER'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmDisconnect(
                        context,
                        ref,
                        session,
                      ),
                      icon: const Icon(Icons.link_off),
                      label: const Text('DISSOCIER'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KitchenRemoteErrorBody extends ConsumerWidget {
  const _KitchenRemoteErrorBody({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
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
              'CHARGEMENT REMOTE IMPOSSIBLE',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
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
    );
  }
}

Future<void> _confirmDisconnect(
  BuildContext context,
  WidgetRef ref,
  KitchenRemoteSession session,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('DISSOCIER'),
        content: Text(
          'Dissocier ce téléphone de ${session.screenName} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ANNULER'),
          ),
          FilledButton(
            key: const Key('kitchen-remote-disconnect-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DISSOCIER'),
          ),
        ],
      );
    },
  );

  if (confirmed ?? false) {
    ref.read(kitchenRemoteSessionProvider.notifier).disconnect();
  }
}

int _prepTimeNormalMinutes(int? value) {
  if (value == null || value <= 0) {
    return defaultKitchenPrepTimeNormalMinutes;
  }
  return value;
}

String _remoteSessionStatusLabel(KitchenRemoteSessionStatus status) {
  return switch (status) {
    KitchenRemoteSessionStatus.disconnected => 'DÉCONNECTÉ',
    KitchenRemoteSessionStatus.connected => 'CONNECTÉ · Session active',
    KitchenRemoteSessionStatus.unavailable => 'SESSION INDISPONIBLE',
  };
}

Color _remoteSessionStatusColor(KitchenRemoteSessionStatus status) {
  return switch (status) {
    KitchenRemoteSessionStatus.disconnected => AppColors.neutral,
    KitchenRemoteSessionStatus.connected => AppColors.success,
    KitchenRemoteSessionStatus.unavailable => AppColors.danger,
  };
}

_ConnectionColors _connectionColors(KitchenConnectionStatus status) {
  return switch (status) {
    KitchenConnectionStatus.online => const _ConnectionColors(
        background: AppColors.successBg,
        border: AppColors.success,
        foreground: AppColors.textPrimary,
        icon: Icons.wifi_outlined,
      ),
    KitchenConnectionStatus.reconnecting => const _ConnectionColors(
        background: AppColors.warningSoftBg,
        border: AppColors.warning,
        foreground: AppColors.textPrimary,
        icon: Icons.sync_outlined,
      ),
    KitchenConnectionStatus.offline => const _ConnectionColors(
        background: AppColors.dangerBg,
        border: AppColors.danger,
        foreground: AppColors.dangerAlt,
        icon: Icons.wifi_off_outlined,
      ),
  };
}

class _ConnectionColors {
  const _ConnectionColors({
    required this.background,
    required this.border,
    required this.foreground,
    required this.icon,
  });

  final Color background;
  final Color border;
  final Color foreground;
  final IconData icon;
}
