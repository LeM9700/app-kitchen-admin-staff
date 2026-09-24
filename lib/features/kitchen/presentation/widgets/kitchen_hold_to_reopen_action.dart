import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_visuals.dart';
import 'package:flutter/material.dart';

/// Duree de maintien requise pour repasser une station "prete" en
/// "preparation" depuis le KDS. Centralisee ici pour eviter un magic number
/// duplique entre le widget et ses tests (fakeAsync / pump).
const kitchenReopenHoldDuration = Duration(seconds: 2);

/// Bouton "maintien 2 secondes" affiche a la place du badge "poste pret"
/// quand une correction operationnelle (repasser la station en preparation)
/// est disponible. Le maintien complet EST la confirmation : aucune modale
/// n'est ouverte apres coup (cf. AGENTS.md LOT 12 B18).
class KitchenHoldToReopenAction extends StatefulWidget {
  const KitchenHoldToReopenAction({
    required this.label,
    required this.onHoldComplete,
    this.busy = false,
    this.compact = false,
    super.key,
  });

  final String label;
  final VoidCallback onHoldComplete;
  final bool busy;
  final bool compact;

  @override
  State<KitchenHoldToReopenAction> createState() {
    return _KitchenHoldToReopenActionState();
  }
}

class _KitchenHoldToReopenActionState extends State<KitchenHoldToReopenAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: kitchenReopenHoldDuration,
    )..addStatusListener(_onStatusChanged);
  }

  @override
  void didUpdateWidget(covariant KitchenHoldToReopenAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busy && !oldWidget.busy) {
      _cancelHold();
    }
  }

  @override
  void dispose() {
    _progress.removeStatusListener(_onStatusChanged);
    _progress.dispose();
    super.dispose();
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_triggered) {
      _triggered = true;
      widget.onHoldComplete();
    }
  }

  void _startHold() {
    if (!mounted || widget.busy || _triggered) {
      return;
    }
    _progress.forward(from: 0);
  }

  void _cancelHold() {
    // A successful hold can trigger a rebuild that unmounts this widget
    // (the ticket moves out of "ready") before the pointer-up/cancel event
    // for that same gesture is delivered -- touching the now-disposed
    // AnimationController would crash.
    if (!mounted) {
      return;
    }
    if (_progress.isAnimating) {
      _progress.stop();
    }
    _progress.value = 0;
    _triggered = false;
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.compact ? 46.0 : 54.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.compact ? 12 : 16,
        widget.compact ? 8 : 10,
        widget.compact ? 12 : 16,
        widget.compact ? 8 : 10,
      ),
      child: Listener(
        // Pointer events plutot que GestureDetector.onLongPress* : ce dernier
        // attend ~500ms avant de reconnaitre le maintien (delai cache qui
        // allongeait le maintien reel a ~2.5s) et annule silencieusement sur
        // un micro-mouvement de souris pendant cette fenetre de
        // reconnaissance. Listener demarre le minuteur des le pointer down,
        // sans ambiguite avec un tap/drag.
        onPointerDown: (_) => _startHold(),
        onPointerUp: (_) => _cancelHold(),
        onPointerCancel: (_) => _cancelHold(),
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.success),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.72),
                    offset: const Offset(-1, -1),
                    blurRadius: 3,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    offset: const Offset(1, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: SizedBox(
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _progress.value.clamp(0, 1),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.24),
                        ),
                      ),
                    ),
                    Center(
                      child: widget.busy
                          ? SizedBox.square(
                              dimension: widget.compact ? 17 : 19,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: KitchenVisuals.graphite,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  widget.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      KitchenTypography.meta(context).copyWith(
                                    color: KitchenVisuals.graphite,
                                    fontSize: widget.compact ? 12 : 14,
                                  ),
                                ),
                                Text(
                                  'MAINTENIR 2 S POUR REPASSER EN PRÉPARATION',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      KitchenTypography.meta(context).copyWith(
                                    color: KitchenVisuals.mutedText,
                                    fontSize: widget.compact ? 8 : 9,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
