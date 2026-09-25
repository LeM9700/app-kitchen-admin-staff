import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/core/offline/sync_worker.dart';
import 'package:app_admin_staff/features/haccp/application/haccp_offline_service.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:app_admin_staff/features/haccp/presentation/dlc_form_dialog.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_ui.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Page principale HACCP — contrôle sécurité alimentaire.
///
/// Affiche deux onglets : ouverture et fermeture.
/// Chaque onglet contient :
///   1. Bandeau de progression (gate bloquant)
///   2. Relevés de température (par équipement)
///   3. Vérifications DLC (niveaux 1/2/3)
///   4. Plan de nettoyage (checklist tâches ND)
///   5. Non-conformités ouvertes (alertes)
///   6. Bouton "Valider la session" (admin uniquement)
class HaccpCheckPage extends ConsumerStatefulWidget {
  const HaccpCheckPage({super.key});

  @override
  ConsumerState<HaccpCheckPage> createState() => _HaccpCheckPageState();
}

class _HaccpCheckPageState extends ConsumerState<HaccpCheckPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(haccpStatusProvider);
    final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
    final isAdmin = user?.role == 'admin' || user?.role == 'super-admin';

    final openNcsAsync = ref.watch(haccpOpenNcProvider);
    final openNcCount = openNcsAsync.valueOrNull?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sécurité alimentaire'),
        actions: [
          // Bouton NC avec badge — accès à HaccpNonConformityPage
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Badge(
              isLabelVisible: openNcCount > 0,
              label: Text(openNcCount.toString()),
              backgroundColor: Colors.red,
              child: IconButton(
                icon: const Icon(Icons.report_problem_outlined),
                tooltip: 'Non-conformités',
                onPressed: () => context.push('/haccp/nc'),
              ),
            ),
          ),
          // Menu accès rapide aux modules complémentaires
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Modules HACCP',
            onSelected: (path) => context.push(path),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: '/haccp/reception',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.local_shipping_outlined),
                  title: Text('Contrôles réception'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: '/haccp/cooling',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.ac_unit),
                  title: Text('Refroidissement rapide'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: '/haccp/training',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.school_outlined),
                  title: Text('Registre formations'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: '/haccp/stats',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.bar_chart_outlined, color: Colors.blue),
                  title: Text(
                    'Scorecard hebdo',
                    style: TextStyle(color: Colors.blue),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: '/haccp/export',
                child: ListTile(
                  dense: true,
                  leading:
                      Icon(Icons.picture_as_pdf_outlined, color: Colors.red),
                  title: Text(
                    'Export PDF / CSV',
                    style: TextStyle(color: Colors.red),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: '/haccp/equipment',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.kitchen_outlined),
                  title: Text('Équipements'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: '/haccp/cleaning-tasks',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.cleaning_services_outlined),
                  title: Text('Tâches de nettoyage'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Ouverture', icon: Icon(Icons.wb_sunny_outlined)),
            Tab(text: 'Fermeture', icon: Icon(Icons.nights_stay_outlined)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Bannière offline — visible quelle que soit l'état du chargement
          const _HaccpOfflineBanner(),

          Expanded(
            child: statusAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                message: e.toString(),
                onRetry: () => ref.invalidate(haccpStatusProvider),
              ),
              data: (status) => Column(
                children: [
                  // Bandeau global NC ouvertes
                  if (status.openNonConformities > 0)
                    _NcBanner(count: status.openNonConformities),

                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _SessionTab(
                          sessionType: 'opening',
                          summary: status.opening,
                          canProceed: status.canOpen,
                          isAdmin: isAdmin,
                        ),
                        _SessionTab(
                          sessionType: 'closing',
                          summary: status.closing,
                          canProceed: status.canClose,
                          isAdmin: isAdmin,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showHaccpSnack<T>(
  BuildContext context,
  OfflineResult<T> result, {
  required String onlineMessage,
}) {
  final queued = result is QueuedForSync<T>;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        queued
            ? '${result.label}. Enregistre localement, synchronisation en attente.'
            : onlineMessage,
      ),
      backgroundColor: queued ? Colors.blue.shade700 : Colors.green,
    ),
  );
}

// ─── Onglet session (ouverture ou fermeture) ──────────────────────────────────

class _SessionTab extends ConsumerStatefulWidget {
  const _SessionTab({
    required this.sessionType,
    required this.summary,
    required this.canProceed,
    required this.isAdmin,
  });

  final String sessionType;
  final HaccpSessionSummary summary;
  final bool canProceed;
  final bool isAdmin;

  @override
  ConsumerState<_SessionTab> createState() => _SessionTabState();
}

class _SessionTabState extends ConsumerState<_SessionTab> {
  bool _loading = false;

  String get _label =>
      widget.sessionType == 'opening' ? 'ouverture' : 'fermeture';

  Future<void> _startSession() async {
    setState(() => _loading = true);
    try {
      final result = await ref
          .read(haccpOfflineServiceProvider)
          .startSession(widget.sessionType);
      ref.invalidate(haccpStatusProvider);
      ref.invalidate(haccpTodaySessionsProvider);
      if (mounted) {
        _showHaccpSnack(
          context,
          result,
          onlineMessage: 'Check $_label demarre',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              haccpFriendlyError(e, 'Impossible de demarrer le check HACCP'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _completeSession(int sessionId, {bool force = false}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Valider le check $_label'),
        content: Text(
          force
              ? 'Certains éléments sont manquants. Voulez-vous valider quand même (validation incomplète) ?'
              : 'Confirmer la validation du check $_label ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final result = await ref
          .read(haccpOfflineServiceProvider)
          .completeSession(sessionId, force: force);
      ref.invalidate(haccpStatusProvider);
      ref.invalidate(haccpTodaySessionsProvider);
      if (mounted) {
        _showHaccpSnack(
          context,
          result,
          onlineMessage: 'Check $_label valide',
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        // Si session incomplète, proposer force=true
        if (msg.contains('INCOMPLETE_SESSION') && !force) {
          _completeSession(sessionId, force: true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur : $msg'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(haccpStatusProvider);
        ref.invalidate(haccpTodaySessionsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // Bandeau de progression
          _ProgressBanner(summary: summary, sessionType: widget.sessionType),
          const SizedBox(height: AppSpacing.md),

          // Session non démarrée
          if (summary.status == 'not_started') ...[
            DsCard(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  const Icon(
                    Icons.play_circle_outline,
                    size: 48,
                    color: AppColors.infoAlt,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Check $_label non démarré',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Démarrez le check pour commencer les relevés.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: _loading ? null : _startSession,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text('Démarrer le check $_label'),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Session en cours ou complète
            _TemperatureSection(
              sessionId: summary.sessionId!,
              sessionType: widget.sessionType,
            ),
            const SizedBox(height: AppSpacing.md),
            _DlcSection(sessionId: summary.sessionId!),
            const SizedBox(height: AppSpacing.md),
            _CleaningSection(
              sessionId: summary.sessionId!,
              sessionType: widget.sessionType,
            ),
            const SizedBox(height: AppSpacing.md),
            // Section huile friteuse — visible seulement si feature flag activé
            _OilSection(sessionId: summary.sessionId!),
            const SizedBox(height: AppSpacing.md),
            _NonConformitySection(sessionId: summary.sessionId!),
            const SizedBox(height: AppSpacing.lg),

            // Bouton validation (admin uniquement)
            if (widget.isAdmin && !summary.isComplete)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _completeSession(summary.sessionId!),
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text('Valider le check $_label'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

            // Statut validé
            if (summary.isComplete)
              DsCard(
                backgroundColor: Colors.green.withValues(alpha: 0.1),
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(
                    summary.status == 'incomplete_validated'
                        ? 'Validé avec réserves'
                        : 'Check $_label validé',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                  subtitle: Text(
                    widget.canProceed
                        ? widget.sessionType == 'opening'
                            ? 'Le restaurant peut ouvrir.'
                            : 'La fermeture peut être confirmée.'
                        : '',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Bandeau de progression ───────────────────────────────────────────────────

class _ProgressBanner extends StatelessWidget {
  const _ProgressBanner({
    required this.summary,
    required this.sessionType,
  });

  final HaccpSessionSummary summary;
  final String sessionType;

  @override
  Widget build(BuildContext context) {
    final color = summary.isComplete
        ? Colors.green
        : summary.status == 'not_started'
            ? Colors.grey
            : AppColors.infoAlt;

    return DsCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                summary.isComplete
                    ? Icons.check_circle
                    : summary.status == 'not_started'
                        ? Icons.radio_button_unchecked
                        : Icons.pending,
                color: color,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                _statusLabel(summary.status),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const Spacer(),
              if (summary.hasNonConformities)
                const StatusBadge(
                  label: 'NC',
                  tone: StatusTone.warning,
                ),
            ],
          ),
          if (summary.status != 'not_started') ...[
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(
              value: summary.progress,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                _ProgressChip(
                  label:
                      '${summary.temperaturesDone}/${summary.temperaturesTotal} Températures',
                  done: summary.temperaturesDone >= summary.temperaturesTotal,
                ),
                const SizedBox(width: AppSpacing.xs),
                _ProgressChip(
                  label:
                      '${summary.cleaningDone}/${summary.cleaningTotal} Nettoyage',
                  done: summary.cleaningDone >= summary.cleaningTotal,
                ),
                const SizedBox(width: AppSpacing.xs),
                _ProgressChip(
                  label: '${summary.dlcDone} DLC',
                  done: summary.dlcDone > 0,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'not_started':
        return 'Non démarré';
      case 'in_progress':
        return 'En cours';
      case 'complete':
        return 'Validé';
      case 'incomplete_validated':
        return 'Validé avec réserves';
      default:
        return status;
    }
  }
}

class _ProgressChip extends StatelessWidget {
  const _ProgressChip({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: done
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: done ? Colors.green[700] : Colors.grey[600],
        ),
      ),
    );
  }
}

// ─── Section températures ─────────────────────────────────────────────────────

class _TemperatureSection extends ConsumerStatefulWidget {
  const _TemperatureSection({
    required this.sessionId,
    required this.sessionType,
  });

  final int sessionId;
  final String sessionType;

  @override
  ConsumerState<_TemperatureSection> createState() =>
      _TemperatureSectionState();
}

class _TemperatureSectionState extends ConsumerState<_TemperatureSection> {
  Future<void> _logTemp(HaccpEquipment equipment) async {
    final controller = TextEditingController();
    final ncController = TextEditingController();

    final entry = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _TempInputDialog(
        equipment: equipment,
        tempController: controller,
        ncController: ncController,
      ),
    );

    if (entry == null) return;

    try {
      final saveResult =
          await ref.read(haccpOfflineServiceProvider).logTemperature(
            widget.sessionId,
            equipmentId: equipment.id,
            measuredTemp: entry['temp'] as double,
            correctiveAction: entry['action'] as String?,
          );
      ref.invalidate(haccpStatusProvider);
      ref.invalidate(haccpTemperatureLogsProvider(widget.sessionId));

      if (mounted && saveResult is QueuedForSync<HaccpTemperatureLog>) {
        _showHaccpSnack(
          context,
          saveResult,
          onlineMessage: 'Releve temperature enregistre',
        );
      } else if (mounted && entry['is_compliant'] == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('⚠️ Température hors limite — NC créée automatiquement'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              haccpFriendlyError(
                e,
                'Impossible d enregistrer la temperature HACCP',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final equipmentAsync = ref.watch(haccpEquipmentProvider);
    final logsAsync = ref.watch(haccpTemperatureLogsProvider(widget.sessionId));

    return _SectionCard(
      title: 'Températures',
      icon: Icons.thermostat,
      child: equipmentAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Erreur : $e'),
        data: (equipment) {
          final filtered = equipment
              .where(
                (e) => widget.sessionType == 'opening'
                    ? e.checkAtOpening
                    : e.checkAtClosing,
              )
              .toList();

          if (filtered.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: Text(
                'Aucun équipement configuré. Contactez votre administrateur.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return logsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Erreur : $e'),
            data: (logs) {
              final loggedIds = logs.map((l) => l.equipmentId).toSet();
              return Column(
                children: filtered.map((equipment) {
                  final done = loggedIds.contains(equipment.id);
                  final log = done
                      ? logs.firstWhere((l) => l.equipmentId == equipment.id)
                      : null;
                  return _EquipmentTile(
                    equipment: equipment,
                    log: log,
                    done: done,
                    onTap: done ? null : () => _logTemp(equipment),
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }
}

class _EquipmentTile extends StatelessWidget {
  const _EquipmentTile({
    required this.equipment,
    this.log,
    required this.done,
    this.onTap,
  });

  final HaccpEquipment equipment;
  final HaccpTemperatureLog? log;
  final bool done;
  final VoidCallback? onTap;

  IconData get _typeIcon {
    switch (equipment.type) {
      case 'fridge':
        return Icons.kitchen;
      case 'freezer':
        return Icons.ac_unit;
      case 'cold_room':
        return Icons.warehouse;
      case 'hot_hold':
        return Icons.whatshot;
      default:
        return Icons.device_thermostat;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: done
            ? (log?.isCompliant == true
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.orange.withValues(alpha: 0.15))
            : Colors.grey.withValues(alpha: 0.15),
        child: Icon(
          done
              ? (log?.isCompliant == true ? Icons.check : Icons.warning)
              : _typeIcon,
          color: done
              ? (log?.isCompliant == true ? Colors.green : Colors.orange)
              : Colors.grey,
        ),
      ),
      title: Text(equipment.name),
      subtitle: done
          ? Text(
              '${log!.measuredTemp.toStringAsFixed(1)}°C '
              '${log!.isCompliant ? '✓' : '⚠️ Hors limite'}',
              style: TextStyle(
                color: log!.isCompliant ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            )
          : Text(
              equipment.tempRangeLabel,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
      trailing: done
          ? null
          : IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onTap,
              tooltip: 'Saisir la température',
            ),
    );
  }
}

class _TempInputDialog extends StatefulWidget {
  const _TempInputDialog({
    required this.equipment,
    required this.tempController,
    required this.ncController,
  });

  final HaccpEquipment equipment;
  final TextEditingController tempController;
  final TextEditingController ncController;

  @override
  State<_TempInputDialog> createState() => _TempInputDialogState();
}

class _TempInputDialogState extends State<_TempInputDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _showNcField = false;

  bool get _isCompliant {
    final temp = double.tryParse(widget.tempController.text);
    if (temp == null) return true;
    final min = widget.equipment.targetMinTemp;
    final max = widget.equipment.targetMaxTemp;
    if (min == null || max == null) return true;
    return temp >= min && temp <= max;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.equipment.name),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Plage cible : ${widget.equipment.tempRangeLabel}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: widget.tempController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Température mesurée (°C)',
                suffixText: '°C',
              ),
              onChanged: (_) {
                setState(() {
                  _showNcField = !_isCompliant;
                });
              },
              validator: (v) {
                if (v == null || v.isEmpty) return 'Champ obligatoire';
                if (double.tryParse(v) == null) return 'Valeur invalide';
                return null;
              },
            ),
            if (_showNcField) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚠️ Température hors limite',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextFormField(
                      controller: widget.ncController,
                      decoration: const InputDecoration(
                        labelText: 'Action corrective (optionnel)',
                        hintText: 'Ex: Alerte technicien, produits déplacés...',
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
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
            if (!_formKey.currentState!.validate()) return;
            final temp = double.parse(widget.tempController.text);
            Navigator.pop(context, {
              'temp': temp,
              'is_compliant': _isCompliant,
              'action': widget.ncController.text.isNotEmpty
                  ? widget.ncController.text
                  : null,
            });
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

// ─── Section DLC ──────────────────────────────────────────────────────────────

class _DlcSection extends ConsumerStatefulWidget {
  const _DlcSection({required this.sessionId});

  final int sessionId;

  @override
  ConsumerState<_DlcSection> createState() => _DlcSectionState();
}

class _DlcSectionState extends ConsumerState<_DlcSection> {
  Future<void> _addDlcCheck() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const DlcFormDialog(),
    );
    if (result == null) return;

    try {
      final saveResult = await ref
          .read(haccpOfflineServiceProvider)
          .logDlcCheck(widget.sessionId, result);
      ref.invalidate(haccpStatusProvider);
      ref.invalidate(haccpDlcChecksProvider(widget.sessionId));

      if (mounted && saveResult is QueuedForSync<HaccpDlcCheck>) {
        _showHaccpSnack(
          context,
          saveResult,
          onlineMessage: 'Verification DLC enregistree',
        );
      } else if (mounted && result['is_compliant'] == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ DLC non conforme — NC créée automatiquement'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final checksAsync = ref.watch(haccpDlcChecksProvider(widget.sessionId));

    return _SectionCard(
      title: 'DLC',
      icon: Icons.event_available,
      action: TextButton.icon(
        onPressed: _addDlcCheck,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Ajouter'),
      ),
      child: checksAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Erreur : $e'),
        data: (checks) {
          if (checks.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: Text(
                'Aucune vérification DLC enregistrée. Appuyez sur Ajouter.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            );
          }
          return Column(
            children: checks.map((c) => _DlcTile(check: c)).toList(),
          );
        },
      ),
    );
  }
}

class _DlcTile extends StatelessWidget {
  const _DlcTile({required this.check});

  final HaccpDlcCheck check;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        check.isCompliant ? Icons.check_circle : Icons.cancel,
        color: check.isCompliant ? Colors.green : Colors.red,
        size: 20,
      ),
      title: Text(check.ingredientName),
      subtitle: Text(
        '${check.levelLabel} • ${_formatDate(check.dlcDate)}'
        '${check.location != null ? ' • ${check.location}' : ''}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: check.isCompliant
          ? null
          : const Icon(Icons.warning_amber, color: Colors.orange, size: 16),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ─── Section nettoyage ────────────────────────────────────────────────────────

class _CleaningSection extends ConsumerStatefulWidget {
  const _CleaningSection({
    required this.sessionId,
    required this.sessionType,
  });

  final int sessionId;
  final String sessionType;

  @override
  ConsumerState<_CleaningSection> createState() => _CleaningSectionState();
}

class _CleaningSectionState extends ConsumerState<_CleaningSection> {
  Future<void> _markDone(int taskId) async {
    try {
      final result = await ref.read(haccpOfflineServiceProvider).logCleaning(
            widget.sessionId,
            taskId: taskId,
          );
      ref.invalidate(haccpStatusProvider);
      ref.invalidate(haccpCleaningLogsProvider(widget.sessionId));
      if (mounted) {
        _showHaccpSnack(
          context,
          result,
          onlineMessage: 'Tache de nettoyage marquee comme faite',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync =
        ref.watch(haccpCleaningTasksProvider(widget.sessionType));
    final logsAsync = ref.watch(haccpCleaningLogsProvider(widget.sessionId));

    return _SectionCard(
      title: 'Nettoyage & Désinfection',
      icon: Icons.cleaning_services,
      child: tasksAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('Erreur : $e'),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.sm),
              child: Text(
                'Aucune tâche ND configurée. Contactez votre administrateur.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return logsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Erreur : $e'),
            data: (logs) {
              final doneIds = logs.map((l) => l.taskId).toSet();
              return Column(
                children: tasks.map((task) {
                  final done = doneIds.contains(task.id);
                  return CheckboxListTile(
                    dense: true,
                    value: done,
                    onChanged: done ? null : (_) => _markDone(task.id),
                    title: Text(task.name),
                    subtitle: Text(
                      '${task.zone}'
                      '${task.productUsed != null ? ' • ${task.productUsed}' : ''}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: Colors.green,
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }
}

// ─── Section non-conformités ──────────────────────────────────────────────────

class _NonConformitySection extends ConsumerWidget {
  const _NonConformitySection({required this.sessionId});

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ncsAsync = ref.watch(haccpOpenNcProvider);

    return ncsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (ncs) {
        // Filtre les NC de cette session
        final sessionNcs =
            ncs.where((nc) => nc.sessionId == sessionId).toList();
        if (sessionNcs.isEmpty) return const SizedBox.shrink();

        return _SectionCard(
          title: 'Non-conformités (${sessionNcs.length})',
          icon: Icons.warning_amber,
          iconColor: Colors.orange,
          child: Column(
            children: sessionNcs
                .map(
                  (nc) => ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.report_problem,
                      color: Colors.orange,
                      size: 18,
                    ),
                    title: Text(
                      nc.description,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: nc.correctiveAction != null
                        ? Text(
                            'Action : ${nc.correctiveAction}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          )
                        : const Text(
                            'Action corrective requise',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

// ─── Bandeau NC globales ──────────────────────────────────────────────────────

class _NcBanner extends StatelessWidget {
  const _NcBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.orange.shade50,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$count non-conformité${count > 1 ? 's' : ''} ouverte${count > 1 ? 's' : ''}',
            style: const TextStyle(
              color: Colors.orange,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets utilitaires ──────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.iconColor,
    this.action,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Color? iconColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: iconColor ?? AppColors.infoAlt),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                if (action != null) action!,
              ],
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }
}

// ─── Section huile friteuse (feature flag) ────────────────────────────────────

/// Visible uniquement si [TenantConfig.haccpFryingOilEnabled] est `true`.
/// Seuil légal : polarité ≤ 25% (OIL_POLARITY_LIMIT).
class _OilSection extends ConsumerWidget {
  const _OilSection({required this.sessionId});

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(tenantConfigProvider);
    final enabled = configAsync.valueOrNull?.haccpFryingOilEnabled ?? false;
    if (!enabled) return const SizedBox.shrink();

    final logsAsync = ref.watch(haccpOilLogsProvider(sessionId));

    return DsCard(
      borderRadius: 12,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_fire_department_outlined,
                size: 18,
                color: Colors.deepOrange,
              ),
              const SizedBox(width: 6),
              Text(
                'Huile friteuse',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showOilForm(context, ref, sessionId),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Relever'),
                style: TextButton.styleFrom(foregroundColor: Colors.deepOrange),
              ),
            ],
          ),
          logsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(
              'Erreur: $e',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
            data: (logs) {
              if (logs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    'Aucun relevé huile pour cette session.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                );
              }
              return Column(
                children: logs.map((log) {
                  final compliant = log.isCompliant;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      compliant ? Icons.check_circle : Icons.cancel,
                      color: compliant ? Colors.green : Colors.red,
                      size: 18,
                    ),
                    title: Text(
                      'Polarité : ${log.polarityPercent.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: compliant
                        ? null
                        : Text(
                            log.correctiveAction ?? 'NC — huile à changer',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                            ),
                          ),
                    trailing: Text(
                      '${log.polarityPercent > 25 ? "⚠️ " : ""}≤ 25% requis',
                      style: TextStyle(
                        fontSize: 11,
                        color: compliant ? Colors.grey : Colors.red,
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showOilForm(BuildContext context, WidgetRef ref, int sessionId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _OilInputForm(
        sessionId: sessionId,
        onSaved: () {
          ref.invalidate(haccpOilLogsProvider(sessionId));
          ref.invalidate(haccpOpenNcProvider);
        },
      ),
    );
  }
}

class _OilInputForm extends ConsumerStatefulWidget {
  const _OilInputForm({required this.sessionId, required this.onSaved});

  final int sessionId;
  final VoidCallback onSaved;

  @override
  ConsumerState<_OilInputForm> createState() => _OilInputFormState();
}

class _OilInputFormState extends ConsumerState<_OilInputForm> {
  final _formKey = GlobalKey<FormState>();
  final _polarityCtrl = TextEditingController();
  final _correctiveCtrl = TextEditingController();
  String? _color;
  String? _odor;
  bool _saving = false;

  static const _colorOptions = ['Normal', 'Brun clair', 'Brun foncé', 'Noir'];
  static const _odorOptions = ['Normal', 'Acre', 'Rance', 'Brûlé'];

  double? get _polarity =>
      double.tryParse(_polarityCtrl.text.replaceAll(',', '.'));
  bool get _nonCompliant => false;

  @override
  void dispose() {
    _polarityCtrl.dispose();
    _correctiveCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final result = await ref.read(haccpOfflineServiceProvider).logFryingOil(
            widget.sessionId,
            polarityPercent: _polarity!,
            color: _color,
            odor: _odor,
            correctiveAction: _correctiveCtrl.text.trim().isNotEmpty
                ? _correctiveCtrl.text.trim()
                : null,
          );
      widget.onSaved();
      if (mounted) {
        _showHaccpSnack(
          context,
          result,
          onlineMessage: 'Releve huile enregistre',
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Relevé huile friteuse',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Seuil légal : polarité ≤ 25% (test bandelette ou testeur)',
                style: TextStyle(fontSize: 12, color: Colors.deepOrange),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _polarityCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Taux de polarité (%) *',
                border: const OutlineInputBorder(),
                suffixText: '%',
                helperText: _polarity == null
                    ? null
                    : _nonCompliant
                        ? '⚠️ NC — dépasse 25% : changer l\'huile'
                        : '✓ Conforme',
                helperStyle: TextStyle(
                  color: _nonCompliant ? Colors.red : Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Requis';
                final d = double.tryParse(v.replaceAll(',', '.'));
                if (d == null || d < 0 || d > 100) {
                  return 'Valeur entre 0 et 100';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _color,
                    hint: const Text('Couleur'),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Couleur',
                    ),
                    items: _colorOptions
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _color = v),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _odor,
                    hint: const Text('Odeur'),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Odeur',
                    ),
                    items: _odorOptions
                        .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                        .toList(),
                    onChanged: (v) => setState(() => _odor = v),
                  ),
                ),
              ],
            ),
            if (_nonCompliant) ...[
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _correctiveCtrl,
                decoration: const InputDecoration(
                  labelText: 'Action corrective *',
                  hintText: 'Ex : Huile changée et friteuse nettoyée',
                  border: OutlineInputBorder(),
                  fillColor: Color(0xFFFFF3E0),
                  filled: true,
                ),
                validator: (v) =>
                    _nonCompliant && (v == null || v.trim().isEmpty)
                        ? 'Requis en cas de NC'
                        : null,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Enregistrer'),
                style: _nonCompliant
                    ? FilledButton.styleFrom(backgroundColor: Colors.orange)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: AppSpacing.sm),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}

// ─── Bannière offline HACCP ───────────────────────────────────────────────────

/// Affiche une bannière contextuelle quand :
///   1. L'appareil est hors ligne (fond orange, mode dégradé)
///   2. Des actions HACCP sont en attente de sync (fond bleu, bouton sync)
///
/// Disparaît automatiquement quand online et queue vide.
class _HaccpOfflineBanner extends ConsumerWidget {
  const _HaccpOfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(onlineStatusProvider).valueOrNull ?? true;
    final pendingCount = ref.watch(haccpPendingSyncCountProvider);

    // Online + aucune action en attente → bannière invisible
    if (isOnline && pendingCount == 0) return const SizedBox.shrink();

    // Offline → bannière mode dégradé
    if (!isOnline) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        color: Colors.orange.shade700,
        child: Row(
          children: [
            const Icon(Icons.wifi_off, color: Colors.white, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                pendingCount > 0
                    ? 'Hors ligne — $pendingCount action${pendingCount > 1 ? 's' : ''} en attente de sync'
                    : 'Hors ligne — Les saisies seront synchronisées au retour réseau',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Online + actions en attente → bannière sync
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 8,
      ),
      color: Colors.blue.shade700,
      child: Row(
        children: [
          const Icon(Icons.cloud_sync_outlined, color: Colors.white, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$pendingCount action${pendingCount > 1 ? 's' : ''} HACCP en attente de synchronisation',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              final queue = ref.read(syncQueueProvider);
              if (queue.isNotEmpty) {
                ref.read(syncWorkerProvider).flush(queue);
              }
            },
            child: const Text(
              'Sync maintenant',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
