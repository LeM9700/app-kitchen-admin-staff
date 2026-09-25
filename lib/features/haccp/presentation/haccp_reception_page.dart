import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/application/haccp_offline_service.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      appBar: AppBar(
        title: const Text('Contrôles réception'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(haccpReceptionTodayProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showReceptionForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle réception'),
      ),
      body: receptionsAsync.when(
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
                onPressed: () => ref.invalidate(haccpReceptionTodayProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (receptions) {
          if (receptions.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_shipping_outlined,
                    size: 56,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Aucune réception aujourd\'hui',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Enregistrez chaque livraison fournisseur.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(haccpReceptionTodayProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                100,
              ),
              itemCount: receptions.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) =>
                  _ReceptionCard(reception: receptions[i]),
            ),
          );
        },
      ),
    );
  }

  void _showReceptionForm(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReceptionForm(
        onSaved: () {
          ref.invalidate(haccpReceptionTodayProvider);
          ref.invalidate(haccpOpenNcProvider);
        },
      ),
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
    final color = compliant ? Colors.green : Colors.red;

    return DsCard(
      borderRadius: 12,
      borderColor: color.withValues(alpha: 0.3),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                compliant ? Icons.check_circle : Icons.cancel,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  reception.productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                _timeLabel(reception.controlledAt),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '📦 ${reception.supplierName}',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: 6,
            children: [
              if (reception.deliveryTemp != null)
                _CheckChip(
                  label: '🌡️ ${reception.deliveryTemp!.toStringAsFixed(1)}°C',
                  ok: reception.tempOk,
                ),
              _CheckChip(label: '📦 Emballage', ok: reception.packagingOk),
              _CheckChip(label: '🏷️ Étiquetage', ok: reception.labelingOk),
              if (reception.dlcDate != null)
                _CheckChip(
                  label: 'DLC ${_dateLabel(reception.dlcDate!)}',
                  ok: reception.dlcDate!.isAfter(DateTime.now()),
                ),
            ],
          ),
          if (!compliant && reception.correctiveAction != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.build_outlined,
                    size: 13,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      reception.correctiveAction!,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
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

class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: ok
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.red.withValues(alpha: 0.1),
      side: BorderSide(
        color: ok
            ? Colors.green.withValues(alpha: 0.3)
            : Colors.red.withValues(alpha: 0.3),
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

// ─── Formulaire réception ─────────────────────────────────────────────────────

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
                  ? '${result.label}. Enregistre localement, synchronisation en attente.'
                  : 'Reception enregistree',
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
              haccpFriendlyError(e, 'Impossible d enregistrer la reception'),
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
                'Contrôle réception',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Fournisseur + produit
              TextFormField(
                controller: _supplierCtrl,
                decoration: const InputDecoration(
                  labelText: 'Fournisseur *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Requis' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _productCtrl,
                decoration: const InputDecoration(
                  labelText: 'Produit *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Requis' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _batchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Référence lot',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // Température
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tempCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Temp. livraison (°C)',
                        border: OutlineInputBorder(),
                        suffixText: '°C',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 730)),
                        );
                        if (date != null) setState(() => _dlcDate = date);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'DLC produit',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today, size: 16),
                        ),
                        child: Text(
                          _dlcDate == null
                              ? '—'
                              : '${_dlcDate!.day.toString().padLeft(2, '0')}/${_dlcDate!.month.toString().padLeft(2, '0')}/${_dlcDate!.year}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),

              // Checklist conformité
              Text(
                'Points de contrôle',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              _ConformityRow(
                label: '📦 Emballage intact',
                value: _packagingOk,
                onChanged: (v) => setState(() => _packagingOk = v ?? true),
              ),
              _ConformityRow(
                label: '🏷️ Étiquetage conforme',
                value: _labelingOk,
                onChanged: (v) => setState(() => _labelingOk = v ?? true),
              ),
              _ConformityRow(
                label: '🌡️ Température conforme',
                value: _tempOk,
                onChanged: (v) => setState(() => _tempOk = v ?? true),
              ),

              // Action corrective si non-conforme
              if (_hasNonCompliance) ...[
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _correctiveCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Action corrective *',
                    hintText: 'Ex : Lot refusé et retourné au fournisseur',
                    border: OutlineInputBorder(),
                    fillColor: Color(0xFFFFF3E0),
                    filled: true,
                  ),
                  validator: (v) =>
                      _hasNonCompliance && (v == null || v.trim().isEmpty)
                          ? 'Requis en cas de non-conformité'
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConformityRow extends StatelessWidget {
  const _ConformityRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final void Function(bool?) onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeColor: Colors.green,
      checkboxShape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    );
  }
}
