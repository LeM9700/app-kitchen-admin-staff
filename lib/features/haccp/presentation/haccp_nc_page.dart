import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/application/haccp_offline_service.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider filtré par statut (autoDispose.family sur String? status).
final haccpNcByStatusProvider =
    FutureProvider.autoDispose.family<List<HaccpNonConformity>, String?>(
  (ref, status) {
    return ref
        .watch(haccpRepositoryProvider)
        .listNonConformities(status: status);
  },
);

/// Page de gestion des non-conformités HACCP.
///
/// Accessible depuis :
///   - Le bandeau NC de [HaccpCheckPage]
///   - La nav principale (admin uniquement)
///
/// Workflow NC :
///   open → in_progress (action corrective saisie) → closed (validé manager)
class HaccpNonConformityPage extends ConsumerStatefulWidget {
  const HaccpNonConformityPage({super.key});

  @override
  ConsumerState<HaccpNonConformityPage> createState() =>
      _HaccpNonConformityPageState();
}

class _HaccpNonConformityPageState
    extends ConsumerState<HaccpNonConformityPage> {
  String? _statusFilter; // null = toutes

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
    final isAdmin = user?.role == 'admin' || user?.role == 'super-admin';
    final ncsAsync = ref.watch(haccpNcByStatusProvider(_statusFilter));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Non-conformités HACCP'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(haccpNcByStatusProvider(_statusFilter)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtres statut
          _StatusFilterBar(
            current: _statusFilter,
            onChanged: (s) => setState(() => _statusFilter = s),
          ),
          Expanded(
            child: ncsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 40,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(e.toString()),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () => ref
                          .invalidate(haccpNcByStatusProvider(_statusFilter)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (ncs) {
                if (ncs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 56,
                          color: Colors.green.shade300,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _statusFilter == null
                              ? 'Aucune non-conformité enregistrée'
                              : 'Aucune NC avec ce statut',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Colors.grey,
                                  ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(haccpNcByStatusProvider(_statusFilter)),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: ncs.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _NcCard(
                      nc: ncs[i],
                      isAdmin: isAdmin,
                      onUpdated: () {
                        ref.invalidate(haccpNcByStatusProvider(_statusFilter));
                        ref.invalidate(haccpStatusProvider);
                        ref.invalidate(haccpOpenNcProvider);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Barre de filtres ─────────────────────────────────────────────────────────

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.current,
    required this.onChanged,
  });

  final String? current;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    final filters = [
      (null, 'Toutes'),
      ('open', 'Ouvertes'),
      ('in_progress', 'En cours'),
      ('closed', 'Clôturées'),
    ];

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final selected = current == f.$1;
            return Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: FilterChip(
                label: Text(f.$2),
                selected: selected,
                onSelected: (_) => onChanged(f.$1),
                selectedColor: AppColors.infoAlt.withValues(alpha: 0.15),
                checkmarkColor: AppColors.infoAlt,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─── Carte non-conformité ─────────────────────────────────────────────────────

class _NcCard extends ConsumerStatefulWidget {
  const _NcCard({
    required this.nc,
    required this.isAdmin,
    required this.onUpdated,
  });

  final HaccpNonConformity nc;
  final bool isAdmin;
  final VoidCallback onUpdated;

  @override
  ConsumerState<_NcCard> createState() => _NcCardState();
}

class _NcCardState extends ConsumerState<_NcCard> {
  bool _expanded = false;
  bool _saving = false;

  Color get _statusColor {
    switch (widget.nc.status) {
      case 'open':
        return Colors.red;
      case 'in_progress':
        return Colors.orange;
      case 'closed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData get _statusIcon {
    switch (widget.nc.status) {
      case 'open':
        return Icons.report_problem;
      case 'in_progress':
        return Icons.pending_actions;
      case 'closed':
        return Icons.check_circle;
      default:
        return Icons.help_outline;
    }
  }

  String get _statusLabel {
    switch (widget.nc.status) {
      case 'open':
        return 'Ouverte';
      case 'in_progress':
        return 'En cours';
      case 'closed':
        return 'Clôturée';
      default:
        return widget.nc.status;
    }
  }

  String get _sourceLabel {
    switch (widget.nc.sourceType) {
      case 'temperature':
        return '🌡️ Température';
      case 'dlc':
        return '📅 DLC';
      case 'cleaning':
        return '🧹 Nettoyage';
      case 'reception':
        return '📦 Réception';
      case 'cooling':
        return '❄️ Refroidissement';
      default:
        return '⚠️ Autre';
    }
  }

  Future<void> _addCorrectiveAction() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller =
        TextEditingController(text: widget.nc.correctiveAction ?? '');

    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Action corrective'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.nc.description,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Action corrective *',
                hintText:
                    'Décrivez les mesures prises pour corriger l\'écart...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (action == null) return;

    setState(() => _saving = true);
    try {
      final result =
          await ref.read(haccpOfflineServiceProvider).updateNonConformity(
            widget.nc.id,
            correctiveAction: action,
            status: 'in_progress',
          );
      if (mounted) {
        final queued = result is QueuedForSync<HaccpNonConformity>;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              queued
                  ? '${result.label}. Enregistre localement, synchronisation en attente.'
                  : 'Action corrective enregistree',
            ),
            backgroundColor: queued ? Colors.blue.shade700 : Colors.green,
          ),
        );
      }
      widget.onUpdated();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              haccpFriendlyError(e, 'Impossible de mettre a jour la NC'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _validate() async {
    final messenger = ScaffoldMessenger.of(context);
    // Vérifier qu'une action corrective existe
    if (widget.nc.correctiveAction == null ||
        widget.nc.correctiveAction!.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Ajoutez d\'abord une action corrective avant de clôturer.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clôturer la non-conformité'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Confirmez-vous que cette non-conformité est résolue ?'),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      widget.nc.correctiveAction!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final result =
          await ref.read(haccpOfflineServiceProvider).updateNonConformity(
            widget.nc.id,
            status: 'closed',
          );
      widget.onUpdated();
      if (mounted) {
        final queued = result is QueuedForSync<HaccpNonConformity>;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              queued
                  ? '${result.label}. Enregistre localement, synchronisation en attente.'
                  : 'Non-conformit\u00e9 cl\u00f4tur\u00e9e \u2713',
            ),
            backgroundColor: queued ? Colors.blue.shade700 : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              haccpFriendlyError(e, 'Impossible de cloturer la NC'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nc = widget.nc;
    final isInProgress = nc.status == 'in_progress';
    final isClosed = nc.status == 'closed';

    return DsCard(
      borderRadius: 12,
      borderColor: _statusColor.withValues(alpha: isClosed ? 0.2 : 0.4),
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Row(
            children: [
              Icon(_statusIcon, color: _statusColor, size: 18),
              const SizedBox(width: AppSpacing.xs),
              _StatusChip(label: _statusLabel, color: _statusColor),
              const SizedBox(width: AppSpacing.xs),
              _SourceChip(label: _sourceLabel),
              const Spacer(),
              Text(
                _formatDate(nc.createdAt),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 18,
                color: Colors.grey,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // Description
          Text(
            nc.description,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
          if (isClosed) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Non-conformit\u00e9 cl\u00f4tur\u00e9e \u2713',
              style: TextStyle(
                color: Colors.green,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],

          // Détails étendus
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),

            // Action corrective existante
            if (nc.correctiveAction != null) ...[
              _DetailRow(
                icon: Icons.build_outlined,
                label: 'Action corrective',
                value: nc.correctiveAction!,
                valueColor:
                    isInProgress ? Colors.orange[700] : Colors.green[700],
              ),
              const SizedBox(height: AppSpacing.xs),
            ] else if (!isClosed) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.red),
                    SizedBox(width: 4),
                    Text(
                      'Action corrective requise',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],

            // Validé par
            if (nc.validatedAt != null) ...[
              _DetailRow(
                icon: Icons.verified_outlined,
                label: 'Clôturée le',
                value: _formatDateTime(nc.validatedAt!),
                valueColor: Colors.green[700],
              ),
              const SizedBox(height: AppSpacing.xs),
            ],

            // Actions (admin uniquement, NC non clôturée)
            if (widget.isAdmin && !isClosed) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  // Ajouter / modifier action corrective
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _addCorrectiveAction,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: Text(
                        nc.correctiveAction == null
                            ? 'Ajouter action'
                            : 'Modifier action',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Clôturer
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_saving || nc.correctiveAction == null)
                          ? null
                          : _validate,
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check, size: 16),
                      label: const Text('Clôturer'),
                      style:
                          FilledButton.styleFrom(backgroundColor: Colors.green),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatDateTime(DateTime d) =>
      '${_formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ─── Widgets utilitaires ──────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
