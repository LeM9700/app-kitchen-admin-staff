import 'dart:async';

import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:flutter/material.dart';

class LiveCountdown extends StatefulWidget {
  const LiveCountdown({required this.target, this.style, super.key});

  final DateTime? target;
  final TextStyle? style;

  @override
  State<LiveCountdown> createState() => _LiveCountdownState();
}

class _LiveCountdownState extends State<LiveCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = widget.style ?? const TextStyle();
    final target = widget.target;
    if (target == null) {
      return Text(
        'Pas de DLC',
        style: baseStyle.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    final remaining = target.toLocal().difference(DateTime.now());
    return Text(
      formatCountdown(remaining),
      style: baseStyle.copyWith(
        color: countdownColor(remaining),
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

String formatCountdown(Duration remaining) {
  if (remaining.isNegative) {
    return 'Expire';
  }
  String two(int value) => value.toString().padLeft(2, '0');
  final days = remaining.inDays;
  final hours = remaining.inHours % 24;
  final minutes = remaining.inMinutes % 60;
  final seconds = remaining.inSeconds % 60;
  return '${two(days)}:${two(hours)}:${two(minutes)}:${two(seconds)}';
}

Color countdownColor(Duration remaining) {
  if (remaining.isNegative) {
    return AppColors.danger;
  }
  if (remaining > const Duration(minutes: 10)) {
    return AppColors.success;
  }
  if (remaining >= const Duration(minutes: 5)) {
    return AppColors.warning;
  }
  return AppColors.danger;
}
