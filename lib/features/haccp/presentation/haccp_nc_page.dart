import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_elevation.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
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

  static const _maxContentWidth = 960.0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
    final isAdmin = user?.role == 'admin' || user?.role == 'super-admin';
    final ncsAsync = ref.watch(haccpNcByStatusProvider(_statusFilter));

    return Scaffold(
      backgroundColor: HaccpPalette.background,
      appBar: AppBar(
        title: const Text('Non-conformités HACCP'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(haccpNcByStatusProvider(_statusFilter)),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Column(
            children: [
              _StatusFilterBar(
                current: _statusFilter,
                onChanged: (s) => setState(() => _statusFilter = s),
              ),
              Expanded(
                child: ncsAsync.when(
                  loading: () => const HaccpSkeleton(),
                  error: (e, _) => HaccpErrorState(
                    message: haccpFriendlyError(
                      e,
                      'Impossible de charger les non-conformités',
                    ),
                    onRetry: () =>
                        ref.invalidate(haccpNcByStatusProvider(_statusFilter)),
                  ),
                  data: (ncs) {
                    if (ncs.isEmpty) {
                      return HaccpEmptyState(
                        icon: Icons.check_circle_outline,
                        title: _statusFilter == null
                            ? 'Aucune non-conformité enregistrée'
                            : 'Aucune NC avec ce statut',
                        message:
                            'Les écarts détectés par les contrôles apparaîtront ici.',
                      );
                    }

                    // Ce qui demande une action d'abord (affichage seulement).
                    int rank(String s) => switch (s) {
                          'open' => 0,
                          'in_progress' => 1,
                          'closed' => 3,
                          _ => 2,
                        };
                    final sorted = [...ncs]..sort(
                        (a, b) => rank(a.status).compareTo(rank(b.status)),
                      );
                    final toHandle = ncs.where((n) => n.isOpen).length;

                    return RefreshIndicator(
                      onRefresh: () async => ref
                          .invalidate(haccpNcByStatusProvider(_statusFilter)),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.xs,
                          AppSpacing.md,
                          AppSpacing.xxl,
                        ),
                        itemCount: sorted.length + 1,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return HaccpPageHeader(
                              title: '${ncs.length} non-conformité(s)',
                              subtitle: toHandle > 0
                                  ? '$toHandle à traiter (ouverte ou en cours)'
                                  : 'Aucune non-conformité à traiter',
                              icon: Icons.report_problem_outlined,
                            );
                          }
                          final nc = sorted[i - 1];
                          return _NcCard(
                            key: ValueKey('haccp-nc-${nc.id}'),
                            nc: nc,
                            isAdmin: isAdmin,
                            onUpdated: () {
                              ref.invalidate(
                                haccpNcByStatusProvider(_statusFilter),
                              );
                              ref.invalidate(haccpStatusProvider);
                              ref.invalidate(haccpOpenNcProvider);
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
    final filters = <(String?, String)>[
      ('open', 'Ouvertes'),
      ('in_progress', 'En cours'),
      ('closed', 'Clôturées'),
      (null, 'Toutes'),
    ];

    return Container(
      width: double.infinity,
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
              child: ChoiceChip(
                label: Text(f.$2),
                selected: selected,
                onSelected: (_) => onChanged(f.$1),
                showCheckmark: false,
                backgroundColor: HaccpPalette.surface,
                selectedColor: HaccpPalette.graphite,
                side: BorderSide(
                  color: selected ? HaccpPalette.graphite : HaccpPalette.border,
                ),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : HaccpPalette.graphite,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
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
    super.key,
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

  HaccpTone get _tone => switch (widget.nc.status) {
        'open' => HaccpTone.danger,
        'in_progress' => HaccpTone.warning,
        'closed' => HaccpTone.ok,
        _ => HaccpTone.neutral,
      };

  String get _statusLabel => switch (widget.nc.status) {
        'open' => 'Ouverte',
        'in_progress' => 'En cours',
        'closed' => 'Clôturée',
        _ => widget.nc.status,
      };

  String get _sourceLabel => switch (widget.nc.sourceType) {
        'temperature' => 'Température',
        'dlc' => 'DLC',
        'cleaning' => 'Nettoyage',
        'reception' => 'Réception',
        'cooling' => 'Refroidissement',
        _ => 'Autre',
      };

  bool get _hasAction =>
      widget.nc.correctiveAction != null &&
      widget.nc.correctiveAction!.isNotEmpty;

  Future<void> _addCorrectiveAction() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller =
        TextEditingController(text: widget.nc.correctiveAction ?? '');

    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: HaccpPalette.surface,
        title: const Text('Action corrective'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.nc.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: HaccpPalette.graphiteSoft,
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
                    filled: true,
                    fillColor: HaccpPalette.surface,
                  ),
                ),
              ],
            ),
          ),
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
            'Ajoutez d\'abord une action corrective avant de clôturer.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: HaccpPalette.surface,
        title: const Text('Clôturer la non-conformité'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Confirmez-vous que cette non-conformité est résolue ?',
                ),
                const SizedBox(height: AppSpacing.sm),
                HaccpInfoBanner(
                  icon: Icons.build_outlined,
                  title: 'Action corrective',
                  message: widget.nc.correctiveAction!,
                  tone: HaccpTone.ok,
                ),
              ],
            ),
          ),
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
                  : 'Non-conformité clôturée ✓',
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
    final isClosed = nc.status == 'closed';
    final tone = _tone;
    final style = haccpToneStyle(tone);

    return DsCard(
      backgroundColor: HaccpPalette.surface,
      borderColor: style.foreground.withValues(alpha: isClosed ? 0.2 : 0.4),
      borderRadius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      intensity: NeumorphicIntensity.subtle,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              HaccpStatusBadge(label: _statusLabel, tone: tone, compact: true),
              HaccpStatusBadge(
                label: _sourceLabel,
                tone: HaccpTone.neutral,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            nc.description,
            style: const TextStyle(
              color: HaccpPalette.graphite,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              height: 1.3,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _createdLabel(nc.createdAt),
            style: const TextStyle(
              color: HaccpPalette.graphiteSoft,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (isClosed)
            const Text(
              'Non-conformité clôturée ✓',
              style: TextStyle(
                color: AppColors.success,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (!_hasAction)
            const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: AppColors.dangerAlt),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Action corrective requise',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.dangerAlt,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            )
          else
            const Row(
              children: [
                Icon(Icons.build_outlined, size: 16, color: AppColors.warning),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Action corrective enregistrée',
                    style: TextStyle(
                      fontSize: 12,
                      color: HaccpPalette.graphiteSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          if (!_expanded)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _expanded = true),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('OUVRIR'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HaccpPalette.graphite,
                  side: const BorderSide(color: HaccpPalette.graphite),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            )
          else ...[
            const Divider(height: 1, color: HaccpPalette.border),
            const SizedBox(height: AppSpacing.sm),
            if (widget.isAdmin && !isClosed) ...[
              HaccpActionBar(
                children: [
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _addCorrectiveAction,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(
                        nc.correctiveAction == null
                            ? 'Ajouter action'
                            : 'Modifier action',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: const BorderSide(color: AppColors.warning),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: (_saving || nc.correctiveAction == null)
                          ? null
                          : _validate,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check, size: 18),
                      label: const Text('Clôturer'),
                      style:
                          FilledButton.styleFrom(backgroundColor: Colors.green),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            _buildDetail(nc),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = false),
                icon: const Icon(Icons.expand_less, size: 18),
                label: const Text('Réduire'),
                style: TextButton.styleFrom(
                  foregroundColor: HaccpPalette.graphiteSoft,
                  minimumSize: const Size(48, 44),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetail(HaccpNonConformity nc) {
    final rows = <Widget>[
      _DetailRow(
        icon: Icons.category_outlined,
        label: 'Origine',
        value: _sourceLabel,
      ),
      if (nc.sourceId != null)
        _DetailRow(
          icon: Icons.straighten,
          label: 'Mesure / événement',
          value: '$_sourceLabel n°${nc.sourceId}',
        ),
      _DetailRow(
        icon: Icons.event_outlined,
        label: 'Date',
        value: _formatDateTime(nc.createdAt),
      ),
      if (nc.sessionId != null)
        _DetailRow(
          icon: Icons.fact_check_outlined,
          label: 'Contexte',
          value: 'Session de contrôle n°${nc.sessionId}',
        ),
      _DetailRow(
        icon: Icons.build_outlined,
        label: 'Action corrective',
        value: _hasAction ? nc.correctiveAction! : 'Non renseignée',
        valueColor: _hasAction ? null : AppColors.dangerAlt,
      ),
      _DetailRow(
        icon: Icons.flag_outlined,
        label: 'Statut',
        value: _statusLabel,
      ),
    ];

    final history = <String>[
      'Créée le ${_formatDateTime(nc.createdAt)}',
      if (nc.validatedAt != null)
        'Clôturée le ${_formatDateTime(nc.validatedAt!)}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows) ...[r, const SizedBox(height: AppSpacing.sm)],
        const Text(
          'Historique',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: HaccpPalette.graphiteSoft,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        for (final h in history)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6, right: 8),
                  child: Icon(
                    Icons.circle,
                    size: 6,
                    color: HaccpPalette.graphiteSoft,
                  ),
                ),
                Expanded(
                  child: Text(
                    h,
                    style: const TextStyle(
                      fontSize: 13,
                      color: HaccpPalette.graphite,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _createdLabel(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.isNegative || diff.inMinutes < 1) return 'Créé à l\'instant';
    if (diff.inMinutes < 60) return 'Créé il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Créé il y a ${diff.inHours} h';
    return 'Créé il y a ${diff.inDays} j';
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatDateTime(DateTime d) =>
      '${_formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ─── Widgets utilitaires ──────────────────────────────────────────────────────

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
        Icon(icon, size: 18, color: HaccpPalette.graphiteSoft),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: HaccpPalette.graphiteSoft,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? HaccpPalette.graphite,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
