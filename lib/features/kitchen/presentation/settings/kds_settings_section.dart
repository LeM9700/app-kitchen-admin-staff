import 'dart:async';

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
import 'package:flutter/services.dart';
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
///
/// Décisions Task 5 (code de pairing + révocation) :
/// - Le dialog "CODE D'ASSOCIATION" reste un `AlertDialog` sobre (comme les
///   autres dialogs de ce fichier) plutôt qu'un `showModalBottomSheet` ou le
///   thème sombre spectaculaire de `kitchen_remote_page.dart` — cohérent
///   avec le ton "administratif" de Settings demandé par le brief.
/// - Le countdown "Expire dans MM:SS" est isolé dans `_PairingCountdown`
///   (son propre `Timer.periodic`, annulé dans `dispose()`), qui ne
///   notifie son parent (`_PairingCodeDialog`) qu'une seule fois, via
///   `onExpired`, au moment où le compte à rebours atteint zéro — c'est la
///   seule occasion où le dialog parent doit se reconstruire (pour basculer
///   vers "CODE EXPIRÉ" + le bouton de régénération), pas à chaque seconde.
/// - Régénérer un code remplace entièrement l'état `_code` du dialog :
///   l'ancien code n'est jamais réaffiché après un appel réussi à
///   `generatePairingCode`.
/// - L'espace médian dans "482 731" est purement visuel
///   (`_formatPairingCodeDisplay`) ; `_code.code` reste `"482731"` partout
///   ailleurs (copie, comparaisons).
/// - "RÉVOQUER LES TÉLÉCOMMANDES" (admin uniquement) exige une confirmation
///   `AlertDialog` ; le `SnackBar` de résultat ne s'affiche que si
///   `revokeScreenSessions` renvoie un `int` non nul (`null` = échec déjà
///   remonté par le `ref.listen(actionError, ...)` existant de Task 4).
///   Aucun compteur de sessions actives n'est affiché avant l'action (non
///   exposé par le backend).
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
            subtitle: mapKdsError(error),
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
              onRevokeSessions: isAdmin
                  ? () => _revokeSessionsDialog(context, ref, screen)
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
      builder: (context) => _PairingCodeDialog(
        screen: screen,
        initialCode: code,
        onRegenerate: () => ref
            .read(kdsScreenManagementProvider.notifier)
            .generatePairingCode(screenId: screen.id),
      ),
    );
  }

  Future<void> _revokeSessionsDialog(
    BuildContext context,
    WidgetRef ref,
    KdsScreen screen,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Révoquer toutes les télécommandes associées à '
          '« ${screen.name} » ?',
        ),
        content: const Text(
          'Les téléphones actuellement associés à cet écran perdront leur '
          'session et devront ressaisir un nouveau code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Révoquer'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final result = await ref
        .read(kdsScreenManagementProvider.notifier)
        .revokeScreenSessions(screenId: screen.id);
    if (result == null || !context.mounted) {
      // `null` signifie un échec déjà remonté par le `ref.listen` de
      // `actionError` (Task 4) : ne pas afficher de SnackBar ici.
      return;
    }
    _snack(
      context,
      result > 0
          ? '$result télécommande(s) révoquée(s)'
          : 'Aucune télécommande active',
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
      // `createScreen` returns the structured error code directly (`null`
      // on success) instead of `void`. This is required, not cosmetic: the
      // section's own `ref.listen(actionError)` (Task 4) fires synchronously
      // the instant the controller sets `actionError`/`actionErrorCode` on
      // failure, shows the SnackBar, and immediately calls
      // `clearActionError()` — all before `await notifier.createScreen(...)`
      // below even returns. So by the time this line resumes, re-reading
      // `actionErrorCode` off `ref.read(kdsScreenManagementProvider)` would
      // already observe it wiped back to `null`, making the collision case
      // indistinguishable from success. Taking the code as a return value
      // sidesteps that race entirely.
      final errorCode = await notifier.createScreen(
        name: result.name,
        screenKey: buildKdsScreenKey(result.name),
        mode: result.mode,
        station: result.station,
        interactionMode: result.interactionMode,
        ticketsPerPage: result.ticketsPerPage,
      );
      if (errorCode == null) {
        // Succès : on ferme définitivement le flux.
        return;
      }
      if (errorCode != 'KDS_SCREEN_KEY_ALREADY_EXISTS') {
        // Tout autre échec (réseau, 403, erreur inconnue...) est déjà
        // remonté par le SnackBar de `ref.listen(actionError)` (Task 4) :
        // rouvrir le formulaire n'aurait de sens que pour un conflit
        // d'identifiant, où renommer est la bonne action de rattrapage.
        return;
      }
      if (!context.mounted) {
        return;
      }
      // Conflit d'identifiant (screen_key déjà utilisé) : on rouvre
      // immédiatement le dialog pré-rempli avec les valeurs saisies pour que
      // l'utilisateur puisse renommer et réessayer — pas de suffixe
      // aléatoire automatique.
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
    // `station` is only ever derived from the selected type in this form
    // (there's no free-text station field), while `screen.station` at the
    // model/repository level is an unconstrained string that may hold a
    // custom value (e.g. 'grill') that doesn't match any type's default. If
    // we diffed `result.station` against `screen.station` unconditionally,
    // an edit that only touches an unrelated field (name, tickets/page…)
    // would still compute a "changed" station and silently clobber that
    // custom value with the type-derived default. So station only follows
    // the diff when `mode` itself actually changed — that's the only case
    // where this form can legitimately express a new station.
    final modeChanged = result.mode != screen.mode;
    await ref.read(kdsScreenManagementProvider.notifier).updateScreen(
          screenId: screen.id,
          name: result.name != screen.name ? result.name : null,
          mode: modeChanged ? result.mode : null,
          station: modeChanged ? result.station : null,
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
    this.onRevokeSessions,
  });

  final KdsScreen screen;
  final bool isAdmin;
  final bool busy;
  final VoidCallback onGeneratePairingCode;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleActive;
  final VoidCallback? onRevokeSessions;

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
              if (isAdmin && onRevokeSessions != null)
                _ActionButton(
                  label: 'RÉVOQUER LES TÉLÉCOMMANDES',
                  icon: Icons.link_off,
                  busy: busy,
                  onPressed: onRevokeSessions!,
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

/// Dialog "ASSOCIER UN TÉLÉPHONE" ouvert par "CODE D'ASSOCIATION".
///
/// Détient localement le code de pairing courant (`_code`) et l'état
/// d'expiration (`_expired`) : régénérer un code remplace entièrement
/// `_code`, donc l'ancien code n'est jamais réaffiché après une
/// régénération réussie. Le décompte lui-même vit dans [_PairingCountdown]
/// (voir sa doc) pour ne pas reconstruire ce dialog à chaque seconde.
class _PairingCodeDialog extends StatefulWidget {
  const _PairingCodeDialog({
    required this.screen,
    required this.initialCode,
    required this.onRegenerate,
  });

  final KdsScreen screen;
  final KdsPairingCode initialCode;
  final Future<KdsPairingCode?> Function() onRegenerate;

  @override
  State<_PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends State<_PairingCodeDialog> {
  late KdsPairingCode _code;
  bool _expired = false;
  bool _regenerating = false;

  @override
  void initState() {
    super.initState();
    _code = widget.initialCode;
  }

  void _handleExpired() {
    if (!mounted) {
      return;
    }
    setState(() => _expired = true);
  }

  Future<void> _regenerate() async {
    setState(() => _regenerating = true);
    // L'échec (result == null) est déjà remonté par le ref.listen
    // d'actionError de la section parente (Task 4) : rien à afficher ici,
    // on reste simplement sur l'état "CODE EXPIRÉ" pour laisser l'admin
    // réessayer.
    final result = await widget.onRegenerate();
    if (!mounted) {
      return;
    }
    setState(() {
      _regenerating = false;
      if (result != null) {
        _code = result;
        _expired = false;
      }
    });
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _code.code));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CODE COPIÉ')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ASSOCIER UN TÉLÉPHONE'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            widget.screen.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _formatPairingCodeDisplay(_code.code),
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_expired) ...[
            Text(
              'CODE EXPIRÉ',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.danger,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: _regenerating ? null : _regenerate,
              icon: _regenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('GÉNÉRER UN NOUVEAU CODE'),
            ),
          ] else ...[
            _PairingCountdown(
              expiresAt: _code.expiresAt,
              onExpired: _handleExpired,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: _copyCode,
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('COPIER'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('FERMER'),
        ),
      ],
    );
  }
}

