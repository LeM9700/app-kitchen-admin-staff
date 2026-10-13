import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HaccpReadinessCard extends ConsumerWidget {
  const HaccpReadinessCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(currentPermissionSetProvider);
    if (!permissions.can(AppPermission.haccpRead))
      return const SizedBox.shrink();
    final establishment = ref.watch(currentEstablishmentProvider);
    return establishment.when(
      loading: () => const _HaccpCardShell(child: LinearProgressIndicator()),
      error: (_, __) => const _HaccpCardShell(
        child: Text('Établissement indisponible. Vérifiez la sélection.'),
      ),
      data: (site) {
        if (site == null) {
          return const _HaccpCardShell(
            child: Text('Aucun établissement sélectionné.'),
          );
        }
        final status = ref.watch(haccpStrictStatusProvider(site.id));
        return status.when(
          loading: () =>
              const _HaccpCardShell(child: LinearProgressIndicator()),
          error: (_, __) => _HaccpCardShell(
            child: Row(
              children: [
                const Expanded(child: Text('Statut HACCP indisponible.')),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(haccpStrictStatusProvider(site.id)),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
          data: (value) => _HaccpCardShell(
            child: Row(
              children: [
                Icon(
                  value.satisfied
                      ? Icons.verified_outlined
                      : Icons.warning_amber_rounded,
                  color: value.satisfied ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HACCP — ${site.name}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value.satisfied
                            ? 'Ouverture et commandes autorisées.'
                            : 'Commandes bloquées : ${value.blockers.length} point(s) à régulariser.',
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () => context.push('/haccp'),
                  child: Text(
                    value.satisfied ? 'Consulter' : 'Préparer l’ouverture',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HaccpCardShell extends StatelessWidget {
  const _HaccpCardShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF8E1),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}
