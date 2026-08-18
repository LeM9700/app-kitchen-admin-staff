import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/kitchen/application/kds_screen_management_controller.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/domain/kds_screen_key.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_screen_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Écrans & postes KDS — section de `SettingsPage`.
///
/// Décisions "au choix, documente" prises dans cette tâche (voir aussi le
/// rapport de tâche) :
/// - `isAdmin` est le seul paramètre transmis par `SettingsPage` : le widget
///   n'est monté que si l'utilisateur est admin OU a la permission
///   `orders:preparation` (gating fait dans `SettingsPage`), donc
///   "CODE D'ASSOCIATION" peut être affiché inconditionnellement pour tout
///   utilisateur qui atteint ce widget.
/// - Les libellés de mode ("CUISINE"/"COMPTOIR"/"SERVICE") réutilisent
///   `kitchenScreenModeLabel` via une conversion locale `String -> enum`
///   (le raw backend n'a pas d'enum dédié), avec repli sur la chaîne brute
///   en majuscule si la valeur est inconnue.
/// - La ligne "Poste : ${screen.station}" est toujours affichée (valeur
///   brute backend, non traduite) — cohérent avec l'exemple visuel de la
///   spec, y compris pour un poste custom futur.
/// - Le bouton "+ AJOUTER UN ÉCRAN" au-dessus de la liste sert aussi de
///   bouton pour l'état vide admin (pas de bouton dupliqué dans l'état
///   vide lui-même).
/// - Le dialog "CODE D'ASSOCIATION" affiche le code et l'heure d'expiration
///   brute (HH:mm) — version minimale fonctionnelle, la Task 5 l'enrichit
///   avec un countdown dans ce même fichier.
/// - "RÉVOQUER LES TÉLÉCOMMANDES" n'est pas implémenté ici (Task 5).
class KdsSettingsSection extends ConsumerWidget {
  const KdsSettingsSection({required this.isAdmin, super.key});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(kdsScreenManagementProvider);

    ref.listen<AsyncValue<KdsScreenManagementState>>(
      kdsScreenManagementProvider,
      (previous, next) {
        final error = next.valueOrNull?.actionError;
        if (error == null) {
          return;
        }
        if (error == previous?.valueOrNull?.actionError) {
          return;
        }
        _snack(context, error);
        ref.read(kdsScreenManagementProvider.notifier).clearActionError();
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ÉCRANS & POSTES', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Configurez les écrans Cuisine, Comptoir et Service.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
        const SizedBox(height: AppSpacing.md),
        asyncState.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, stackTrace) => EmptyState(
            icon: Icons.error_outline,
            title: 'Écrans indisponibles',
            subtitle: _loadErrorMessage(error),
          ),
          data: (value) => _buildContent(context, ref, value),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    KdsScreenManagementState value,
  ) {
    final screens = isAdmin
        ? value.screens
        : value.screens.where((screen) => screen.isActive).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isAdmin) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed:
                  value.creating ? null : () => _createDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('+ AJOUTER UN ÉCRAN'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (screens.isEmpty)
          EmptyState(
            icon: Icons.desktop_windows_outlined,
            title: isAdmin
                ? 'Aucun écran KDS configuré.'
                : 'Aucun écran disponible.',
            subtitle: isAdmin
                ? null
                : 'Demandez à un administrateur de configurer un écran.',
          )
        else
          for (final screen in screens) ...[
            _KdsScreenCard(
              screen: screen,
              isAdmin: isAdmin,
              busy: value.busyScreenIds.contains(screen.id),
              onGeneratePairingCode: () =>
                  _pairingCodeDialog(context, ref, screen),
              onEdit: isAdmin ? () => _editDialog(context, ref, screen) : null,
              onToggleActive: isAdmin
                  ? () => _deactivateDialog(context, ref, screen)
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
      ],
    );
  }

