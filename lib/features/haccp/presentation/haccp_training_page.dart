import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
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
      appBar: AppBar(
        title: const Text('Registre de formation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(haccpTrainingProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(context, ref),
        icon: const Icon(Icons.school),
        label: const Text('Ajouter formation'),
      ),
      body: trainingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: AppSpacing.sm),
              Text(e.toString()),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: () => ref.invalidate(haccpTrainingProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (records) {
          // Alertes : formations expirées ou expirant dans 30j
          final expiring = records
              .where((r) => !r.isExpired && r.expiresWithin30Days)
              .toList();
          final expired = records.where((r) => r.isExpired).toList();

          return Column(
            children: [
              // Bannière alerte
              if (expired.isNotEmpty || expiring.isNotEmpty)
                _AlertBanner(
                    expired: expired.length, expiring: expiring.length),

              // Info légale
              Container(
                margin: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.blue),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Arrêté 12/02/2024 — Au moins 1 formé permanent. '
                        'Registre présentable à la DDPP.',
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.school_outlined,
                                size: 56, color: Colors.grey[300]),
                            const SizedBox(height: AppSpacing.md),
                            const Text(
                              'Aucune formation enregistrée',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(haccpTrainingProvider),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md, AppSpacing.sm, AppSpacing.md, 100),
                          itemCount: records.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (context, i) =>
                              _TrainingCard(record: records[i]),
                        ),
                      ),
              ),
            ],
          );
        },
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

// ─── Bannière alerte ──────────────────────────────────────────────────────────

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.expired, required this.expiring});

  final int expired;
  final int expiring;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: expired > 0
            ? Colors.red.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: expired > 0
              ? Colors.red.withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber,
            color: expired > 0 ? Colors.red : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (expired > 0)
                  Text(
                    '$expired formation(s) expirée(s)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.red,
                        fontSize: 13),
                  ),
                if (expiring > 0)
                  Text(
                    '$expiring formation(s) expirant dans moins de 30j',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                        fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Carte formation ──────────────────────────────────────────────────────────

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({required this.record});

  final HaccpTrainingRecord record;

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (record.isExpired) {
      statusColor = Colors.red;
      statusLabel = 'Expirée';
      statusIcon = Icons.error_outline;
    } else if (record.expiresWithin30Days) {
      statusColor = Colors.orange;
      statusLabel = 'Expire bientôt';
      statusIcon = Icons.schedule;
    } else {
      statusColor = Colors.green;
      statusLabel = 'Valide';
      statusIcon = Icons.check_circle_outline;
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    record.trainingTypeLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Formé le ${_dateLabel(record.trainingDate)}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                if (record.expiryDate != null) ...[
                  const Text(' · ',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(
                    'Expire le ${_dateLabel(record.expiryDate!)}',
                    style: TextStyle(
                        color: record.isExpired
                            ? Colors.red
                            : record.expiresWithin30Days
                                ? Colors.orange
                                : Colors.grey,
                        fontSize: 12,
                        fontWeight:
                            record.isExpired || record.expiresWithin30Days
                                ? FontWeight.w600
                                : FontWeight.normal),
                  ),
                ],
              ],
            ),
            if (record.trainerName != null) ...[
              const SizedBox(height: 2),
              Text(
                '🎓 ${record.trainerName}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            if (record.certificateRef != null) ...[
              const SizedBox(height: 2),
              Text(
                '📄 Réf. ${record.certificateRef}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            if (record.notes != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                record.notes!,
                style:
                    const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ajouter une formation',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.lg),

              // Type formation
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                    labelText: 'Type de formation *',
                    border: OutlineInputBorder()),
                items: _types
                    .map((t) => DropdownMenuItem(
                          value: t.$1,
                          child:
                              Text(t.$2, style: const TextStyle(fontSize: 13)),
                        ))
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
                        child: Text(_fmt(_trainingDate),
                            style: const TextStyle(fontSize: 14)),
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
                    labelText: 'Formateur', border: OutlineInputBorder()),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _certCtrl,
                decoration: const InputDecoration(
                    labelText: 'Référence certificat',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Notes', border: OutlineInputBorder()),
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
                          child: CircularProgressIndicator(strokeWidth: 2))
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
