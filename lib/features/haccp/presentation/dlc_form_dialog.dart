import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Valeur sentinelle du menu déroulant ingrédient signifiant "saisie libre" --
/// aucun ingrédient réel du Stock ne peut avoir cet id.
const dlcOtherIngredientId = -1;

/// Formulaire de vérification DLC, relié aux ingrédients/lots du Stock.
///
/// Utilisé à la fois depuis la session HACCP (ouverture/fermeture) et depuis
/// l'onglet Stock (gestion DLC indépendante d'une session). Retourne un
/// [Map] prêt à envoyer à l'API (create) ou null si annulé. Passer
/// [existing] pré-remplit le formulaire pour une modification.
class DlcFormDialog extends ConsumerStatefulWidget {
  const DlcFormDialog({super.key, this.existing});

  final HaccpDlcCheck? existing;

  @override
  ConsumerState<DlcFormDialog> createState() => _DlcFormDialogState();
}

class _DlcFormDialogState extends ConsumerState<DlcFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  int? _selectedIngredientId;
  int? _selectedBatchId;
  List<IngredientBatch> _batches = const [];
  bool _loadingBatches = false;
  late int _dlcLevel;
  late DateTime _dlcDate;
  late bool _isCompliant;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.ingredientName ?? '');
    _locationController = TextEditingController(text: e?.location ?? '');
    _selectedIngredientId =
        e == null ? null : (e.ingredientId ?? dlcOtherIngredientId);
    _selectedBatchId = e?.batchId;
    _dlcLevel = e?.dlcLevel ?? 1;
    _dlcDate = e?.dlcDate ?? DateTime.now();
    _isCompliant = e?.isCompliant ?? true;
    if (_selectedIngredientId != null &&
        _selectedIngredientId != dlcOtherIngredientId) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _loadBatches(_selectedIngredientId!));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dlcDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dlcDate = picked);
  }

  Future<void> _loadBatches(int ingredientId) async {
    setState(() => _loadingBatches = true);
    try {
      final batches =
          await ref.read(stockRepositoryProvider).listBatches(ingredientId);
      if (!mounted) return;
      setState(() {
        _batches = batches
            .where((b) => b.status != 'consumed' && b.status != 'discarded')
            .toList();
        _loadingBatches = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingBatches = false);
    }
  }

  Future<void> _onIngredientChanged(int? ingredientId) async {
    setState(() {
      _selectedIngredientId = ingredientId;
      _selectedBatchId = null;
      _batches = const [];
    });
    if (ingredientId == null || ingredientId == dlcOtherIngredientId) return;
    await _loadBatches(ingredientId);
  }

  void _onBatchChanged(int? batchId) {
    setState(() => _selectedBatchId = batchId);
    if (batchId == null) return;
    final batch = _batches.firstWhere((b) => b.id == batchId);
    final dlcDate = batch.effectiveExpiresAt ?? batch.expiresAt;
    if (dlcDate != null) setState(() => _dlcDate = dlcDate);
  }

  String _formatShortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String get _levelLabel {
    switch (_dlcLevel) {
      case 1:
        return 'Emballage produit brut';
      case 2:
        return 'Conservation frigo/congélateur';
      case 3:
        return 'Utilisation (table garniture)';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // DLC non conforme si la date est dépassée
    final isExpired = _dlcDate.isBefore(
      DateTime.now().subtract(const Duration(hours: 1)),
    );

    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Vérification DLC'
          : 'Modifier la vérification DLC'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Consumer(
                builder: (context, ref, _) {
                  final ingredientsAsync = ref.watch(ingredientsProvider);
                  return ingredientsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Erreur chargement ingrédients : $e'),
                    data: (ingredients) => DropdownButtonFormField<int>(
                      value: _selectedIngredientId,
                      decoration: const InputDecoration(
                        labelText: 'Ingrédient (Stock) *',
                      ),
                      items: [
                        ...ingredients.map(
                          (i) => DropdownMenuItem(
                            value: i.id,
                            child: Text(i.name),
                          ),
                        ),
                        const DropdownMenuItem(
                          value: dlcOtherIngredientId,
                          child: Text('Autre (saisie libre)'),
                        ),
                      ],
                      onChanged: _onIngredientChanged,
                      validator: (v) => v == null ? 'Champ obligatoire' : null,
                    ),
                  );
                },
              ),
              if (_selectedIngredientId == dlcOtherIngredientId) ...[
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom du produit *',
                  ),
                  validator: (v) =>
                      _selectedIngredientId == dlcOtherIngredientId &&
                              (v == null || v.isEmpty)
                          ? 'Champ obligatoire'
                          : null,
                ),
              ],
              if (_selectedIngredientId != null &&
                  _selectedIngredientId != dlcOtherIngredientId) ...[
                const SizedBox(height: AppSpacing.sm),
                if (_loadingBatches)
                  const LinearProgressIndicator()
                else if (_batches.isNotEmpty)
                  DropdownButtonFormField<int>(
                    value: _selectedBatchId,
                    decoration: const InputDecoration(
                      labelText: 'Lot (optionnel — pré-remplit la date DLC)',
                    ),
                    items: _batches
                        .map(
                          (b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(
                              'Lot #${b.id}'
                              '${(b.effectiveExpiresAt ?? b.expiresAt) != null ? ' — DLC ${_formatShortDate(b.effectiveExpiresAt ?? b.expiresAt!)}' : ''}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _onBatchChanged,
                  )
                else
                  const Text(
                    'Aucun lot actif pour cet ingrédient.',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
              ],
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<int>(
                value: _dlcLevel,
                decoration: const InputDecoration(labelText: 'Niveau DLC'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('DLC 1 — Emballage')),
                  DropdownMenuItem(
                      value: 2, child: Text('DLC 2 — Conservation')),
                  DropdownMenuItem(
                      value: 3, child: Text('DLC 3 — Utilisation')),
                ],
                onChanged: (v) => setState(() => _dlcLevel = v!),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(_levelLabel,
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
              const SizedBox(height: AppSpacing.sm),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date DLC',
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(
                    '${_dlcDate.day.toString().padLeft(2, '0')}/${_dlcDate.month.toString().padLeft(2, '0')}/${_dlcDate.year}',
                    style: TextStyle(
                      color: isExpired ? Colors.red : null,
                      fontWeight:
                          isExpired ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              if (isExpired) ...[
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  '⚠️ DLC dépassée — non-conformité',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Emplacement (optionnel)',
                  hintText: 'Ex: Frigo 2, Table garniture',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                dense: true,
                value: _isCompliant && !isExpired,
                onChanged:
                    isExpired ? null : (v) => setState(() => _isCompliant = v),
                title: const Text('Conforme', style: TextStyle(fontSize: 13)),
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
            if (!_formKey.currentState!.validate()) return;
            final isOther = _selectedIngredientId == dlcOtherIngredientId ||
                _selectedIngredientId == null;
            final ingredients = ref.read(ingredientsProvider).valueOrNull;
            final selectedIngredient = isOther
                ? null
                : ingredients?.firstWhere(
                    (i) => i.id == _selectedIngredientId,
                  );
            Navigator.pop(context, {
              'ingredient_id': isOther ? null : _selectedIngredientId,
              'batch_id': isOther ? null : _selectedBatchId,
              'ingredient_name': isOther
                  ? _nameController.text.trim()
                  : (selectedIngredient?.name ??
                      widget.existing?.ingredientName ??
                      ''),
              'dlc_level': _dlcLevel,
              'dlc_date':
                  '${_dlcDate.year}-${_dlcDate.month.toString().padLeft(2, '0')}-${_dlcDate.day.toString().padLeft(2, '0')}',
              'location': _locationController.text.trim().isNotEmpty
                  ? _locationController.text.trim()
                  : null,
              'is_compliant': _isCompliant && !isExpired,
            });
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
