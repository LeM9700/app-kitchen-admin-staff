import 'dart:async';

import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_visuals.dart';
import 'package:flutter/material.dart';

class KitchenReadyTransition extends StatefulWidget {
  const KitchenReadyTransition({
    required this.active,
    required this.child,
    super.key,
  });

  final bool active;
  final Widget child;

  @override
  State<KitchenReadyTransition> createState() => _KitchenReadyTransitionState();
}

class _KitchenReadyTransitionState extends State<KitchenReadyTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      reverseDuration: const Duration(milliseconds: 300),
    );
    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ).drive(Tween<double>(begin: 0.82, end: 1));
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    if (widget.active) {
      _showCheck();
    }
  }

  @override
  void didUpdateWidget(covariant KitchenReadyTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      _showCheck();
    } else if (oldWidget.active && !widget.active) {
      _hideCheck();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _opacity.value,
                    child: Transform.scale(
                      scale: _scale.value,
                      child: child,
                    ),
                  );
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.75),
                      width: 1.5,
                    ),
                    boxShadow: KitchenVisuals.ticketShadow(focused: false),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.check_rounded,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showCheck() {
    _hideTimer?.cancel();
    _controller.forward(from: 0);
    _hideTimer = Timer(const Duration(seconds: 6), _hideCheck);
  }

  void _hideCheck() {
    _hideTimer?.cancel();
    if (_controller.status != AnimationStatus.dismissed) {
      _controller.reverse();
    }
  }
}
