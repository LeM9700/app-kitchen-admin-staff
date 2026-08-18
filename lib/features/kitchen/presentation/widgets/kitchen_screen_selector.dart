import 'package:app_admin_staff/features/kitchen/application/kds_active_screens_provider.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/domain/kds_screen_profile_mapper.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Real KDS screen selector for the kitchen board (LOT 11 Task 6).
///
/// Replaces the previous demo-preset picker: opening the bottom sheet loads
/// the tenant's active backend KDS screens (`kdsActiveScreensProvider`, which
/// calls `KdsRepository.listScreens()` with no `includeInactive` — so only
/// `isActive == true` screens come back) and lets the user pick one of them.
/// Selecting a screen applies `profileFromKdsScreen(screen)` through
/// `onProfileSelected` (unchanged signature/caller contract) and records the
/// pick in `kitchenSelectedScreenProvider` so `KitchenStatusHeader` can show
/// the screen's real name.
///
/// `kitchen_screen_presets.dart` / `kitchenScreenPresetFor` are intentionally
/// no longer used here — they remain in the codebase for other
/// tests/legacy call sites, but are not part of this widget's normal flow
/// anymore.
class KitchenScreenSelector extends StatelessWidget {
  const KitchenScreenSelector({
    required this.profile,
    required this.onProfileSelected,
    super.key,
  });

  final KitchenScreenProfile profile;
  final ValueChanged<KitchenScreenProfile> onProfileSelected;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      key: const Key('kitchen-screen-selector'),
      tooltip: 'Écran KDS',
      onPressed: () => _showSelector(context),
      icon: const Icon(Icons.display_settings_outlined),
    );
  }

  void _showSelector(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: _KitchenScreenSelectorSheet(
            onProfileSelected: onProfileSelected,
          ),
        );
      },
    );
  }
}

class _KitchenScreenSelectorSheet extends ConsumerWidget {
  const _KitchenScreenSelectorSheet({
    required this.onProfileSelected,
  });

  final ValueChanged<KitchenScreenProfile> onProfileSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screensAsync = ref.watch(kdsActiveScreensProvider);
    final selectedScreen = ref.watch(kitchenSelectedScreenProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ÉCRAN KDS', style: KitchenTypography.meta(context)),
          const SizedBox(height: 12),
          screensAsync.when(
            data: (screens) => _ScreenOptions(
              screens: screens,
              selectedScreen: selectedScreen,
              onSelected: (screen) => _select(context, ref, screen),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            // Erreur de chargement (API indisponible): on n'affiche JAMAIS un
            // fallback silencieux sur les presets `kitchen_screen_presets.dart`
            // et on ne touche à rien côté `kitchenQueueProvider` /
            // `kitchenScreenProfileProvider` — le board déjà chargé continue
            // de fonctionner avec son profil actuel.
            error: (error, stackTrace) => const Text(
              key: Key('kitchen-screen-selector-error'),
              'Impossible de charger les écrans',
            ),
          ),
        ],
      ),
    );
  }

  void _select(BuildContext context, WidgetRef ref, KdsScreen screen) {
    ref.read(kitchenSelectedScreenProvider.notifier).state = screen;
    onProfileSelected(profileFromKdsScreen(screen));
    Navigator.of(context).pop();
  }
}

class _ScreenOptions extends StatelessWidget {
  const _ScreenOptions({
    required this.screens,
    required this.selectedScreen,
    required this.onSelected,
  });

  final List<KdsScreen> screens;
  final KdsScreen? selectedScreen;
  final ValueChanged<KdsScreen> onSelected;

  @override
  Widget build(BuildContext context) {
    if (screens.isEmpty) {
      return const Text('Aucun écran actif');
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final screen in screens)
          ChoiceChip(
            key: Key('kitchen-screen-option-${screen.id}'),
            label: Text(screen.name),
            selected: selectedScreen?.id == screen.id,
            onSelected: (_) => onSelected(screen),
            showCheckmark: true,
          ),
      ],
    );
  }
}
