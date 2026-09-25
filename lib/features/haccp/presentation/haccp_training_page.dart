import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Page registre de formation hygiène (admin uniquement).
///
/// Obligation légale : arrêté du 12 février 2024 — au moins un employé
/// permanent formé à l'hygiène alimentaire (14h minimum) dans l'établissement.
/// Le registre doit être présentable lors d'une inspection DDPP.
class HaccpTrainingPage extends ConsumerWidget {
  const HaccpTrainingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trainingAsync = ref.watch(haccpTrainingProvider);

    return Scaffold(
      backgroundColor: HaccpPalette.background,
      appBar: AppBar(
        title: const Text('Registre de formation'),
        backgroundColor: HaccpPalette.background,
        foregroundColor: HaccpPalette.graphite,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: () => ref.invalidate(haccpTrainingProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(context, ref),
        icon: const Icon(Icons.school),
        label: const Text('Ajouter formation'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: trainingAsync.when(
            loading: () => const HaccpSkeleton(),
            error: (e, _) => HaccpErrorState(
              message: haccpFriendlyError(
                e,
                'Impossible de charger le registre de formation',
              ),
              onRetry: () => ref.invalidate(haccpTrainingProvider),
            ),
            data: (records) => _TrainingBody(
              records: records,
              onRefresh: () async => ref.invalidate(haccpTrainingProvider),
            ),
          ),
        ),
      ),
    );
  }

  void _showForm(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TrainingForm(
        onSaved: () => ref.invalidate(haccpTrainingProvider),
      ),
    );
  }
}

String _dateLabel(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

({String label, HaccpTone tone}) _trainingStatus(HaccpTrainingRecord r) {
  if (r.isExpired) return (label: 'Expirée', tone: HaccpTone.danger);
  if (r.expiresWithin30Days) {
    return (label: 'Expire bientôt', tone: HaccpTone.warning);
  }
  return (label: 'Valide', tone: HaccpTone.ok);
}

// ─── Corps ────────────────────────────────────────────────────────────────────

class _TrainingBody extends StatelessWidget {
  const _TrainingBody({required this.records, required this.onRefresh});

  final List<HaccpTrainingRecord> records;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final expired = records.where((r) => r.isExpired).length;
    final expiring =
        records.where((r) => !r.isExpired && r.expiresWithin30Days).length;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          100,
        ),
        children: [
          if (expired > 0 || expiring > 0) ...[
            HaccpInfoBanner(
              icon: Icons.warning_amber_outlined,
              title: expired > 0
                  ? '$expired formation(s) expirée(s)'
                  : '$expiring formation(s) expirant sous 30 jours',
              message: expired > 0 && expiring > 0
                  ? '$expiring formation(s) expirant dans moins de 30 jours.'
                  : 'À renouveler pour garder le registre à jour.',
              tone: expired > 0 ? HaccpTone.danger : HaccpTone.warning,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          const HaccpInfoBanner(
            icon: Icons.info_outline,
            title: 'Registre de formation',
            message: 'Arrêté 12/02/2024 — Au moins 1 formé permanent. '
                'Registre présentable à la DDPP.',
            tone: HaccpTone.info,
          ),
          const SizedBox(height: AppSpacing.md),
          if (records.isEmpty)
            const HaccpEmptyState(
              icon: Icons.school_outlined,
              title: 'Aucune formation enregistrée',
              message: 'Ajoutez une formation pour alimenter le registre.',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 720) {
                  return _TrainingTable(records: records);
                }
                return Column(
                  children: [
                    for (var i = 0; i < records.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.sm),
                      _TrainingCard(record: records[i]),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─── Tableau (largeur >= 720) ─────────────────────────────────────────────────

class _TrainingTable extends StatelessWidget {
  const _TrainingTable({required this.records});

  final List<HaccpTrainingRecord> records;

  @override
  Widget build(BuildContext context) {
    const headStyle = TextStyle(
      color: HaccpPalette.graphiteSoft,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
    );
    return Container(
      decoration: BoxDecoration(
        color: HaccpPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HaccpPalette.border),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('EMPLOYÉ', style: headStyle)),
                Expanded(flex: 4, child: Text('FORMATION', style: headStyle)),
                Expanded(flex: 2, child: Text('DATE', style: headStyle)),
                Expanded(flex: 2, child: Text('ÉCHÉANCE', style: headStyle)),
                Expanded(flex: 2, child: Text('STATUT', style: headStyle)),
              ],
            ),
          ),
          for (final r in records) ...[
            const Divider(height: 1, color: HaccpPalette.border),
            _TrainingRow(record: r),
          ],
        ],
      ),
    );
  }
}

class _TrainingRow extends StatelessWidget {
  const _TrainingRow({required this.record});

  final HaccpTrainingRecord record;

