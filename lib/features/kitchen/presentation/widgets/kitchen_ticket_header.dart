import 'dart:async';

import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_time.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_status_ui.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_visuals.dart';
import 'package:flutter/material.dart';

class KitchenTicketHeader extends StatelessWidget {
  const KitchenTicketHeader({
    required this.ticket,
    this.compact = false,
    this.prepTimeNormalMinutes = defaultKitchenPrepTimeNormalMinutes,
    super.key,
  });

  final KitchenTicketViewModel ticket;
  final bool compact;
  final int prepTimeNormalMinutes;

  @override
  Widget build(BuildContext context) {
    final ui = KitchenStatusUi.from(ticket.state);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: KitchenVisuals.ticketHeaderSurface,
        border: Border(
          bottom: BorderSide(color: KitchenVisuals.warmBorder),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 10 : 12,
        ),
        child: Row(
          children: [
            Text(
              '#${ticket.order.id}',
              style: KitchenTypography.ticketNumber(
                context,
                compact: compact,
              ).copyWith(color: KitchenVisuals.graphite),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ui.background,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: ui.color.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 8 : 10,
                          vertical: compact ? 5 : 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              ui.icon,
                              size: compact ? 14 : 16,
                              color: ui.color,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                ui.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: KitchenTypography.ticketStatus(
                                  context,
                                  compact: compact,
                                ).copyWith(
                                  color: KitchenVisuals.graphite,
                                  fontSize: compact ? 10 : 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _TimerCapsule(
              compact: compact,
              child: KitchenPreparationTimer(
                confirmedAt: ticket.confirmedAt,
                prepTimeNormalMinutes: prepTimeNormalMinutes,
                style: KitchenTypography.timer(
                  context,
                  compact: compact,
                ).copyWith(
                  color: KitchenVisuals.graphite,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: humanOrderType(ticket.order.orderType),
              child: Icon(
                kitchenOrderTypeIcon(ticket.order.orderType),
                color: KitchenVisuals.mutedText,
                size: compact ? 20 : 23,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerCapsule extends StatelessWidget {
  const _TimerCapsule({
    required this.child,
    required this.compact,
  });

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KitchenVisuals.recessedSurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: KitchenVisuals.warmBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.75),
            offset: const Offset(-1, -1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(1, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 5 : 6,
        ),
        child: child,
      ),
    );
  }
}

class KitchenPreparationTimer extends StatefulWidget {
  const KitchenPreparationTimer({
    required this.confirmedAt,
    this.prepTimeNormalMinutes = defaultKitchenPrepTimeNormalMinutes,
    this.style,
    super.key,
  });

  final DateTime? confirmedAt;
  final int prepTimeNormalMinutes;
  final TextStyle? style;

  @override
  State<KitchenPreparationTimer> createState() =>
      _KitchenPreparationTimerState();
}

class _KitchenPreparationTimerState extends State<KitchenPreparationTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(KitchenPreparationTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.confirmedAt != widget.confirmedAt ||
        oldWidget.prepTimeNormalMinutes != widget.prepTimeNormalMinutes) {
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
    final confirmedAt = widget.confirmedAt;
    final urgency = resolveKitchenUrgency(
      confirmedAt: confirmedAt,
      now: DateTime.now(),
      prepTimeNormalMinutes: widget.prepTimeNormalMinutes,
    );
    final style = urgency == KitchenUrgency.late
        ? widget.style?.copyWith(color: AppColors.danger) ??
            TextStyle(color: Theme.of(context).colorScheme.error)
        : widget.style;

    return Text(
      confirmedAt == null
          ? '--:--'
          : formatKitchenPreparationElapsed(confirmedAt),
      style: style,
    );
  }

  void _startTimerIfNeeded() {
    if (widget.confirmedAt == null) {
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }
}

String formatKitchenPreparationElapsed(
  DateTime confirmedAt, {
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  final elapsed = effectiveNow.difference(confirmedAt.toLocal());
  final seconds = elapsed.inSeconds.clamp(0, 1 << 31);
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;

  String two(int value) => value.toString().padLeft(2, '0');

  return '${two(minutes)}:${two(remainingSeconds)}';
}

IconData kitchenOrderTypeIcon(String orderType) {
  return switch (orderType) {
    'dine_in' => Icons.restaurant_outlined,
    'pickup' => Icons.takeout_dining_outlined,
    'delivery' => Icons.delivery_dining_outlined,
    _ => Icons.receipt_long_outlined,
  };
}