/// Décompte "Expire dans MM:SS" isolé de son parent : un `Timer.periodic`
/// interne se reconstruit lui-même chaque seconde (même pattern que
/// `lib/core/widgets/live_countdown.dart`), annulé dans `dispose()`. Le
/// parent ([_PairingCodeDialog]) n'est notifié qu'une seule fois, via
/// [onExpired], au moment où le compte à rebours atteint zéro — pas à
/// chaque tick — pour ne provoquer qu'une seule reconstruction du dialog
/// (bascule vers "CODE EXPIRÉ") au lieu d'une par seconde.
class _PairingCountdown extends StatefulWidget {
  const _PairingCountdown({
    required this.expiresAt,
    required this.onExpired,
  });

  final DateTime expiresAt;
  final VoidCallback onExpired;

  @override
  State<_PairingCountdown> createState() => _PairingCountdownState();
}

class _PairingCountdownState extends State<_PairingCountdown> {
  Timer? _timer;
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    // Vérifie l'expiration dès la première frame (cas limite : le code est
    // déjà expiré au moment où le dialog s'ouvre) sans appeler setState
    // pendant la phase de build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted || _notified) {
      return;
    }
    final remaining = widget.expiresAt.toLocal().difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _notified = true;
      _timer?.cancel();
      widget.onExpired();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt.toLocal().difference(DateTime.now());
    final display = remaining.isNegative ? Duration.zero : remaining;
    return Text(
      'Expire dans ${_formatPairingCountdown(display)}',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
    );
  }
}

/// Formate un code de pairing 6 chiffres avec un espace médian purement
/// visuel ("482731" -> "482 731"). Ne modifie jamais la valeur réelle du
/// code (utilisée telle quelle pour la copie et les appels API) et ne
/// convertit jamais le code en nombre (le zéro initial doit rester
/// visible, ex. "004281" -> "004 281").
String _formatPairingCodeDisplay(String code) {
  if (code.length != 6) {
    return code;
  }
  return '${code.substring(0, 3)} ${code.substring(3)}';
}

/// Formate une durée restante en `MM:SS` (jamais `DD:HH:MM:SS` — un code de
/// pairing expire toujours en quelques minutes, jamais en jours/heures),
/// distinct de `formatCountdown` de `live_countdown.dart` qui cible un
/// tout autre usage (DLC produits).
String _formatPairingCountdown(Duration remaining) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(remaining.inMinutes)}:${two(remaining.inSeconds % 60)}';
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
