import 'dart:async';

import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_actions_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_time.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_status_ui.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ready_transition.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_actions.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_header.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_items.dart';
import 'package:flutter/material.dart';

class KitchenTicket extends StatefulWidget {
  const KitchenTicket({
    required this.ticket,
    required this.focused,
    this.profile = const KitchenScreenProfile(
      mode: KitchenScreenMode.kitchen,
      station: 'kitchen',
    ),
    this.actionsState = const KitchenActionsState(),
    this.prepTimeNormalMinutes = defaultKitchenPrepTimeNormalMinutes,
    this.onTap,
    this.onStart,
    this.onReady,
    this.compact = false,
    super.key,
  });

  final KitchenTicketViewModel ticket;
  final bool focused;
  final KitchenScreenProfile profile;
  final KitchenActionsState actionsState;
  final int prepTimeNormalMinutes;
  final VoidCallback? onTap;
  final VoidCallback? onStart;
  final VoidCallback? onReady;
  final bool compact;

  @override
  State<KitchenTicket> createState() => _KitchenTicketState();
}

class _KitchenTicketState extends State<KitchenTicket> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(KitchenTicket oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ticket.confirmedAt != widget.ticket.confirmedAt) {
      _timer?.cancel();
      _timer = null;
      _startTimerIfNeeded();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusUi = KitchenStatusUi.from(widget.ticket.state);
    final urgency = resolveKitchenUrgency(
      confirmedAt: widget.ticket.confirmedAt,
      now: DateTime.now(),
      prepTimeNormalMinutes: widget.prepTimeNormalMinutes,
    );
    final isLate = urgency == KitchenUrgency.late;
    final borderColor = isLate
        ? AppColors.danger
        : widget.focused
            ? scheme.primary
            : scheme.outlineVariant;
    final borderWidth = isLate ? 2.0 : (widget.focused ? 3.0 : 1.0);
    final surface = widget.focused
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.08),
            scheme.surface,
          )
        : scheme.surface;

    final card = KitchenReadyTransition(
      active: widget.ticket.state == KitchenTicketState.ready,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: widget.focused
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.28),
                    blurRadius: 0,
                    spreadRadius: isLate ? 3 : 2,
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            side: BorderSide(color: borderColor, width: borderWidth),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KitchenTapRegion(
                onTap: widget.onTap,
                child: KitchenTicketHeader(
                  ticket: widget.ticket,
                  compact: widget.compact,
                  prepTimeNormalMinutes: widget.prepTimeNormalMinutes,
                ),
              ),
              Expanded(
                child: _KitchenTapRegion(
                  onTap: widget.onTap,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: widget.ticket.isLocked
                              ? statusUi.color
                              : Colors.transparent,
                          width: widget.ticket.isLocked ? 4 : 0,
                        ),
                      ),
                    ),
                    child: KitchenTicketItems(
                      items: widget.ticket.visibleItems,
                      compact: widget.compact,
                    ),
                  ),
                ),
              ),
              KitchenTicketActions(
                ticket: widget.ticket,
                profile: widget.profile,
                actionsState: widget.actionsState,
                compact: widget.compact,
                onStart: widget.onStart,
                onReady: widget.onReady,
              ),
              _KitchenTapRegion(
                onTap: widget.onTap,
                child: _KitchenTicketMeta(ticket: widget.ticket),
              ),
            ],
          ),
        ),
      ),
    );

    return card;
  }

  void _startTimerIfNeeded() {
    if (widget.ticket.confirmedAt == null) {
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }
}

class _KitchenTapRegion extends StatelessWidget {
  const _KitchenTapRegion({
    required this.child,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return child;
    }

    return InkWell(
      onTap: onTap,
      child: child,
    );
  }
}

class _KitchenTicketMeta extends StatelessWidget {
  const _KitchenTicketMeta({required this.ticket});

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KitchenTypography.meta(context).copyWith(
              color: scheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
        ),
      ),
    );
  }
}