  @override
  Widget build(BuildContext context) {
    const cell = TextStyle(color: HaccpPalette.graphite, fontSize: 13);
    final status = _trainingStatus(record);
    final expiry = record.expiryDate;
    final extra = [
      if (record.trainerName != null) record.trainerName!,
      if (record.certificateRef != null) 'Réf. ${record.certificateRef}',
    ].join(' • ');
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 2,
            child: Text('Employé #${record.userId}', style: cell),
          ),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.trainingTypeLabel,
                  style: cell.copyWith(fontWeight: FontWeight.w700),
                ),
                if (extra.isNotEmpty)
                  Text(
                    extra,
                    style: const TextStyle(
                      color: HaccpPalette.graphiteSoft,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(_dateLabel(record.trainingDate), style: cell),
          ),
          Expanded(
            flex: 2,
            child: Text(expiry == null ? '—' : _dateLabel(expiry), style: cell),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: HaccpStatusBadge(
                label: status.label,
                tone: status.tone,
                compact: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Carte formation (mobile) ─────────────────────────────────────────────────

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({required this.record});

  final HaccpTrainingRecord record;

  @override
  Widget build(BuildContext context) {
    final status = _trainingStatus(record);
    final expiry = record.expiryDate;
    const label = TextStyle(color: HaccpPalette.graphiteSoft, fontSize: 12);
    const value = TextStyle(
      color: HaccpPalette.graphite,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );

    Widget line(String k, String v) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 78, child: Text(k, style: label)),
              Expanded(child: Text(v, style: value)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: HaccpPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: haccpToneStyle(status.tone).foreground.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  record.trainingTypeLabel,
                  style: const TextStyle(
                    color: HaccpPalette.graphite,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              HaccpStatusBadge(
                label: status.label,
                tone: status.tone,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          line('Employé', '#${record.userId}'),
          line('Date', _dateLabel(record.trainingDate)),
          line('Échéance', expiry == null ? '—' : _dateLabel(expiry)),
          if (record.trainerName != null)
            line('Formateur', record.trainerName!),
          if (record.certificateRef != null)
            line('Réf.', record.certificateRef!),
          if (record.notes != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              record.notes!,
              style: const TextStyle(
                color: HaccpPalette.graphiteSoft,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Formulaire formation ─────────────────────────────────────────────────────

class _TrainingForm extends ConsumerStatefulWidget {
  const _TrainingForm({required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<_TrainingForm> createState() => _TrainingFormState();
}

class _TrainingFormState extends ConsumerState<_TrainingForm> {
  final _formKey = GlobalKey<FormState>();
  final _trainerCtrl = TextEditingController();
  final _certCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _type = 'hygiene_initial';
  DateTime _trainingDate = DateTime.now();
  DateTime? _expiryDate;
  bool _saving = false;

  static const _types = [
    ('hygiene_initial', 'Hygiène alimentaire (initiale)'),
    ('hygiene_refresher', 'Hygiène alimentaire (recyclage)'),
    ('haccp', 'HACCP / PMS'),
    ('allergens', 'Gestion des allergènes'),
    ('fire_safety', 'Sécurité incendie'),
  ];

  @override
  void dispose() {
    _trainerCtrl.dispose();
    _certCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isExpiry) async {
    final initial = isExpiry
        ? (_expiryDate ?? DateTime.now().add(const Duration(days: 365)))
        : _trainingDate;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: isExpiry ? DateTime.now() : DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    setState(() {
      if (isExpiry) {
        _expiryDate = date;
      } else {
        _trainingDate = date;
      }
    });
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await ref.read(haccpRepositoryProvider).createTrainingRecord({
        'training_type': _type,
        'training_date': _isoDate(_trainingDate),
        if (_expiryDate != null) 'expiry_date': _isoDate(_expiryDate!),
        if (_trainerCtrl.text.trim().isNotEmpty)
          'trainer_name': _trainerCtrl.text.trim(),
        if (_certCtrl.text.trim().isNotEmpty)
          'certificate_ref': _certCtrl.text.trim(),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      });
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              haccpFriendlyError(e, 'Enregistrement impossible'),
            ),
            backgroundColor: haccpToneStyle(HaccpTone.danger).foreground,
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ajouter une formation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Type formation
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Type de formation *',
                  border: OutlineInputBorder(),
                ),
                items: _types
                    .map(
                      (t) => DropdownMenuItem(
                        value: t.$1,
                        child: Text(t.$2, style: const TextStyle(fontSize: 13)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Dates
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(false),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date formation *',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today, size: 16),
                        ),
                        child: Text(
                          _fmt(_trainingDate),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(true),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date expiration',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today, size: 16),
                        ),
                        child: Text(
                          _expiryDate == null ? '—' : _fmt(_expiryDate!),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _trainerCtrl,
                decoration: const InputDecoration(
                  labelText: 'Formateur',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _certCtrl,
                decoration: const InputDecoration(
                  labelText: 'Référence certificat',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
              ),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
