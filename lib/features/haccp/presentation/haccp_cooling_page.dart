import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_elevation.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/application/haccp_offline_service.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double _kMaxContentWidth = 960;

/// Page de suivi du refroidissement rapide.
///
/// Norme légale : descendre en dessous de 10°C en moins de 2h
/// (Règlement CE 852/2004 + guide GEMRCN).
///
/// Workflow :
///   1. Démarrer un suivi (produit + température initiale)
///   2. Après ≤ 2h, enregistrer la température finale
///   3. Si T° finale > 10°C → NC automatique
class HaccpCoolingPage extends ConsumerWidget {
  const HaccpCoolingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coolingAsync = ref.watch(haccpAllCoolingProvider);

    return Scaffold(
      backgroundColor: HaccpPalette.background,
      appBar: AppBar(
        title: const Text('Refroidissement rapide'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(haccpAllCoolingProvider);
              ref.invalidate(haccpActiveCoolingProvider);
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
          child: coolingAsync.when(
            loading: () => const HaccpSkeleton(),
            error: (e, _) => HaccpErrorState(
              message: haccpFriendlyError(
                e,
                'Impossible de charger les refroidissements',
              ),
              onRetry: () => ref.invalidate(haccpAllCoolingProvider),
            ),
            data: (logs) {
              final active = logs.where((l) => l.isInProgress).toList();
              final done = logs.where((l) => !l.isInProgress).toList();

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(haccpAllCoolingProvider),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.xxl,
                  ),
                  children: [
                    HaccpPageHeader(
                      title: 'Suivi du refroidissement',
                      subtitle: logs.isEmpty
                          ? 'Objectif légal : < 10°C en moins de 2h'
                          : '${active.length} en cours - ${done.length} terminé(s)',
                      icon: Icons.ac_unit,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: () => _showStartForm(context, ref),
                            icon: const Icon(Icons.thermostat),
                            label: const Text('Démarrer suivi'),
                            style: FilledButton.styleFrom(
                              backgroundColor: HaccpPalette.graphite,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (logs.isEmpty)
                      const HaccpEmptyState(
                        icon: Icons.ac_unit,
                        title: 'Aucun suivi de refroidissement',
                        message: 'Objectif légal : < 10°C en moins de 2h',
                      ),
                    if (active.isNotEmpty) ...[
                      _SectionTitle(
                        icon: Icons.timer_outlined,
                        label: 'En cours (${active.length})',
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      for (final l in active) ...[
                        _CoolingCard(
                          log: l,
                          onComplete: () => _showCompleteForm(context, ref, l),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    if (done.isNotEmpty) ...[
                      _SectionTitle(
                        icon: Icons.history,
                        label: 'Terminés (${done.length})',
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      for (final l in done) ...[
                        _CoolingCard(log: l),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showStartForm(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: HaccpPalette.background,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => _StartCoolingForm(
        onSaved: () {
          ref.invalidate(haccpAllCoolingProvider);
          ref.invalidate(haccpActiveCoolingProvider);
        },
      ),
    );
  }

  void _showCompleteForm(
    BuildContext context,
    WidgetRef ref,
    HaccpCoolingLog log,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: HaccpPalette.background,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => _CompleteCoolingForm(
        log: log,
        onSaved: () {
          ref.invalidate(haccpAllCoolingProvider);
          ref.invalidate(haccpActiveCoolingProvider);
          ref.invalidate(haccpOpenNcProvider);
          ref.invalidate(haccpStatusProvider);
        },
      ),
    );
  }
}

// ─── Composants privés ────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: HaccpPalette.graphiteSoft),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: HaccpPalette.graphiteSoft,
            ),
          ),
        ),
      ],
    );
  }
}

String _timeLabel(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Point de la timeline : heure (si connue), libellé et température.
class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.time,
    required this.label,
    required this.temp,
    required this.tone,
    required this.isLast,
  });

  final String? time;
  final String label;
  final double temp;
  final HaccpTone tone;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final style = haccpToneStyle(tone);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Align(
              alignment: Alignment.topRight,
              child: Text(
                time ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: HaccpPalette.graphite,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          SizedBox(
            width: 14,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: style.foreground,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: HaccpPalette.border),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: HaccpPalette.graphiteSoft,
                    ),
                  ),
                  Text(
                    '${temp.toStringAsFixed(1)}°C',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: style.foreground,
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

// ─── Carte refroidissement ────────────────────────────────────────────────────

class _CoolingCard extends StatelessWidget {
  const _CoolingCard({required this.log, this.onComplete});

  final HaccpCoolingLog log;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final isActive = log.isInProgress;
    final compliant = log.isCompliant;

    final tone = isActive
        ? HaccpTone.warning
        : (compliant ? HaccpTone.ok : HaccpTone.danger);
    final style = haccpToneStyle(tone);
    final badgeLabel =
        isActive ? 'En cours' : (compliant ? 'Conforme' : 'Non conforme');

    final elapsed =
        isActive ? DateTime.now().difference(log.startedAt).inMinutes : null;
    final twoHoursWarning = elapsed != null && elapsed >= 90;

    return DsCard(
      backgroundColor: HaccpPalette.surface,
      borderColor: style.foreground.withValues(alpha: 0.3),
      borderRadius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      intensity: NeumorphicIntensity.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  log.productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: HaccpPalette.graphite,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              HaccpStatusBadge(label: badgeLabel, tone: tone, compact: true),
            ],
          ),
          if (elapsed != null) ...[
            const SizedBox(height: 2),
            Text(
              'Écoulé : $elapsed min',
              style: TextStyle(
                color: twoHoursWarning
                    ? haccpToneStyle(HaccpTone.danger).foreground
                    : HaccpPalette.graphiteSoft,
                fontSize: 12,
                fontWeight: twoHoursWarning ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ] else if (log.durationMinutes != null) ...[
            const SizedBox(height: 2),
            Text(
              'Durée : ${log.durationMinutes} min',
              style: const TextStyle(
                color: HaccpPalette.graphiteSoft,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _TimelineEntry(
            time: _timeLabel(log.startedAt),
            label: 'Début',
            temp: log.tempInitial,
            tone: HaccpTone.ok,
            isLast: isActive || log.tempFinal == null,
          ),
          if (!isActive && log.tempFinal != null)
            _TimelineEntry(
              time: log.endedAt != null ? _timeLabel(log.endedAt!) : null,
              label: 'Fin',
              temp: log.tempFinal!,
              tone: log.tempFinal! <= 10 ? HaccpTone.ok : HaccpTone.danger,
              isLast: true,
            ),
          if (twoHoursWarning) ...[
            const SizedBox(height: AppSpacing.sm),
            const HaccpInfoBanner(
              icon: Icons.warning_amber,
              title: 'Objectif 2h bientôt dépassé',
              message: 'Enregistrez la T° finale.',
              tone: HaccpTone.danger,
            ),
          ],
          if (!compliant && log.correctiveAction != null) ...[
            const SizedBox(height: AppSpacing.sm),
            HaccpInfoBanner(
              icon: Icons.build_outlined,
              title: 'Action corrective',
              message: log.correctiveAction!,
              tone: HaccpTone.warning,
            ),
          ],
          if (isActive && onComplete != null) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: onComplete,
                icon: const Icon(Icons.thermostat, size: 20),
                label: const Text('Enregistrer T° finale'),
                style: FilledButton.styleFrom(
                  backgroundColor: HaccpPalette.graphite,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Formulaire démarrage ─────────────────────────────────────────────────────

class _StartCoolingForm extends ConsumerStatefulWidget {
  const _StartCoolingForm({required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<_StartCoolingForm> createState() => _StartCoolingFormState();
}

class _StartCoolingFormState extends ConsumerState<_StartCoolingForm> {
  final _formKey = GlobalKey<FormState>();
  final _productCtrl = TextEditingController();
  final _tempCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _productCtrl.dispose();
    _tempCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final result = await ref.read(haccpOfflineServiceProvider).startCooling({
        'product_name': _productCtrl.text.trim(),
        'temp_initial':
            double.parse(_tempCtrl.text.trim().replaceAll(',', '.')),
        'started_at': DateTime.now().toIso8601String(),
      });
      widget.onSaved();
      if (mounted) {
        final queued = result is QueuedForSync<HaccpCoolingLog>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              queued
                  ? '${result.label}. Enregistré localement, synchronisation en attente.'
                  : 'Suivi de refroidissement démarré',
            ),
            backgroundColor: queued ? Colors.blue.shade700 : Colors.green,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              haccpFriendlyError(
                e,
                'Impossible de démarrer le refroidissement',
              ),
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
    return _SheetScaffold(
      title: 'Démarrer un suivi',
      formKey: _formKey,
      saving: _saving,
      submitLabel: 'DÉMARRER',
      submitIcon: Icons.play_arrow,
      onSubmit: _submit,
      children: [
        const HaccpInfoBanner(
          icon: Icons.info_outline,
          title: 'Objectif légal',
          message: 'Atteindre ≤ 10°C en moins de 2h',
          tone: HaccpTone.info,
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _productCtrl,
          decoration: const InputDecoration(
            labelText: 'Produit / préparation *',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: HaccpPalette.surface,
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 18,
            ),
          ),
          validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        HaccpMeasurementInput(
          controller: _tempCtrl,
          label: 'Température initiale (°C) *',
          suffix: '°C',
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Requis';
            if (double.tryParse(v.replaceAll(',', '.')) == null) {
              return 'Valeur numérique invalide';
            }
            return null;
          },
        ),
      ],
    );
  }
}

// ─── Formulaire température finale ───────────────────────────────────────────

class _CompleteCoolingForm extends ConsumerStatefulWidget {
  const _CompleteCoolingForm({required this.log, required this.onSaved});

  final HaccpCoolingLog log;
  final VoidCallback onSaved;

  @override
  ConsumerState<_CompleteCoolingForm> createState() =>
      _CompleteCoolingFormState();
}

class _CompleteCoolingFormState extends ConsumerState<_CompleteCoolingForm> {
  final _formKey = GlobalKey<FormState>();
  final _tempCtrl = TextEditingController();
  final _correctiveCtrl = TextEditingController();
  bool _saving = false;

  double? get _tempValue =>
      double.tryParse(_tempCtrl.text.replaceAll(',', '.'));

  // GELE (phase 2 UI) : reste volontairement a false, comme avant la refonte.
  // Ne pas brancher de seuil ici sans passe metier dediee.
  bool get _nonCompliant => false;

  @override
  void dispose() {
    _tempCtrl.dispose();
    _correctiveCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final result =
          await ref.read(haccpOfflineServiceProvider).completeCooling(
                widget.log.id,
                tempFinal: _tempValue!,
                correctiveAction: _correctiveCtrl.text.trim().isNotEmpty
                    ? _correctiveCtrl.text.trim()
                    : null,
              );
      widget.onSaved();
      if (mounted) {
        final queued = result is QueuedForSync<HaccpCoolingLog>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              queued
                  ? '${result.label}. Enregistré localement, synchronisation en attente.'
                  : 'Température finale enregistrée',
            ),
            backgroundColor: queued ? Colors.blue.shade700 : Colors.green,
          ),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              haccpFriendlyError(
                e,
                'Impossible de terminer le refroidissement',
              ),
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
    return _SheetScaffold(
      title: 'Enregistrer T° finale',
      formKey: _formKey,
      saving: _saving,
      submitLabel: 'VALIDER',
      submitIcon: Icons.check,
      warn: _nonCompliant,
      onSubmit: _submit,
      children: [
        Text(
          '${widget.log.productName} — T° init. ${widget.log.tempInitial.toStringAsFixed(1)}°C',
          style: const TextStyle(
            color: HaccpPalette.graphiteSoft,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        HaccpMeasurementInput(
          controller: _tempCtrl,
          label: 'Température finale (°C) *',
          suffix: '°C',
          autofocus: true,
          onChanged: (_) => setState(() {}),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Requis';
            if (double.tryParse(v.replaceAll(',', '.')) == null) {
              return 'Valeur numérique invalide';
            }
            return null;
          },
        ),
        if (_tempValue != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: HaccpStatusBadge(
              label: _nonCompliant
                  ? 'NC — objectif ≤ 10°C non atteint'
                  : 'Conforme',
              tone: _nonCompliant ? HaccpTone.danger : HaccpTone.ok,
            ),
          ),
        ],
        if (_nonCompliant) ...[
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _correctiveCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Action corrective *',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: HaccpPalette.surface,
            ),
            validator: (v) => _nonCompliant && (v == null || v.trim().isEmpty)
                ? 'Requis en cas de NC'
                : null,
          ),
        ],
      ],
    );
  }
}

/// Feuille de saisie : titre, contenu défilant, bouton principal collé en bas.
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.formKey,
    required this.saving,
    required this.submitLabel,
    required this.submitIcon,
    required this.onSubmit,
    required this.children,
    this.warn = false,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final bool saving;
  final String submitLabel;
  final IconData submitIcon;
  final VoidCallback onSubmit;
  final List<Widget> children;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: HaccpPalette.graphite,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed:
                        saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: const BoxDecoration(
                color: HaccpPalette.surface,
                border: Border(top: BorderSide(color: HaccpPalette.border)),
              ),
              child: SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: saving ? null : onSubmit,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(submitIcon),
                  label: Text(submitLabel),
                  style: FilledButton.styleFrom(
                    backgroundColor: warn
                        ? haccpToneStyle(HaccpTone.warning).foreground
                        : HaccpPalette.graphite,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
