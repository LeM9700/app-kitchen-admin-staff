import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:flutter/material.dart';

class KitchenPaginationBar extends StatelessWidget {
  const KitchenPaginationBar({
    required this.state,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final KitchenQueueState state;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canGoPrevious = state.currentPage > 0;
    final canGoNext = state.currentPage < state.totalPages - 1;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              IconButton(
                key: const Key('kitchen-previous-page'),
                tooltip: 'Page précédente',
                onPressed: canGoPrevious ? onPrevious : null,
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (state.totalPages == 0)
                      Text(
                        '0 PAGE',
                        style: Theme.of(context).textTheme.labelLarge,
                      )
                    else
                      for (var page = 0; page < state.totalPages; page++)
                        _PageDot(active: page == state.currentPage),
                    if (state.remainingItems > 0)
                      Text(
                        '+${state.remainingItems}',
                        key: const Key('kitchen-remaining-items'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    if (state.queueChangedWhileBrowsing)
                      const _QueueChangedBadge(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('kitchen-next-page'),
                tooltip: 'Page suivante',
                onPressed: canGoNext ? onNext : null,
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageDot extends StatelessWidget {
  const _PageDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: active ? 13 : 10,
      height: active ? 13 : 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? scheme.primary : Colors.transparent,
        border: Border.all(
          color: active ? scheme.primary : scheme.outline,
          width: 2,
        ),
      ),
    );
  }
}

class _QueueChangedBadge extends StatelessWidget {
  const _QueueChangedBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.infoAlt),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          'FILE MISE À JOUR',
          style: Theme.of(context).textTheme.labelLarge!.copyWith(
                color: AppColors.infoAlt,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
        ),
      ),
    );
  }
}
