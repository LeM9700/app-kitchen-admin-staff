import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/core/offline/sync_worker.dart';
import 'package:app_admin_staff/features/haccp/application/haccp_offline_service.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
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
      backgroundColor: HaccpPalette.background,
      appBar: AppBar(
        title: const Text('Sécurité alimentaire'),
        actions: [
          // Bouton NC avec badge — accès à HaccpNonConformityPage
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Badge(
              isLabelVisible: openNcCount > 0,
              label: Text(openNcCount.toString()),
              backgroundColor: AppColors.dangerAlt,
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
              loading: () => const HaccpSkeleton(),
              error: (e, _) => HaccpErrorState(
                message: haccpFriendlyError(
                  e,
                  'Impossible de charger les checks HACCP',
                ),
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
      backgroundColor: queued ? AppColors.infoAlt : AppColors.success,
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
            backgroundColor: AppColors.dangerAlt,
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
              content: Text(
                haccpFriendlyError(e, 'Impossible de valider le check HACCP'),
              ),
              backgroundColor: AppColors.dangerAlt,
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
    final started = summary.status != 'not_started';

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(haccpStatusProvider);
        ref.invalidate(haccpTodaySessionsProvider);
      },
      child: HaccpPageBody(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            // Progression : session, restant, terminé, NC
            _ProgressBanner(summary: summary, sessionType: widget.sessionType),
            const SizedBox(height: AppSpacing.md),

            if (!started)
              HaccpSection(
                title: 'Check $_label non démarré',
                subtitle: 'Démarrez le check pour commencer les relevés.',
                icon: Icons.play_circle_outline,
                tone: HaccpTone.info,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _startSession,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text('Démarrer le check $_label'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
              )
            else ...[
              // 1. Ce qui nécessite une action : NC de la session
              _NonConformitySection(sessionId: summary.sessionId!),
              // 2. Contrôles / saisies
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
              const SizedBox(height: AppSpacing.lg),

              // Bouton validation (admin uniquement)
              if (widget.isAdmin && !summary.isComplete)
                FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _completeSession(summary.sessionId!),
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text('Valider le check $_label'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: HaccpPalette.graphite,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),

              // Statut validé
              if (summary.isComplete)
                HaccpInfoBanner(
                  icon: Icons.check_circle_outline,
                  title: summary.status == 'incomplete_validated'
                      ? 'Validé avec réserves'
                      : 'Check $_label validé',
                  message: widget.canProceed
                      ? widget.sessionType == 'opening'
                          ? 'Le restaurant peut ouvrir.'
                          : 'La fermeture peut être confirmée.'
                      : 'Validation enregistrée.',
                  tone: summary.status == 'incomplete_validated'
                      ? HaccpTone.warning
                      : HaccpTone.ok,
                ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Bandeau de progression ───────────────────────────────────────────────────

class _ProgressBanner extends ConsumerWidget {
  const _ProgressBanner({
    required this.summary,
    required this.sessionType,
  });

  final HaccpSessionSummary summary;
  final String sessionType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final started = summary.status != 'not_started';
    final total = summary.temperaturesTotal + summary.cleaningTotal;
    final done = summary.temperaturesDone + summary.cleaningDone;
    final sessionId = summary.sessionId;
    final ncCount = sessionId == null
        ? 0
        : (ref
                .watch(haccpOpenNcProvider)
                .valueOrNull
                ?.where((nc) => nc.sessionId == sessionId)
                .length ??
            0);

    final tone = summary.isComplete
        ? (summary.status == 'incomplete_validated'
            ? HaccpTone.warning
            : HaccpTone.ok)
        : started
            ? HaccpTone.info
            : HaccpTone.neutral;

    final remainingTemps =
        (summary.temperaturesTotal - summary.temperaturesDone).clamp(0, 9999);
    final remainingCleaning =
        (summary.cleaningTotal - summary.cleaningDone).clamp(0, 9999);

    return HaccpProgressCard(
      title: sessionType == 'opening'
          ? 'HACCP — Ouverture'
          : 'HACCP — Fermeture',
      statusLabel: _statusLabel(summary.status),
      tone: tone,
      done: done,
      total: started ? total : 0,
      chips: !started
          ? const []
          : [
              HaccpStatusBadge(
                label:
                    '${summary.temperaturesDone}/${summary.temperaturesTotal} Températures',
                tone: remainingTemps == 0 ? HaccpTone.ok : HaccpTone.neutral,
                compact: true,
              ),
              HaccpStatusBadge(
                label:
                    '${summary.cleaningDone}/${summary.cleaningTotal} Nettoyage',
                tone:
                    remainingCleaning == 0 ? HaccpTone.ok : HaccpTone.neutral,
                compact: true,
              ),
              HaccpStatusBadge(
                label: '${summary.dlcDone} DLC',
                tone: summary.dlcDone > 0 ? HaccpTone.ok : HaccpTone.neutral,
                compact: true,
              ),
              if (ncCount > 0 || summary.hasNonConformities)
                HaccpStatusBadge(
                  label: ncCount > 0
                      ? '$ncCount NC ouverte${ncCount > 1 ? 's' : ''}'
                      : 'NC',
                  tone: HaccpTone.danger,
                  compact: true,
                ),
            ],
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
            backgroundColor: AppColors.warning,
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
            backgroundColor: AppColors.dangerAlt,
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
        loading: () => const HaccpInlineSkeleton(),
        error: (e, _) => HaccpInlineError(
          message: haccpFriendlyError(e, 'Équipements indisponibles'),
        ),
        data: (equipment) {
          final filtered = equipment
              .where(
                (e) => widget.sessionType == 'opening'
                    ? e.checkAtOpening
                    : e.checkAtClosing,
              )
              .toList();

          if (filtered.isEmpty) {
            return const HaccpInlineEmpty(
              message:
                  'Aucun équipement configuré. Contactez votre administrateur.',
            );
          }

          return logsAsync.when(
            loading: () => const HaccpInlineSkeleton(),
            error: (e, _) => HaccpInlineError(
              message: haccpFriendlyError(e, 'Relevés indisponibles'),
            ),
            data: (logs) {
              final loggedIds = logs.map((l) => l.equipmentId).toSet();
              final todo =
                  filtered.where((e) => !loggedIds.contains(e.id)).toList();
              final doneList =
                  filtered.where((e) => loggedIds.contains(e.id)).toList();
              Widget tile(HaccpEquipment equipment) {
                final done = loggedIds.contains(equipment.id);
                final log = done
                    ? logs.firstWhere((l) => l.equipmentId == equipment.id)
                    : null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _EquipmentTile(
                    equipment: equipment,
                    log: log,
                    done: done,
                    onTap: done ? null : () => _logTemp(equipment),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (todo.isNotEmpty) ...[
                    HaccpGroupLabel(
                      label: 'À FAIRE',
                      count: todo.length,
                      tone: HaccpTone.warning,
                    ),
                    ...todo.map(tile),
                  ],
                  if (doneList.isNotEmpty) ...[
                    HaccpGroupLabel(label: 'TERMINÉS', count: doneList.length),
                    ...doneList.map(tile),
                  ],
                ],
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

  String get _rangeSubtitle =>
      equipment.targetMinTemp == null || equipment.targetMaxTemp == null
          ? 'À relever'
          : 'À relever · cible ${equipment.tempRangeLabel}';

  @override
  Widget build(BuildContext context) {
    final l = log;
    if (done && l != null) {
      final at = l.loggedAt.toLocal();
      final hh = at.hour.toString().padLeft(2, '0');
      final mm = at.minute.toString().padLeft(2, '0');
      return HaccpMeasurementCard(
        title: equipment.name,
        primaryValue: '${l.measuredTemp.toStringAsFixed(1)} °C',
        subtitle:
            '${l.isCompliant ? 'Conforme' : 'Hors limite'} · relevé à $hh:$mm',
        icon: l.isCompliant ? Icons.check_circle : Icons.warning_amber_rounded,
        tone: l.isCompliant ? HaccpTone.ok : HaccpTone.danger,
      );
    }
    return HaccpTaskCard(
      title: equipment.name,
      subtitle: _rangeSubtitle,
      icon: _typeIcon,
      tone: HaccpTone.neutral,
      onTap: onTap,
      trailing: const Icon(
        Icons.add_circle_outline,
        color: HaccpPalette.graphite,
        size: 28,
        semanticLabel: 'Saisir la température',
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

  bool get _hasRange =>
      widget.equipment.targetMinTemp != null &&
      widget.equipment.targetMaxTemp != null;

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
    final typed = double.tryParse(widget.tempController.text);
    final HaccpTone? liveTone = typed == null || !_hasRange
        ? null
        : (_isCompliant ? HaccpTone.ok : HaccpTone.danger);

    return AlertDialog(
      backgroundColor: HaccpPalette.surface,
      scrollable: true,
      title: Text(widget.equipment.name),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_hasRange)
                Text(
                  'Plage cible : ${widget.equipment.tempRangeLabel}',
                  style: const TextStyle(
                    color: HaccpPalette.graphiteSoft,
                    fontSize: 13,
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: widget.tempController,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: HaccpPalette.graphite,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Température relevée',
                  suffixText: '°C',
                  filled: true,
                  fillColor: HaccpPalette.surfaceWarm,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                    horizontal: AppSpacing.md,
                  ),
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
              if (liveTone != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: HaccpStatusBadge(
                    label: liveTone == HaccpTone.ok
                        ? 'Conforme'
                        : 'Hors plage — non-conformité',
                    tone: liveTone,
                  ),
                ),
              ],
              if (_showNcField) ...[
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: widget.ncController,
                  decoration: InputDecoration(
                    labelText: 'Action corrective (optionnel)',
                    hintText: 'Ex: Alerte technicien, produits déplacés...',
                    filled: true,
                    fillColor: AppColors.dangerBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  maxLines: 2,
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
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
          style: FilledButton.styleFrom(
            minimumSize: const Size(140, 52),
            backgroundColor: HaccpPalette.graphite,
          ),
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
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              haccpFriendlyError(e, 'Impossible d enregistrer la saisie HACCP'),
            ),
            backgroundColor: AppColors.dangerAlt,
          ),
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
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Ajouter'),
        style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
      ),
      child: checksAsync.when(
        loading: () => const HaccpInlineSkeleton(rows: 1),
        error: (e, _) => HaccpInlineError(
          message: haccpFriendlyError(e, 'Vérifications DLC indisponibles'),
        ),
        data: (checks) {
          if (checks.isEmpty) {
            return const HaccpInlineEmpty(
              message:
                  'Aucune vérification DLC enregistrée. Appuyez sur Ajouter.',
            );
          }
          return Column(
            children: [
              for (final c in checks)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _DlcTile(check: c),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DlcTile extends StatelessWidget {
  const _DlcTile({required this.check});

  final HaccpDlcCheck check;

  /// Temps restant calcule depuis la date DLC saisie (jour calendaire).
  String get _remaining {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(check.dlcDate.year, check.dlcDate.month, check.dlcDate.day);
    final days = d.difference(today).inDays;
    if (days < 0) return 'Expirée depuis ${-days} j';
    if (days == 0) return "Échéance aujourd'hui";
    return 'J-$days';
  }

  @override
  Widget build(BuildContext context) {
    final tone = check.isCompliant ? HaccpTone.ok : HaccpTone.danger;
    final parts = <String>[
      check.levelLabel,
      if (check.batchId != null) 'Lot ${check.batchId}',
      'Échéance ${_formatDate(check.dlcDate)}',
      if (check.location != null) check.location!,
    ];
    return HaccpTaskCard(
      title: check.ingredientName,
      subtitle: '${parts.join(' · ')}\nTemps restant : $_remaining',
      icon: check.isCompliant ? Icons.check_circle_outline : Icons.event_busy,
      tone: tone,
      statusLabel: check.isCompliant ? 'Conforme' : 'Non conforme',
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

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
          SnackBar(
            content: Text(
              haccpFriendlyError(e, 'Impossible d enregistrer la saisie HACCP'),
            ),
            backgroundColor: AppColors.dangerAlt,
          ),
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
        loading: () => const HaccpInlineSkeleton(),
        error: (e, _) => HaccpInlineError(
          message: haccpFriendlyError(e, 'Tâches de nettoyage indisponibles'),
        ),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const HaccpInlineEmpty(
              message:
                  'Aucune tâche ND configurée. Contactez votre administrateur.',
            );
          }

          return logsAsync.when(
            loading: () => const HaccpInlineSkeleton(),
            error: (e, _) => HaccpInlineError(
              message: haccpFriendlyError(e, 'Historique nettoyage indisponible'),
            ),
            data: (logs) {
              final doneIds = logs.map((l) => l.taskId).toSet();
              final todo = tasks.where((t) => !doneIds.contains(t.id)).toList();
              final done = tasks.where((t) => doneIds.contains(t.id)).toList();

              String doneAt(int taskId) {
                final log = logs.firstWhere((l) => l.taskId == taskId);
                final at = log.completedAt.toLocal();
                return 'Fait à ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
              }

              Widget row(HaccpCleaningTask task, bool isDone) {
                final detail = [
                  task.zone,
                  if (task.productUsed != null) task.productUsed!,
                ].join(' · ');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: isDone
                        ? AppColors.successBg
                        : HaccpPalette.surfaceWarm,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: isDone ? null : () => _markDone(task.id),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isDone
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                size: 28,
                                color: isDone
                                    ? AppColors.success
                                    : HaccpPalette.graphiteSoft,
                                semanticLabel: isDone
                                    ? 'Tâche faite'
                                    : 'Marquer comme faite',
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: HaccpPalette.graphite,
                                      ),
                                    ),
                                    Text(
                                      isDone
                                          ? '${doneAt(task.id)} · $detail'
                                          : detail,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: HaccpPalette.graphiteSoft,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (todo.isNotEmpty) ...[
                    HaccpGroupLabel(
                      label: 'À FAIRE',
                      count: todo.length,
                      tone: HaccpTone.warning,
                    ),
                    ...todo.map((t) => row(t, false)),
                  ],
                  if (done.isNotEmpty) ...[
                    HaccpGroupLabel(label: 'TERMINÉS', count: done.length),
                    ...done.map((t) => row(t, true)),
                  ],
                ],
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

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: HaccpSection(
            title: 'Non-conformités (${sessionNcs.length})',
            subtitle: 'À traiter avant de valider la session',
            icon: Icons.report_problem_outlined,
            tone: HaccpTone.danger,
            action: TextButton(
              onPressed: () => context.push('/haccp/nc'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
              child: const Text('Ouvrir'),
            ),
            child: Column(
              children: [
                for (final nc in sessionNcs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: HaccpTaskCard(
                      title: nc.description,
                      subtitle: nc.correctiveAction != null
                          ? 'Action : ${nc.correctiveAction}'
                          : 'Action corrective requise',
                      icon: Icons.report_problem_outlined,
                      tone: HaccpTone.danger,
                      statusLabel: 'Ouverte',
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

// ─── Bandeau NC globales ──────────────────────────────────────────────────────

class _NcBanner extends StatelessWidget {
  const _NcBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final style = haccpToneStyle(HaccpTone.danger);
    return Container(
      width: double.infinity,
      color: style.background,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(Icons.report_problem_outlined, color: style.foreground, size: 18),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '$count non-conformité${count > 1 ? 's' : ''} ouverte${count > 1 ? 's' : ''}',
              style: TextStyle(
                color: style.foreground,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.push('/haccp/nc'),
            style: TextButton.styleFrom(
              foregroundColor: style.foreground,
              minimumSize: const Size(48, 40),
            ),
            child: const Text('Voir'),
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
    this.action,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return HaccpSection(
      title: title,
      icon: icon,
      action: action,
      tone: HaccpTone.info,
      child: child,
    );
  }
}

// Visible uniquement si [TenantConfig.haccpFryingOilEnabled] est `true`.
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

    return HaccpSection(
      title: 'Huile friteuse',
      icon: Icons.local_fire_department_outlined,
      tone: HaccpTone.warning,
      action: TextButton.icon(
        onPressed: () => _showOilForm(context, ref, sessionId),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Relever'),
        style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
      ),
      child: logsAsync.when(
        loading: () => const HaccpInlineSkeleton(rows: 1),
        error: (e, _) => HaccpInlineError(
          message: haccpFriendlyError(e, 'Relevés huile indisponibles'),
        ),
        data: (logs) {
          if (logs.isEmpty) {
            return const HaccpInlineEmpty(
              message: 'Aucun relevé huile pour cette session.',
            );
          }
          return Column(
            children: [
              for (final log in logs)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: HaccpMeasurementCard(
                    title: 'Polarité : ${log.polarityPercent.toStringAsFixed(1)} %',
                    primaryValue: log.isCompliant ? 'Conforme' : 'Non conforme',
                    subtitle: log.isCompliant
                        ? '≤ 25 % requis'
                        : (log.correctiveAction ?? 'NC — huile à changer'),
                    icon: log.isCompliant
                        ? Icons.check_circle
                        : Icons.warning_amber_rounded,
                    tone: log.isCompliant ? HaccpTone.ok : HaccpTone.danger,
                  ),
                ),
            ],
          );
        },
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
  // GELE (phase 2 UI) : reste volontairement a false, comme avant la refonte.
  // Ne pas brancher de seuil ici sans passe metier dediee.
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
          SnackBar(
            content: Text(
              haccpFriendlyError(e, 'Impossible d enregistrer la saisie HACCP'),
            ),
            backgroundColor: AppColors.dangerAlt,
          ),
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

// ─── Bannière offline HACCP ───────────────────────────────────────────────────

//// Etat de synchronisation HACCP (UI uniquement, lit la file existante).
///
///   1. Hors ligne : "Enregistre localement"
///   2. Actions en attente : "Synchronisation en attente" + bouton
///   3. Au moins une action a deja echoue : "Erreur de synchronisation"
///   4. Sinon : "Synchronise"
class _HaccpOfflineBanner extends ConsumerWidget {
  const _HaccpOfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(onlineStatusProvider).valueOrNull ?? true;
    final pendingCount = ref.watch(haccpPendingSyncCountProvider);
    final failedCount = ref
        .watch(syncQueueProvider)
        .where((a) => a.feature == 'haccp' && a.retryCount > 0)
        .length;

    return HaccpSyncStatus(
      isOnline: isOnline,
      pendingCount: pendingCount,
      failedCount: failedCount,
      showWhenSynced: true,
      onSync: () {
        final queue = ref.read(syncQueueProvider);
        if (queue.isNotEmpty) {
          ref.read(syncWorkerProvider).flush(queue);
        }
      },
    );
  }
}
