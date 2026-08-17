import 'dart:async';

import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_status_ui.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:flutter/material.dart';

class KitchenTicketHeader extends StatelessWidget {
  const KitchenTicketHeader({
    required this.ticket,
    this.compact = false,
    super.key,
  });

  final KitchenTicketViewModel ticket;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ui = KitchenStatusUi.from(ticket.state);
    final foreground = ui.foregroundColor();

    return DecoratedBox(
      decoration: BoxDecoration(color: ui.color),
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
              ).copyWith(color: foreground),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(ui.icon, size: compact ? 16 : 18, color: foreground),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      ui.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KitchenTypography.ticketStatus(
                        context,
                        compact: compact,
                      ).copyWith(color: foreground),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            KitchenPreparationTimer(
              confirmedAt: ticket.confirmedAt,
              style: KitchenTypography.timer(
                context,
                compact: compact,
              ).copyWith(color: foreground),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: humanOrderType(ticket.order.orderType),
              child: Icon(
                kitchenOrderTypeIcon(ticket.order.orderType),
                color: foreground,
                size: compact ? 20 : 23,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class KitchenPreparationTimer extends StatefulWidget {
  const KitchenPreparationTimer({
    required this.confirmedAt,
    this.style,
    super.key,
  });

  final DateTime? confirmedAt;
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
    if (oldWidget.confirmedAt != widget.confirmedAt) {
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

    return Text(
      confirmedAt == null
          ? '--:--'
          : formatKitchenPreparationElapsed(confirmedAt),
      style: widget.style,
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
