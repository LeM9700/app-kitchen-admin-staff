import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      appBar: AppBar(
        title: const Text('Refroidissement rapide'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(haccpAllCoolingProvider);
              ref.invalidate(haccpActiveCoolingProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showStartForm(context, ref),
        icon: const Icon(Icons.thermostat),
        label: const Text('Démarrer suivi'),
      ),
      body: coolingAsync.when(
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
                onPressed: () => ref.invalidate(haccpAllCoolingProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (logs) {
          final active = logs.where((l) => l.isInProgress).toList();
          final done = logs.where((l) => !l.isInProgress).toList();

          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.ac_unit, size: 56, color: Colors.blue[100]),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Aucun suivi de refroidissement',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Objectif légal : < 10°C en moins de 2h',
                    style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(haccpAllCoolingProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, 100),
              children: [
                if (active.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.timer_outlined,
                    label: 'En cours (${active.length})',
                    color: Colors.orange,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ...active.map((l) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _CoolingCard(
                          log: l,
                          onComplete: () {
                            _showCompleteForm(context, ref, l);
                          },
                        ),
                      )),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (done.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.history,
                    label: 'Terminés (${done.length})',
                    color: Colors.grey,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ...done.map((l) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _CoolingCard(log: l),
                      )),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showStartForm(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StartCoolingForm(
        onSaved: () {
          ref.invalidate(haccpAllCoolingProvider);
          ref.invalidate(haccpActiveCoolingProvider);
        },
      ),
    );
  }

  void _showCompleteForm(
      BuildContext context, WidgetRef ref, HaccpCoolingLog log) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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

// ─── Carte refroidissement ────────────────────────────────────────────────────

class _CoolingCard extends StatelessWidget {
  const _CoolingCard({required this.log, this.onComplete});

  final HaccpCoolingLog log;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final isActive = log.isInProgress;
    final compliant = log.isCompliant;

    Color statusColor;
    if (isActive) {
      statusColor = Colors.orange;
    } else if (compliant) {
      statusColor = Colors.green;
    } else {
      statusColor = Colors.red;
    }

    final elapsed =
        isActive ? DateTime.now().difference(log.startedAt).inMinutes : null;
    final twoHoursWarning = elapsed != null && elapsed >= 90;

    return DsCard(
      borderRadius: 12,
      borderColor: statusColor.withValues(alpha: 0.3),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isActive
                    ? Icons.ac_unit
                    : (compliant ? Icons.check_circle : Icons.cancel),
                color: statusColor,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  log.productName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              if (isActive && elapsed != null) ...[
                if (twoHoursWarning)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '⚠️ ${elapsed}min',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.red,
                          fontWeight: FontWeight.w600),
                    ),
                  )
                else
                  Text(
                    '${elapsed}min',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              _TempBadge(label: 'T° init.', temp: log.tempInitial, ok: true),
              if (!isActive && log.tempFinal != null) ...[
                const SizedBox(width: AppSpacing.xs),
                const Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
                const SizedBox(width: AppSpacing.xs),
                _TempBadge(
                  label: 'T° finale',
                  temp: log.tempFinal!,
                  ok: log.tempFinal! <= 10,
                ),
              ],
              if (!isActive && log.durationMinutes != null) ...[
                const Spacer(),
                Text(
                  '${log.durationMinutes}min',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ],
          ),
          if (twoHoursWarning) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, size: 13, color: Colors.red),
                  SizedBox(width: 4),
                  Text(
                    'Objectif 2h bientôt dépassé — enregistrez la T° finale',
                    style: TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ],
              ),
            ),
          ],
          if (!compliant && log.correctiveAction != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '🔧 ${log.correctiveAction}',
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
          if (isActive && onComplete != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onComplete,
                icon: const Icon(Icons.thermostat, size: 16),
                label: const Text('Enregistrer T° finale'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TempBadge extends StatelessWidget {
  const _TempBadge({required this.label, required this.temp, required this.ok});

  final String label;
  final double temp;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ok ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: ok
                ? Colors.green.withOpacity(0.3)
                : Colors.red.withOpacity(0.3)),
      ),
      child: Text(
        '$label: ${temp.toStringAsFixed(1)}°C',
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ok ? Colors.green[700] : Colors.red[700]),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13, color: color)),
      ],
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
      await ref.read(haccpRepositoryProvider).startCooling({
        'product_name': _productCtrl.text.trim(),
        'temp_initial':
            double.parse(_tempCtrl.text.trim().replaceAll(',', '.')),
        'started_at': DateTime.now().toIso8601String(),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Démarrer un suivi',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Objectif légal : atteindre ≤ 10°C en moins de 2h',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _productCtrl,
              decoration: const InputDecoration(
                  labelText: 'Produit / préparation *',
                  border: OutlineInputBorder()),
              validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _tempCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Température initiale (°C) *',
                border: OutlineInputBorder(),
                suffixText: '°C',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Requis';
                if (double.tryParse(v.replaceAll(',', '.')) == null) {
                  return 'Valeur numérique invalide';
                }
                return null;
              },
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
                    : const Icon(Icons.play_arrow),
                label: const Text('Démarrer'),
              ),
            ),
          ],
        ),
      ),
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

  bool get _nonCompliant => _tempValue != null && _tempValue! > 10;

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
      await ref.read(haccpRepositoryProvider).completeCooling(
            widget.log.id,
            tempFinal: _tempValue!,
            correctiveAction: _correctiveCtrl.text.trim().isNotEmpty
                ? _correctiveCtrl.text.trim()
                : null,
          );
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enregistrer T° finale',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${widget.log.productName} — T° init. ${widget.log.tempInitial.toStringAsFixed(1)}°C',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _tempCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Température finale (°C) *',
                border: const OutlineInputBorder(),
                suffixText: '°C',
                // feedback temps réel
                helperText: _tempValue == null
                    ? null
                    : _nonCompliant
                        ? '⚠️ NC — objectif ≤ 10°C non atteint'
                        : '✓ Conforme',
                helperStyle: TextStyle(
                  color: _nonCompliant ? Colors.red : Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Requis';
                if (double.tryParse(v.replaceAll(',', '.')) == null) {
                  return 'Valeur numérique invalide';
                }
                return null;
              },
            ),
            if (_nonCompliant) ...[
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _correctiveCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Action corrective *',
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
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('Valider'),
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
