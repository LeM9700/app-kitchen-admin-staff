import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Valeur « revenir au reglage general » dans les listes de regles d'echec.
const _inherit = -1;

/// Reglages de livraison de l'etablissement courant : qui attribue les courses (comptoir ou
/// livreur), plafond de livraisons en cours par livreur, regles d'echec propres au site.
/// Modifiable par un administrateur ; un conflit de version recharge les valeurs.
class EstablishmentDispatchCard extends ConsumerWidget {
  const EstablishmentDispatchCard({required this.isAdmin, super.key});

  final bool isAdmin;

  static const waitOptions = [0, 2, 5, 10, 15, 20, 30, 45, 60];
  static const callOptions = [0, 1, 2, 3, 4, 5];

  Future<void> _update(
    BuildContext context,
    WidgetRef ref,
    EstablishmentDispatchSettings current,
    Map<String, Object?> changes,
  ) async {
    try {
      await ref
          .read(dispatchRepositoryProvider)
          .updateDispatchSettings(
            current.establishmentId,
            expectedVersion: current.version,
            changes: changes,
          );
    } catch (error) {
      if (context.mounted) {
        final message = error is ApiError
            ? error.message
            : 'Enregistrement impossible. Reessayez.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      ref.invalidate(dispatchSettingsProvider(current.establishmentId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final establishment = ref.watch(currentEstablishmentProvider).valueOrNull;
    if (establishment == null) return const SizedBox.shrink();
    final settings = ref
        .watch(dispatchSettingsProvider(establishment.id))
        .valueOrNull;
    // Pas de droit de lecture ou erreur reseau : on n'affiche rien plutot qu'une carte vide.
    if (settings == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return DsCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      // Les listes gardent leur valeur initiale : on les recree quand la version change.
      child: KeyedSubtree(
        key: ValueKey('dispatch-card-v${settings.version}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Livraison : ${establishment.name}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              key: const ValueKey('dispatch-mode'),
              initialValue: settings.dispatchMode,
              decoration: const InputDecoration(
                labelText: 'Attribution des courses',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'counter',
                  child: Text('Le comptoir attribue'),
                ),
                DropdownMenuItem(
                  value: 'self_assign',
                  child: Text('Les livreurs se servent'),
                ),
              ],
              onChanged: isAdmin
                  ? (value) {
                      if (value != null && value != settings.dispatchMode) {
                        _update(context, ref, settings, {
                          'dispatch_mode': value,
                        });
                      }
                    }
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<int>(
              key: const ValueKey('dispatch-cap'),
              initialValue: settings.maxActiveDeliveries,
              decoration: const InputDecoration(
                labelText: 'Livraisons en cours par livreur (maximum)',
              ),
              items: [
                for (var value = 1; value <= 10; value++)
                  DropdownMenuItem(value: value, child: Text('$value')),
              ],
              onChanged: isAdmin
                  ? (value) {
                      if (value != null &&
                          value != settings.maxActiveDeliveries) {
                        _update(context, ref, settings, {
                          'max_active_deliveries': value,
                        });
                      }
                    }
                  : null,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              settings.selfAssign
                  ? 'Le plafond limite ce qu\'un livreur peut prendre seul ; le comptoir peut '
                        'toujours attribuer au-dela.'
                  : 'Le plafond s\'applique quand le mode « Les livreurs se servent » est actif.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              settings.failureRulesOverridden
                  ? 'Client absent ou injoignable : regles propres a cet etablissement'
                  : 'Client absent ou injoignable : regles generales',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const ValueKey('est-failure-wait'),
                    initialValue:
                        waitOptions.contains(settings.failureMinWaitMinutes)
                        ? settings.failureMinWaitMinutes
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Attendu (min)',
                    ),
                    items: [
                      for (final value in waitOptions)
                        DropdownMenuItem(
                          value: value,
                          child: Text('$value min'),
                        ),
                      const DropdownMenuItem(
                        value: _inherit,
                        child: Text('Reglage general'),
                      ),
                    ],
                    onChanged: isAdmin
                        ? (value) => _update(context, ref, settings, {
                            'failure_min_wait_minutes': value == _inherit
                                ? null
                                : value,
                          })
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: const ValueKey('est-failure-calls'),
                    initialValue:
                        callOptions.contains(settings.failureMinCallAttempts)
                        ? settings.failureMinCallAttempts
                        : null,
                    decoration: const InputDecoration(labelText: 'Appels'),
                    items: [
                      for (final value in callOptions)
                        DropdownMenuItem(
                          value: value,
                          child: Text('$value appel(s)'),
                        ),
                      const DropdownMenuItem(
                        value: _inherit,
                        child: Text('Reglage general'),
                      ),
                    ],
                    onChanged: isAdmin
                        ? (value) => _update(context, ref, settings, {
                            'failure_min_call_attempts': value == _inherit
                                ? null
                                : value,
                          })
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
