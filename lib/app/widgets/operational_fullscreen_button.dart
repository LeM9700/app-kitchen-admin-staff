import 'package:app_admin_staff/app/operational_fullscreen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OperationalFullscreenButton extends ConsumerWidget {
  const OperationalFullscreenButton({
    this.style,
    super.key,
  });

  final ButtonStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fullscreen = ref.watch(operationalFullscreenProvider);
    return IconButton.filledTonal(
      tooltip: fullscreen ? 'Quitter le plein écran' : 'Plein écran',
      style: style,
      onPressed: () {
        ref.read(operationalFullscreenProvider.notifier).state = !fullscreen;
      },
      icon: Icon(
        fullscreen
            ? Icons.fullscreen_exit_outlined
            : Icons.fullscreen_outlined,
      ),
    );
  }
}