  Future<void> _pairingCodeDialog(
    BuildContext context,
    WidgetRef ref,
    KdsScreen screen,
  ) async {
    final code = await ref
        .read(kdsScreenManagementProvider.notifier)
        .generatePairingCode(screenId: screen.id);
    if (code == null || !context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Code d'association — ${screen.name}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              code.code,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Expire à ${formatTime(code.expiresAt)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _createDialog(BuildContext context, WidgetRef ref) async {
    String? initialName;
    String? initialMode;
    String? initialInteractionMode;
    int? initialTicketsPerPage;

    while (true) {
      final result = await _screenFormDialog(
        context,
        title: 'Ajouter un écran',
        confirmLabel: 'CRÉER',
        initialName: initialName,
        initialMode: initialMode,
        initialInteractionMode: initialInteractionMode,
        initialTicketsPerPage: initialTicketsPerPage,
      );
      if (result == null) {
        return;
      }
      final notifier = ref.read(kdsScreenManagementProvider.notifier);
      final before =
          ref.read(kdsScreenManagementProvider).valueOrNull?.screens.length ??
              0;
      await notifier.createScreen(
        name: result.name,
        screenKey: buildKdsScreenKey(result.name),
        mode: result.mode,
        station: result.station,
        interactionMode: result.interactionMode,
        ticketsPerPage: result.ticketsPerPage,
      );
      final after =
          ref.read(kdsScreenManagementProvider).valueOrNull?.screens.length ??
              0;
      if (after > before) {
        return;
      }
      if (!context.mounted) {
        return;
      }
      // Échec (ex: identifiant déjà utilisé) : on rouvre immédiatement le
      // dialog pré-rempli avec les valeurs saisies pour que l'utilisateur
      // puisse renommer et réessayer — pas de suffixe aléatoire automatique.
      initialName = result.name;
      initialMode = result.mode;
      initialInteractionMode = result.interactionMode;
      initialTicketsPerPage = result.ticketsPerPage;
    }
  }

  Future<void> _editDialog(
    BuildContext context,
    WidgetRef ref,
    KdsScreen screen,
  ) async {
    final result = await _screenFormDialog(
      context,
      title: "Modifier l'écran",
      confirmLabel: 'ENREGISTRER',
      initialName: screen.name,
      initialMode: screen.mode,
      initialInteractionMode: screen.interactionMode,
      initialTicketsPerPage: screen.ticketsPerPage,
    );
    if (result == null) {
      return;
    }
    await ref.read(kdsScreenManagementProvider.notifier).updateScreen(
          screenId: screen.id,
          name: result.name != screen.name ? result.name : null,
          mode: result.mode != screen.mode ? result.mode : null,
          station: result.station != screen.station ? result.station : null,
          interactionMode: result.interactionMode != screen.interactionMode
              ? result.interactionMode
              : null,
          ticketsPerPage: result.ticketsPerPage != screen.ticketsPerPage
              ? result.ticketsPerPage
              : null,
        );
  }

  Future<void> _deactivateDialog(
    BuildContext context,
    WidgetRef ref,
    KdsScreen screen,
  ) async {
    final notifier = ref.read(kdsScreenManagementProvider.notifier);
    if (!screen.isActive) {
      await notifier.updateScreen(screenId: screen.id, isActive: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Désactiver l'écran « ${screen.name} » ?"),
        content: const Text(
          'Les nouvelles associations ne seront plus possibles sur cet écran.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await notifier.updateScreen(screenId: screen.id, isActive: false);
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ScreenTypeOption {
  const _ScreenTypeOption({
    required this.mode,
    required this.station,
    required this.label,
  });

  final String mode;
  final String station;
  final String label;
}

const _screenTypes = <_ScreenTypeOption>[
  _ScreenTypeOption(mode: 'kitchen', station: 'kitchen', label: 'Cuisine'),
  _ScreenTypeOption(mode: 'counter', station: 'counter', label: 'Comptoir'),
  _ScreenTypeOption(mode: 'service', station: 'service', label: 'Service'),
];

class _ScreenFormResult {
  const _ScreenFormResult({
    required this.name,
    required this.mode,
    required this.station,
    required this.interactionMode,
    required this.ticketsPerPage,
  });

  final String name;
  final String mode;
  final String station;
  final String interactionMode;
  final int ticketsPerPage;
}

Future<_ScreenFormResult?> _screenFormDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? initialName,
  String? initialMode,
  String? initialInteractionMode,
  int? initialTicketsPerPage,
}) {
  final nameController = TextEditingController(text: initialName ?? '');
  var mode = _screenTypes.any((option) => option.mode == initialMode)
      ? initialMode!
      : _screenTypes.first.mode;
  var interactionMode = initialInteractionMode ?? 'wall';
  var ticketsPerPage = initialTicketsPerPage ?? 4;

  return showDialog<_ScreenFormResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "Nom de l'écran",
                    hintText: 'Cuisine principale',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final option in _screenTypes)
                      DropdownMenuItem(
                        value: option.mode,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: (value) => setState(() => mode = value ?? mode),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: interactionMode,
                  decoration: const InputDecoration(labelText: 'Mode'),
                  items: const [
                    DropdownMenuItem(value: 'wall', child: Text('Mural')),
                    DropdownMenuItem(value: 'touch', child: Text('Tactile')),
                  ],
                  onChanged: (value) => setState(
                    () => interactionMode = value ?? interactionMode,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<int>(
                  initialValue: ticketsPerPage,
                  decoration:
                      const InputDecoration(labelText: 'Commandes par page'),
                  items: [
                    for (var count = 1; count <= 8; count++)
                      DropdownMenuItem(value: count, child: Text('$count')),
                  ],
                  onChanged: (value) =>
                      setState(() => ticketsPerPage = value ?? ticketsPerPage),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  return;
                }
                final selected = _screenTypes.firstWhere(
                  (option) => option.mode == mode,
                  orElse: () => _screenTypes.first,
                );
                Navigator.pop(
                  context,
                  _ScreenFormResult(
                    name: name,
                    mode: selected.mode,
                    station: selected.station,
                    interactionMode: interactionMode,
                    ticketsPerPage: ticketsPerPage,
                  ),
                );
              },
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    ),
  );
}

class _KdsScreenCard extends StatelessWidget {
  const _KdsScreenCard({
    required this.screen,
    required this.isAdmin,
    required this.busy,
    required this.onGeneratePairingCode,
    this.onEdit,
    this.onToggleActive,
  });

  final KdsScreen screen;
  final bool isAdmin;
  final bool busy;
  final VoidCallback onGeneratePairingCode;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleActive;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      _modeLabel(screen.mode),
      _interactionModeLabel(screen.interactionMode),
      '${screen.ticketsPerPage} commandes/page',
    ].join(' · ');

    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  screen.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusBadge(
                label: screen.isActive ? 'ACTIF' : 'INACTIF',
                tone: screen.isActive ? StatusTone.success : StatusTone.neutral,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Poste : ${screen.station}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ActionButton(
                label: "CODE D'ASSOCIATION",
                icon: Icons.qr_code_outlined,
                busy: busy,
                onPressed: onGeneratePairingCode,
              ),
              if (isAdmin && onEdit != null)
                _ActionButton(
                  label: 'MODIFIER',
                  icon: Icons.edit_outlined,
                  busy: busy,
                  onPressed: onEdit!,
                ),
              if (isAdmin && onToggleActive != null)
                _ActionButton(
                  label: screen.isActive ? 'DÉSACTIVER' : 'ACTIVER',
                  icon: screen.isActive
                      ? Icons.toggle_off_outlined
                      : Icons.toggle_on_outlined,
                  busy: busy,
                  onPressed: onToggleActive!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: OutlinedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

String _interactionModeLabel(String value) {
  return switch (value) {
    'wall' => 'Mural',
    'touch' => 'Tactile',
    _ => value.isEmpty ? '-' : value,
  };
}

String _modeLabel(String rawMode) {
  final mode = switch (rawMode) {
    'kitchen' => KitchenScreenMode.kitchen,
    'counter' => KitchenScreenMode.counter,
    'service' => KitchenScreenMode.service,
    _ => null,
  };
  if (mode == null) {
    return rawMode.isEmpty ? '-' : rawMode.toUpperCase();
  }
  return kitchenScreenModeLabel(mode);
}

String _loadErrorMessage(Object error) {
  if (error is AppException) {
    return error.message;
  }
  return 'UNE ERREUR EST SURVENUE';
}
