import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/driver/application/location_sharing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Texte d'information montre au livreur avant le partage de sa position. La duree vient du serveur
/// (jamais ecrite en dur) pour ne pas contredire la configuration reelle.
String locationNoticeText(int retentionHours) {
  final duration = retentionHours % 24 == 0
      ? '${retentionHours ~/ 24} jours ($retentionHours h)'
      : '$retentionHours heures';
  return 'Pendant une livraison en cours, votre position est partagee avec le restaurant et avec '
      'le client de la commande que vous livrez, pour qu\'il suive son arrivee. '
      'Le partage continue application en arriere-plan ou ecran verrouille : une notification '
      '(Android) ou un indicateur (iPhone) reste affiche pendant ce temps. '
      'Rien n\'est partage en dehors d\'une livraison. '
      'Les positions sont conservees $duration pour pouvoir verifier un litige, '
      'puis supprimees. Vous pouvez retirer votre accord a tout moment : le partage s\'arrete.';
}

String _message(Object error) => error is ApiError
    ? error.message
    : 'Action impossible pour le moment. Reessayez.';

/// Accord du livreur et etat du partage de position, en haut de l'ecran des livraisons.
class LocationSharingPanel extends ConsumerWidget {
  const LocationSharingPanel({super.key});

  Future<void> _grant(BuildContext context, WidgetRef ref, DriverMe me) async {
    try {
      await ref
          .read(dispatchRepositoryProvider)
          .grantLocationConsent(me.locationNoticeVersion);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } finally {
      ref.invalidate(driverMeProvider);
    }
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer votre accord ?'),
        content: const Text(
          'Votre position ne sera plus partagee. Le client ne verra plus sa livraison sur la carte.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('confirm-withdraw-consent'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retirer mon accord'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(dispatchRepositoryProvider).withdrawLocationConsent();
      await ref.read(driverLocationSharerProvider.notifier).setActive(false);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } finally {
      ref.invalidate(driverMeProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(driverMeProvider).valueOrNull;
    final sharing = ref.watch(driverLocationSharerProvider);
    if (me == null) return const SizedBox.shrink();

    if (!me.locationConsent) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: DsCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.share_location_outlined),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Partage de votre position',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                locationNoticeText(me.locationRetentionHours),
                key: const ValueKey('location-notice'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const ValueKey('grant-location-consent'),
                  onPressed: () => _grant(context, ref, me),
                  child: const Text('J\'accepte'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final (icon, text, color) = switch (sharing.status) {
      SharingStatus.sharing => (
        Icons.my_location,
        'Position partagee avec le restaurant et le client, meme ecran verrouille.',
        AppColors.success,
      ),
      SharingStatus.permissionDenied => (
        Icons.location_disabled_outlined,
        sharing.lastError ??
            'Localisation indisponible : la position n\'est pas partagee.',
        AppColors.dangerAlt,
      ),
      SharingStatus.consentRequired => (
        Icons.privacy_tip_outlined,
        'Votre accord est requis pour partager la position.',
        AppColors.warning,
      ),
      SharingStatus.idle => (
        Icons.location_off_outlined,
        'Votre position n\'est partagee que pendant une livraison en route.',
        AppColors.textSecondary,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DsCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(text, key: const ValueKey('sharing-status')),
                ),
                TextButton(
                  key: const ValueKey('withdraw-location-consent'),
                  onPressed: () => _withdraw(context, ref),
                  child: const Text('Retirer mon accord'),
                ),
              ],
            ),
            if (sharing.isSharing &&
                sharing.pending > 0 &&
                sharing.lastError != null)
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: Text(
                  '${sharing.pending} position(s) en attente d\'envoi (${sharing.lastError})',
                  key: const ValueKey('sharing-pending'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.warning),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
