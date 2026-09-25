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

const double _kMaxContentWidth = 960;

/// Page de suivi des contrôles à réception fournisseurs.
///
/// Procédure légale à chaque livraison :
///   1. Température de livraison (chaîne du froid)
///   2. DLC produit
///   3. Intégrité de l'emballage
///   4. Conformité de l'étiquetage (nom, lot, allergènes)
class HaccpReceptionPage extends ConsumerWidget {
  const HaccpReceptionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receptionsAsync = ref.watch(haccpReceptionTodayProvider);

    return Scaffold(
      backgroundColor: HaccpPalette.background,
      appBar: AppBar(
        title: const Text('Contrôles réception'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(haccpReceptionTodayProvider),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
          child: receptionsAsync.when(
            loading: () => const HaccpSkeleton(),
            error: (e, _) => HaccpErrorState(
              message: haccpFriendlyError(
                e,
                'Impossible de charger les réceptions',
              ),
              onRetry: () => ref.invalidate(haccpReceptionTodayProvider),
            ),
            data: (receptions) {
              final nonCompliant =
                  receptions.where((r) => !r.isCompliant).length;
              return RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(haccpReceptionTodayProvider),
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
                      title: 'Réceptions du jour',
                      subtitle: receptions.isEmpty
                          ? 'Enregistrez chaque livraison fournisseur.'
                          : '${receptions.length} réception(s) - '
                              '$nonCompliant non conforme(s)',
                      icon: Icons.local_shipping_outlined,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: () => _showReceptionForm(context, ref),
                            icon: const Icon(Icons.add),
                            label: const Text('Nouvelle réception'),
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
                    if (receptions.isEmpty)
                      const HaccpEmptyState(
                        icon: Icons.local_shipping_outlined,
                        title: 'Aucune réception aujourd\'hui',
                        message: 'Enregistrez chaque livraison fournisseur.',
                      )
                    else ...[
                      const _SectionTitle(
                        icon: Icons.history,
                        label: 'Historique du jour',
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      for (final r in receptions) ...[
                        _ReceptionCard(reception: r),
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

  void _showReceptionForm(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: HaccpPalette.background,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => _ReceptionForm(
        onSaved: () {
          ref.invalidate(haccpReceptionTodayProvider);
          ref.invalidate(haccpOpenNcProvider);
        },
      ),
    );
  }
}

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

// ─── Carte réception ──────────────────────────────────────────────────────────

class _ReceptionCard extends StatelessWidget {
  const _ReceptionCard({required this.reception});

  final HaccpReceptionControl reception;

  @override
  Widget build(BuildContext context) {
    final compliant = reception.isCompliant;
    final tone = haccpToneForCompliance(compliant);
    final style = haccpToneStyle(tone);

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reception.productName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: HaccpPalette.graphite,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reception.batchRef == null || reception.batchRef!.isEmpty
                          ? reception.supplierName
                          : '${reception.supplierName} · lot ${reception.batchRef}',
                      style: const TextStyle(
                        color: HaccpPalette.graphiteSoft,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  HaccpStatusBadge(
                    label: compliant ? 'Conforme' : 'Non conforme',
                    tone: tone,
                    compact: true,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timeLabel(reception.controlledAt),
                    style: const TextStyle(
                      color: HaccpPalette.graphiteSoft,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (reception.deliveryTemp != null)
                HaccpStatusBadge(
                  label:
                      'Temp. ${reception.deliveryTemp!.toStringAsFixed(1)}°C',
                  tone: haccpToneForCompliance(reception.tempOk),
                  compact: true,
                ),
              if (reception.dlcDate != null)
                HaccpStatusBadge(
                  label: 'DLC ${_dateLabel(reception.dlcDate!)}',
                  tone: haccpToneForCompliance(
                    reception.dlcDate!.isAfter(DateTime.now()),
                  ),
                  compact: true,
                ),
              HaccpStatusBadge(
                label: 'Emballage',
                tone: haccpToneForCompliance(reception.packagingOk),
                compact: true,
              ),
              HaccpStatusBadge(
                label: 'Étiquetage',
                tone: haccpToneForCompliance(reception.labelingOk),
                compact: true,
              ),
            ],
          ),
          if (!compliant && reception.correctiveAction != null) ...[
            const SizedBox(height: AppSpacing.sm),
            HaccpInfoBanner(
              icon: Icons.build_outlined,
              title: 'Action corrective',
              message: reception.correctiveAction!,
              tone: HaccpTone.warning,
            ),
          ],
        ],
      ),
    );
  }

  String _timeLabel(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _dateLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ─── Formulaire réception (checklist) ─────────────────────────────────────────

class _ReceptionForm extends ConsumerStatefulWidget {
  const _ReceptionForm({required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<_ReceptionForm> createState() => _ReceptionFormState();
}

class _ReceptionFormState extends ConsumerState<_ReceptionForm> {
  final _formKey = GlobalKey<FormState>();
  final _supplierCtrl = TextEditingController();
  final _productCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();
  final _tempCtrl = TextEditingController();
  final _correctiveCtrl = TextEditingController();

  bool _packagingOk = true;
  bool _labelingOk = true;
  bool _tempOk = true;
  DateTime? _dlcDate;
  bool _saving = false;

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _productCtrl.dispose();
    _batchCtrl.dispose();
    _tempCtrl.dispose();
    _correctiveCtrl.dispose();
    super.dispose();
  }

  bool get _hasNonCompliance => !_packagingOk || !_labelingOk || !_tempOk;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final temp = double.tryParse(_tempCtrl.text.replaceAll(',', '.'));

    try {
      final result =
          await ref.read(haccpOfflineServiceProvider).createReceptionControl({
        'supplier_name': _supplierCtrl.text.trim(),
        'product_name': _productCtrl.text.trim(),
        if (_batchCtrl.text.trim().isNotEmpty)
          'batch_ref': _batchCtrl.text.trim(),
        if (temp != null) 'delivery_temp': temp,
        if (_dlcDate != null)
          'dlc_date':
              '${_dlcDate!.year}-${_dlcDate!.month.toString().padLeft(2, '0')}-${_dlcDate!.day.toString().padLeft(2, '0')}',
        'packaging_ok': _packagingOk,
        'labeling_ok': _labelingOk,
        'temp_ok': _tempOk,
        if (_correctiveCtrl.text.trim().isNotEmpty)
          'corrective_action': _correctiveCtrl.text.trim(),
      });

      widget.onSaved();
      if (mounted) {
        final queued = result is QueuedForSync<HaccpReceptionControl>;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              queued
                  ? '${result.label}. Enregistré localement, synchronisation en attente.'
                  : 'Réception enregistrée',
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
              haccpFriendlyError(e, 'Impossible d’enregistrer la réception'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String label, {String? suffix}) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: HaccpPalette.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 18,
      ),
    );
  }

  Future<void> _pickDlc() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dlcDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date != null) setState(() => _dlcDate = date);
  }

  @override
  Widget build(BuildContext context) {
    final dlcLabel = _dlcDate == null
        ? 'Choisir la date'
        : '${_dlcDate!.day.toString().padLeft(2, '0')}/${_dlcDate!.month.toString().padLeft(2, '0')}/${_dlcDate!.year}';

    return Form(
      key: _formKey,
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
                  const Expanded(
                    child: Text(
                      'Contrôle réception',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: HaccpPalette.graphite,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
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
                  children: [
                    HaccpSection(
                      title: 'Livraison',
                      subtitle: 'Fournisseur et produit reçu',
                      icon: Icons.local_shipping_outlined,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _supplierCtrl,
                            decoration: _decoration('Fournisseur *'),
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? 'Requis' : null,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextFormField(
                            controller: _productCtrl,
                            decoration: _decoration('Produit *'),
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? 'Requis' : null,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextFormField(
                            controller: _batchCtrl,
                            decoration: _decoration('Référence lot'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _CheckStep(
                      index: 1,
                      title: 'Température',
                      icon: Icons.thermostat,
                      ok: _tempOk,
                      onChanged: (v) => setState(() => _tempOk = v),
                      child: TextFormField(
                        controller: _tempCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration:
                            _decoration('Temp. livraison (°C)', suffix: '°C'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _CheckStep(
                      index: 2,
                      title: 'DLC',
                      icon: Icons.event_outlined,
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: _pickDlc,
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text('DLC produit : $dlcLabel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: HaccpPalette.graphite,
                            side: const BorderSide(color: HaccpPalette.border),
                            alignment: Alignment.centerLeft,
                            backgroundColor: HaccpPalette.surface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _CheckStep(
                      index: 3,
                      title: 'Emballage',
                      icon: Icons.inventory_2_outlined,
                      subtitle: 'Emballage intact',
                      ok: _packagingOk,
                      onChanged: (v) => setState(() => _packagingOk = v),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _CheckStep(
                      index: 4,
                      title: 'Étiquetage',
                      icon: Icons.sell_outlined,
                      subtitle: 'Nom, lot, allergènes',
                      ok: _labelingOk,
                      onChanged: (v) => setState(() => _labelingOk = v),
                    ),
                    if (_hasNonCompliance) ...[
                      const SizedBox(height: AppSpacing.sm),
                      HaccpSection(
                        title: 'Observations',
                        subtitle: 'Action corrective requise',
                        icon: Icons.build_outlined,
                        tone: HaccpTone.warning,
                        child: TextFormField(
                          controller: _correctiveCtrl,
                          maxLines: 3,
                          decoration:
                              _decoration('Action corrective *').copyWith(
                            hintText:
                                'Ex : Lot refusé et retourné au fournisseur',
                          ),
                          validator: (v) => _hasNonCompliance &&
                                  (v == null || v.trim().isEmpty)
                              ? 'Requis en cas de non-conformité'
                              : null,
                        ),
                      ),
                    ],
                  ],
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
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('VALIDER LA RECEPTION'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _hasNonCompliance
                        ? AppColors.warning
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

/// Étape de checklist : numéro, titre, état conforme/non conforme (si [ok]
/// est fourni) et contenu de saisie éventuel.
class _CheckStep extends StatelessWidget {
  const _CheckStep({
    required this.index,
    required this.title,
    required this.icon,
    this.subtitle,
    this.ok,
    this.onChanged,
    this.child,
  });

  final int index;
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool? ok;
  final ValueChanged<bool>? onChanged;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tone = ok == null
        ? HaccpTone.neutral
        : (ok! ? HaccpTone.ok : HaccpTone.danger);
    final style = haccpToneStyle(tone);

    return DsCard(
      backgroundColor: HaccpPalette.surface,
      borderColor: ok == false
          ? style.foreground.withValues(alpha: 0.5)
          : HaccpPalette.border,
      borderRadius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      intensity: NeumorphicIntensity.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: style.background,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: style.foreground, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$index. $title',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: HaccpPalette.graphite,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: HaccpPalette.graphiteSoft,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: AppSpacing.sm),
            child!,
          ],
          if (ok != null && onChanged != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 52,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.check),
                    label: Text('Conforme'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.close),
                    label: Text('Non conforme'),
                  ),
                ],
                selected: {ok!},
                onSelectionChanged: (s) => onChanged!(s.first),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
