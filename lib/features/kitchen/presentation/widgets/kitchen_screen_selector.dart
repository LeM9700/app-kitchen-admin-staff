import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_screen_presets.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:flutter/material.dart';

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
      tooltip: 'Profil ecran KDS',
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
            profile: profile,
            onProfileSelected: onProfileSelected,
          ),
        );
      },
    );
  }
}

class _KitchenScreenSelectorSheet extends StatelessWidget {
  const _KitchenScreenSelectorSheet({
    required this.profile,
    required this.onProfileSelected,
  });

  final KitchenScreenProfile profile;
  final ValueChanged<KitchenScreenProfile> onProfileSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PROFIL KDS', style: KitchenTypography.meta(context)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ProfileChip(
                key: const Key('kitchen-profile-mode-kitchen'),
                label: 'CUISINE',
                selected: profile.mode == KitchenScreenMode.kitchen,
                onSelected: () =>
                    _selectMode(context, KitchenScreenMode.kitchen),
              ),
              _ProfileChip(
                key: const Key('kitchen-profile-mode-counter'),
                label: 'COMPTOIR',
                selected: profile.mode == KitchenScreenMode.counter,
                onSelected: () =>
                    _selectMode(context, KitchenScreenMode.counter),
              ),
              _ProfileChip(
                key: const Key('kitchen-profile-mode-service'),
                label: 'SERVICE',
                selected: profile.mode == KitchenScreenMode.service,
                onSelected: () =>
                    _selectMode(context, KitchenScreenMode.service),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('INTERACTION', style: KitchenTypography.meta(context)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ProfileChip(
                key: const Key('kitchen-profile-interaction-wall'),
                label: 'MURAL',
                selected:
                    profile.interactionMode == KitchenInteractionMode.wall,
                onSelected: () =>
                    _selectInteraction(context, KitchenInteractionMode.wall),
              ),
              _ProfileChip(
                key: const Key('kitchen-profile-interaction-touch'),
                label: 'TACTILE',
                selected:
                    profile.interactionMode == KitchenInteractionMode.touch,
                onSelected: () =>
                    _selectInteraction(context, KitchenInteractionMode.touch),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _selectMode(BuildContext context, KitchenScreenMode mode) {
    _select(context, mode: mode, interactionMode: profile.interactionMode);
  }

  void _selectInteraction(
    BuildContext context,
    KitchenInteractionMode interactionMode,
  ) {
    _select(context, mode: profile.mode, interactionMode: interactionMode);
  }

  void _select(
    BuildContext context, {
    required KitchenScreenMode mode,
    required KitchenInteractionMode interactionMode,
  }) {
    onProfileSelected(
      kitchenScreenPresetFor(
        mode: mode,
        interactionMode: interactionMode,
        ticketsPerPage: profile.ticketsPerPage,
      ),
    );
    Navigator.of(context).pop();
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: true,
    );
  }
}
