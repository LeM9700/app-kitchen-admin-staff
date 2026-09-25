import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/core/widgets/live_countdown.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/components/forms/pill_filter_bar.dart';
import 'package:app_admin_staff/design_system/theme/staggered_entrance.dart';
import 'package:app_admin_staff/design_system/tokens/app_breakpoints.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/stock/application/stock_view_state.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ingredients = ref.watch(ingredientsProvider);
    final alerts = ref.watch(stockAlertsProvider);
    final movements = ref.watch(stockMovementsProvider);
    final levelFilter = ref.watch(stockLevelFilterProvider);
    final permissions = ref.watch(currentPermissionSetProvider);
    final currentEstablishment = ref.watch(currentEstablishmentProvider);
    final canReview = permissions.hasRole('admin');
    final canWriteStock = permissions.can(AppPermission.stockWrite);
    final canAdjustStock = permissions.can(AppPermission.stockAdjustmentCreate);
    final requests = canReview
        ? ref.watch(adjustmentRequestsProvider)
        : const AsyncValue<List<StockAdjustmentRequest>>.data([]);

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ColoredBox(
        color: const Color(0xFFE8E2D8),
        child: ListView(
          padding: EdgeInsets.all(
            AppBreakpoints.isMobile(context) ? AppSpacing.md : AppSpacing.xxl,
          ),
          children: [
            _StockHeader(
              establishmentName:
                  currentEstablishment.valueOrNull?.name ?? 'Etablissement',
              canCreateIngredient: canWriteStock,
              canManageRecipes: canWriteStock,
              onRefresh: () => _refresh(ref),
              onCreateIngredient: () => _ingredientDialog(context, ref),
              onRecipe: () => _recipeDialog(context, ref),
              onManageDlc: () => context.push('/stock/dlc'),
            ),
            const SizedBox(height: AppSpacing.md),
            _StockStatsRow(
              ingredients: ingredients.valueOrNull,
              alerts: alerts.valueOrNull,
              requests: requests.valueOrNull,
              movements: movements.valueOrNull,
              onFilter: (filter) {
                ref.read(stockLevelFilterProvider.notifier).state = filter;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _StockToolbar(
              controller: _searchController,
              selected: levelFilter,
              onSearchChanged: (value) {
                ref.read(stockSearchProvider.notifier).state = value;
              },
              onFilterChanged: (value) {
                ref.read(stockLevelFilterProvider.notifier).state = value;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1180;
                final effectiveIngredients =
                    _filterIngredients(ingredients, levelFilter);
                final table = _IngredientsPanel(
                  ingredients: effectiveIngredients,
                  canEdit: canWriteStock,
                  canSupply: canWriteStock,
                  canAdjust: canAdjustStock,
                  compactCards: constraints.maxWidth < 760,
                  onEdit: (ingredient) => _ingredientDialog(
                    context,
                    ref,
                    ingredient: ingredient,
                  ),
                  onSupply: (ingredient) => _supply(context, ref, ingredient),
                  onAdjust: (ingredient) => _adjust(context, ref, ingredient),
                  onBatches: (ingredient) => _batches(context, ref, ingredient),
                );
                final side = Column(
                  children: [
                    _StockHealthPanel(
                      alerts: alerts,
                      ingredients: ingredients.valueOrNull,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _AdjustmentRequestsPanel(
                      requests: requests,
                      canReview: canReview,
                      onReview: (request, approve) => _review(
                        context,
                        ref,
                        request.id,
                        approve: approve,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _StockMovementsPanel(
                      movements: movements,
                      ingredients: ingredients.valueOrNull,
                    ),
                  ],
                );

                if (!wide) {
                  return Column(
                    children: [
                      table,
                      const SizedBox(height: AppSpacing.md),
                      side,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: table),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(width: 390, child: side),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  AsyncValue<List<Ingredient>> _filterIngredients(
    AsyncValue<List<Ingredient>> ingredients,
    StockLevelFilter filter,
  ) {
    return ingredients.whenData(
      (items) => items
          .where((ingredient) => matchesStockFilter(ingredient, filter))
          .toList(),
    );
  }

  Future<void> _supply(
    BuildContext context,
    WidgetRef ref,
    Ingredient ingredient,
  ) async {
    final controller = TextEditingController();
    final quantity = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _SupplySheet(
        ingredient: ingredient,
        controller: controller,
      ),
    );
    controller.dispose();
    if (quantity == null) {
      return;
    }
    try {
      await ref.read(stockRepositoryProvider).supply(
            ingredientId: ingredient.id,
            quantity: quantity,
          );
      ref.invalidate(ingredientsProvider);
      ref.invalidate(stockAlertsProvider);
      ref.invalidate(stockMovementsProvider);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(ingredientsProvider);
    ref.invalidate(stockAlertsProvider);
    ref.invalidate(stockMovementsProvider);
    ref.invalidate(adjustmentRequestsProvider);
    await Future.wait([
      ref.read(ingredientsProvider.future),
      ref.read(stockAlertsProvider.future),
      ref.read(stockMovementsProvider.future),
      ref.read(adjustmentRequestsProvider.future),
    ]);
  }

  Future<void> _ingredientDialog(
    BuildContext context,
    WidgetRef ref, {
    Ingredient? ingredient,
  }) async {
    final name = TextEditingController(text: ingredient?.name ?? '');
    final unit = TextEditingController(text: ingredient?.unit ?? '');
    final qty =
        TextEditingController(text: ingredient?.currentQty.toString() ?? '0');
    final threshold = TextEditingController(
      text: ingredient?.alertThreshold.toString() ?? '0',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          ingredient == null ? 'Nouvel ingredient' : 'Modifier ingredient',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: unit,
              decoration: const InputDecoration(labelText: 'Unite'),
            ),
            const SizedBox(height: 12),
            if (ingredient == null)
              TextField(
                controller: qty,
                decoration: const InputDecoration(labelText: 'Stock initial'),
                keyboardType: TextInputType.number,
              ),
            if (ingredient == null) const SizedBox(height: 12),
            TextField(
              controller: threshold,
              decoration: const InputDecoration(labelText: 'Seuil alerte'),
              keyboardType: TextInputType.number,
            ),
          ],
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
    if (confirmed != true) {
      return;
    }
    try {
      final repository = ref.read(stockRepositoryProvider);
      if (ingredient == null) {
        await repository.createIngredient(
          name: name.text.trim(),
          unit: unit.text.trim(),
          currentQty: _parseDouble(qty.text) ?? 0,
          alertThreshold: _parseDouble(threshold.text) ?? 0,
        );
      } else {
        await repository.patchIngredient(
          ingredientId: ingredient.id,
          name: name.text.trim(),
          unit: unit.text.trim(),
          alertThreshold: _parseDouble(threshold.text) ?? 0,
        );
      }
      ref.invalidate(ingredientsProvider);
      ref.invalidate(stockAlertsProvider);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _recipeDialog(BuildContext context, WidgetRef ref) async {
    var targetType = 'product';
    final targetId = TextEditingController();
    final ingredientId = TextEditingController();
    final quantity = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Recette stock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'product', label: Text('Produit')),
                  ButtonSegment(value: 'variant', label: Text('Variante')),
                  ButtonSegment(value: 'extra', label: Text('Extra')),
                ],
                selected: {targetType},
                onSelectionChanged: (value) {
                  setState(() => targetType = value.first);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: targetId,
                decoration: InputDecoration(labelText: '$targetType ID'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ingredientId,
                decoration: const InputDecoration(labelText: 'Ingredient ID'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantity,
                decoration:
                    const InputDecoration(labelText: 'Quantite consommee'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    final parsedTargetId = int.tryParse(targetId.text.trim());
    final parsedIngredientId = int.tryParse(ingredientId.text.trim());
    final parsedQuantity = _parseDouble(quantity.text);
    if (parsedTargetId == null ||
        parsedIngredientId == null ||
        parsedQuantity == null) {
      if (context.mounted) {
        _snack(context, 'Saisie invalide');
      }
      return;
    }
    try {
      final repository = ref.read(stockRepositoryProvider);
      if (targetType == 'product') {
        await repository.createProductRecipe(
          productId: parsedTargetId,
          ingredientId: parsedIngredientId,
          quantity: parsedQuantity,
        );
      } else if (targetType == 'variant') {
        await repository.createVariantRecipe(
          variantId: parsedTargetId,
          ingredientId: parsedIngredientId,
          quantity: parsedQuantity,
        );
      } else {
        await repository.createExtraRecipe(
          extraId: parsedTargetId,
          ingredientId: parsedIngredientId,
          quantity: parsedQuantity,
        );
      }
      if (context.mounted) {
        _snack(context, 'Recette enregistree');
      }
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _adjust(
    BuildContext context,
    WidgetRef ref,
    Ingredient ingredient,
  ) async {
    final draft = await showModalBottomSheet<_AdjustmentDraft>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _AdjustmentSheet(
        ingredient: ingredient,
      ),
    );
    if (draft == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    try {
      await ref.read(stockRepositoryProvider).createAdjustmentRequest(
            ingredientId: ingredient.id,
            quantityDelta: draft.quantityDelta,
            reason: draft.reason,
            note: draft.note,
          );
      ref.invalidate(adjustmentRequestsProvider);
      ref.invalidate(stockMovementsProvider);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _batches(
    BuildContext context,
    WidgetRef ref,
    Ingredient ingredient,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: _BatchesSheet(ingredient: ingredient),
        );
      },
    );
    ref.invalidate(ingredientsProvider);
    ref.invalidate(stockAlertsProvider);
    ref.invalidate(stockMovementsProvider);
  }

  Future<void> _review(
    BuildContext context,
    WidgetRef ref,
    int requestId, {
    required bool approve,
  }) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approuver' : 'Rejeter'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(labelText: 'Note'),
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
    if (confirmed != true) {
      return;
    }
    try {
      final repository = ref.read(stockRepositoryProvider);
      if (approve) {
        await repository.approveAdjustment(
          requestId,
          note: noteController.text,
        );
      } else {
        await repository.rejectAdjustment(requestId, note: noteController.text);
      }
      ref.invalidate(adjustmentRequestsProvider);
      ref.invalidate(ingredientsProvider);
      ref.invalidate(stockAlertsProvider);
      ref.invalidate(stockMovementsProvider);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  double? _parseDouble(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SupplySheet extends StatefulWidget {
  const _SupplySheet({
    required this.ingredient,
    required this.controller,
  });

  final Ingredient ingredient;
  final TextEditingController controller;

  @override
  State<_SupplySheet> createState() => _SupplySheetState();
}

class _SupplySheetState extends State<_SupplySheet> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Approvisionner',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.ingredient.name,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: widget.controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Quantite ajoutee (${widget.ingredient.unit})',
              prefixIcon: const Icon(Icons.scale_outlined),
              errorText: _error,
            ),
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter au stock'),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final value =
        double.tryParse(widget.controller.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) {
      setState(() {
        _error = 'Saisir une quantite positive.';
      });
      return;
    }
    Navigator.pop(context, value);
  }
}

class _AdjustmentDraft {
  const _AdjustmentDraft({
    required this.quantityDelta,
    required this.reason,
    this.note,
  });

  final double quantityDelta;
  final String reason;
  final String? note;
}

class _AdjustmentSheet extends StatefulWidget {
  const _AdjustmentSheet({required this.ingredient});

  final Ingredient ingredient;

  @override
  State<_AdjustmentSheet> createState() => _AdjustmentSheetState();
}

class _AdjustmentSheetState extends State<_AdjustmentSheet> {
  final _deltaController = TextEditingController();
  final _noteController = TextEditingController();
  String _reason = 'inventory';
  String? _error;

  @override
  void dispose() {
    _deltaController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Demande d ajustement',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${widget.ingredient.name} - stock actuel ${formatStockQty(widget.ingredient.currentQty)} ${widget.ingredient.unit}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'inventory', label: Text('Inventaire')),
              ButtonSegment(value: 'loss', label: Text('Perte')),
              ButtonSegment(value: 'waste', label: Text('Jete')),
              ButtonSegment(value: 'correction', label: Text('Correction')),
            ],
            selected: {_reason},
            onSelectionChanged: (values) {
              setState(() {
                _reason = values.first;
              });
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _deltaController,
            decoration: InputDecoration(
              labelText: 'Delta (${widget.ingredient.unit})',
              helperText: 'Exemple : -2 pour retirer, 3 pour ajouter',
              prefixIcon: const Icon(Icons.swap_vert_outlined),
              errorText: _error,
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Note',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.send_outlined),
              label: const Text('Envoyer la demande'),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final value =
        double.tryParse(_deltaController.text.trim().replaceAll(',', '.'));
    if (value == null || value == 0) {
      setState(() {
        _error = 'Saisir un delta non nul.';
      });
      return;
    }
    Navigator.pop(
      context,
      _AdjustmentDraft(
        quantityDelta: value,
        reason: _reason,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      ),
    );
  }
}

class _StockHeader extends StatelessWidget {
  const _StockHeader({
    required this.establishmentName,
    required this.canCreateIngredient,
    required this.canManageRecipes,
    required this.onRefresh,
    required this.onCreateIngredient,
    required this.onRecipe,
    required this.onManageDlc,
  });

  final String establishmentName;
  final bool canCreateIngredient;
  final bool canManageRecipes;
  final VoidCallback onRefresh;
  final VoidCallback onCreateIngredient;
  final VoidCallback onRecipe;
  final VoidCallback onManageDlc;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      backgroundColor: const Color(0xFFF8F4EC),
      borderColor: const Color(0xFFD8D0C3),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stock',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _SoftChip(
                      icon: Icons.storefront_outlined,
                      label: establishmentName,
                    ),
                    const _SoftChip(
                      icon: Icons.inventory_2_outlined,
                      label: 'Controle operationnel',
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<_StockHeaderAction>(
            tooltip: 'Actions stock',
            onSelected: (value) {
              switch (value) {
                case _StockHeaderAction.refresh:
                  onRefresh();
                case _StockHeaderAction.createIngredient:
                  onCreateIngredient();
                case _StockHeaderAction.recipe:
                  onRecipe();
                case _StockHeaderAction.dlc:
                  onManageDlc();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _StockHeaderAction.refresh,
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('Rafraichir'),
                ),
              ),
              if (canCreateIngredient)
                const PopupMenuItem(
                  value: _StockHeaderAction.createIngredient,
                  child: ListTile(
                    leading: Icon(Icons.add),
                    title: Text('Nouvel ingredient'),
                  ),
                ),
              if (canManageRecipes)
                const PopupMenuItem(
                  value: _StockHeaderAction.recipe,
                  child: ListTile(
                    leading: Icon(Icons.menu_book_outlined),
                    title: Text('Recette stock'),
                  ),
                ),
              const PopupMenuItem(
                value: _StockHeaderAction.dlc,
                child: ListTile(
                  leading: Icon(Icons.event_available_outlined),
                  title: Text('Acces DLC'),
                ),
              ),
            ],
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.adminSidebar,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.more_horiz, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StockHeaderAction {
  refresh,
  createIngredient,
  recipe,
  dlc,
}

class _SoftChip extends StatelessWidget {
  const _SoftChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFE8E2D8),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: const Color(0xFFD8D0C3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockStatsRow extends StatelessWidget {
  const _StockStatsRow({
    required this.ingredients,
    required this.alerts,
    required this.requests,
    required this.movements,
    required this.onFilter,
  });

  final List<Ingredient>? ingredients;
  final List<Ingredient>? alerts;
  final List<StockAdjustmentRequest>? requests;
  final List<StockMovement>? movements;
  final ValueChanged<StockLevelFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final pending =
        requests?.where((request) => request.status == 'pending').length;
    final ruptureCount = ingredients
        ?.where(
          (ingredient) => stockStatusOf(ingredient) == StockDerivedStatus.out,
        )
        .length;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _CompactMetric(
          value: alerts?.length.toString() ?? '-',
          label: 'stocks faibles',
          icon: Icons.warning_amber_outlined,
          color:
              (alerts?.isEmpty ?? true) ? AppColors.success : AppColors.warning,
          onTap: () => onFilter(StockLevelFilter.low),
        ),
        _CompactMetric(
          value: ruptureCount?.toString() ?? '-',
          label: 'ruptures',
          icon: Icons.error_outline,
          color:
              (ruptureCount ?? 0) == 0 ? AppColors.success : AppColors.danger,
          onTap: () => onFilter(StockLevelFilter.out),
        ),
        _CompactMetric(
          value: ingredients?.length.toString() ?? '-',
          label: 'ingredients',
          icon: Icons.warehouse_outlined,
          color: AppColors.infoAlt,
          onTap: () => onFilter(StockLevelFilter.all),
        ),
        _CompactMetric(
          value: pending?.toString() ?? '-',
          label: 'ajustements',
          icon: Icons.tune_outlined,
          color: (pending ?? 0) == 0 ? AppColors.success : AppColors.warning,
        ),
        _CompactMetric(
          value: movements?.length.toString() ?? '-',
          label: 'mouvements',
          icon: Icons.history_outlined,
          color: AppColors.accent,
        ),
      ],
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: DsCard(
        onTap: onTap,
        backgroundColor: const Color(0xFFF8F4EC),
        borderColor: const Color(0xFFD8D0C3),
        borderRadius: AppRadius.md,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockToolbar extends StatelessWidget {
  const _StockToolbar({
    required this.controller,
    required this.selected,
    required this.onSearchChanged,
    required this.onFilterChanged,
  });

  final TextEditingController controller;
  final StockLevelFilter selected;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<StockLevelFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 340,
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Recherche ingredient',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          PillFilterBar<StockLevelFilter>(
            selected: selected,
            onSelected: onFilterChanged,
            options: const [
              PillFilterOption<StockLevelFilter>(
                value: StockLevelFilter.all,
                label: 'Tous',
                icon: Icons.inventory_2_outlined,
              ),
              PillFilterOption<StockLevelFilter>(
                value: StockLevelFilter.low,
                label: 'Sous seuil',
                icon: Icons.warning_amber_outlined,
              ),
              PillFilterOption<StockLevelFilter>(
                value: StockLevelFilter.out,
                label: 'Rupture',
                icon: Icons.error_outline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IngredientsPanel extends StatelessWidget {
  const _IngredientsPanel({
    required this.ingredients,
    required this.canEdit,
    required this.canSupply,
    required this.canAdjust,
    required this.compactCards,
    required this.onEdit,
    required this.onSupply,
    required this.onAdjust,
    required this.onBatches,
  });

  final AsyncValue<List<Ingredient>> ingredients;
  final bool canEdit;
  final bool canSupply;
  final bool canAdjust;
  final bool compactCards;
  final ValueChanged<Ingredient> onEdit;
  final ValueChanged<Ingredient> onSupply;
  final ValueChanged<Ingredient> onAdjust;
  final ValueChanged<Ingredient> onBatches;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: EdgeInsets.zero,
      child: ingredients.when(
        data: (items) {
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: EmptyState(
                icon: Icons.warehouse_outlined,
                title: 'Aucun ingredient',
                subtitle: 'Aucun stock ne correspond aux filtres actifs.',
              ),
            );
          }
          if (compactCards) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                children: [
                  for (final (index, ingredient) in items.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _IngredientCard(
                        ingredient: ingredient,
                        canEdit: canEdit,
                        canSupply: canSupply,
                        canAdjust: canAdjust,
                        onEdit: onEdit,
                        onSupply: onSupply,
                        onAdjust: onAdjust,
                        onBatches: onBatches,
                      ).staggeredEntrance(index),
                    ),
                ],
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  constraints.maxWidth < 920 ? 920.0 : constraints.maxWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      const _IngredientHeader(),
                      const Divider(height: 1),
                      for (final (index, ingredient) in items.indexed) ...[
                        _IngredientRow(
                          ingredient: ingredient,
                          canEdit: canEdit,
                          canSupply: canSupply,
                          canAdjust: canAdjust,
                          onEdit: onEdit,
                          onSupply: onSupply,
                          onAdjust: onAdjust,
                          onBatches: onBatches,
                        ).staggeredEntrance(index),
                        const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: LinearProgressIndicator(),
        ),
        error: (error, stackTrace) => const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: EmptyState(
            icon: Icons.error_outline,
            title: 'Stock indisponible',
            subtitle: 'Les ingredients ne peuvent pas etre charges.',
          ),
        ),
      ),
    );
  }
}

class _IngredientHeader extends StatelessWidget {
  const _IngredientHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: const Row(
        children: [
          _StockTableLabel('Ingredient', width: 260),
          _StockTableLabel('Stock actuel', width: 130),
          _StockTableLabel('Niveau seuil', width: 170),
          _StockTableLabel('Etat', width: 120),
          Expanded(child: _StockTableLabel('Actions')),
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.ingredient,
    required this.canEdit,
    required this.canSupply,
    required this.canAdjust,
    required this.onEdit,
    required this.onSupply,
    required this.onAdjust,
    required this.onBatches,
  });

  final Ingredient ingredient;
  final bool canEdit;
  final bool canSupply;
  final bool canAdjust;
  final ValueChanged<Ingredient> onEdit;
  final ValueChanged<Ingredient> onSupply;
  final ValueChanged<Ingredient> onAdjust;
  final ValueChanged<Ingredient> onBatches;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: Row(
              children: [
                Icon(
                  stockStatusOf(ingredient) == StockDerivedStatus.out
                      ? Icons.error_outline
                      : stockStatusOf(ingredient) == StockDerivedStatus.low
                          ? Icons.warning_amber_outlined
                          : Icons.inventory_outlined,
                  color: _stockColor(ingredient),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    ingredient.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 130,
            child: Text(
              '${formatStockQty(ingredient.currentQty)} ${ingredient.unit}',
            ),
          ),
          SizedBox(
            width: 170,
            child: _StockLevelIndicator(ingredient: ingredient),
          ),
          SizedBox(
            width: 120,
            child: _StockStatusBadge(ingredient: ingredient),
          ),
          Expanded(
            child: _IngredientActions(
              ingredient: ingredient,
              canEdit: canEdit,
              canSupply: canSupply,
              canAdjust: canAdjust,
              onEdit: onEdit,
              onSupply: onSupply,
              onAdjust: onAdjust,
              onBatches: onBatches,
            ),
          ),
        ],
      ),
    );
  }
}

class _IngredientCard extends StatelessWidget {
  const _IngredientCard({
    required this.ingredient,
    required this.canEdit,
    required this.canSupply,
    required this.canAdjust,
    required this.onEdit,
    required this.onSupply,
    required this.onAdjust,
    required this.onBatches,
  });

  final Ingredient ingredient;
  final bool canEdit;
  final bool canSupply;
  final bool canAdjust;
  final ValueChanged<Ingredient> onEdit;
  final ValueChanged<Ingredient> onSupply;
  final ValueChanged<Ingredient> onAdjust;
  final ValueChanged<Ingredient> onBatches;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      backgroundColor: const Color(0xFFFCF8F0),
      borderColor: const Color(0xFFD8D0C3),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: _stockColor(ingredient)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  ingredient.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              _StockStatusBadge(ingredient: ingredient),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${formatStockQty(ingredient.currentQty)} ${ingredient.unit}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _StockLevelIndicator(ingredient: ingredient),
          const SizedBox(height: AppSpacing.md),
          _IngredientActions(
            ingredient: ingredient,
            canEdit: canEdit,
            canSupply: canSupply,
            canAdjust: canAdjust,
            onEdit: onEdit,
            onSupply: onSupply,
            onAdjust: onAdjust,
            onBatches: onBatches,
          ),
        ],
      ),
    );
  }
}

class _IngredientActions extends StatelessWidget {
  const _IngredientActions({
    required this.ingredient,
    required this.canEdit,
    required this.canSupply,
    required this.canAdjust,
    required this.onEdit,
    required this.onSupply,
    required this.onAdjust,
    required this.onBatches,
  });

  final Ingredient ingredient;
  final bool canEdit;
  final bool canSupply;
  final bool canAdjust;
  final ValueChanged<Ingredient> onEdit;
  final ValueChanged<Ingredient> onSupply;
  final ValueChanged<Ingredient> onAdjust;
  final ValueChanged<Ingredient> onBatches;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      alignment: WrapAlignment.end,
      children: [
        if (canSupply)
          FilledButton.icon(
            onPressed: () => onSupply(ingredient),
            icon: const Icon(Icons.add),
            label: const Text('Appro'),
          ),
        OutlinedButton.icon(
          onPressed: () => onBatches(ingredient),
          icon: const Icon(Icons.event_note_outlined),
          label: const Text('Lots'),
        ),
        if (canAdjust || canEdit)
          PopupMenuButton<_IngredientAction>(
            tooltip: 'Actions ingredient',
            onSelected: (action) {
              switch (action) {
                case _IngredientAction.adjust:
                  onAdjust(ingredient);
                case _IngredientAction.edit:
                  onEdit(ingredient);
              }
            },
            itemBuilder: (context) => [
              if (canAdjust)
                const PopupMenuItem(
                  value: _IngredientAction.adjust,
                  child: ListTile(
                    leading: Icon(Icons.tune_outlined),
                    title: Text('Demander un ajustement'),
                  ),
                ),
              if (canEdit)
                const PopupMenuItem(
                  value: _IngredientAction.edit,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Modifier'),
                  ),
                ),
            ],
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E2D8),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: const Color(0xFFD8D0C3)),
              ),
              child: const Icon(Icons.more_horiz),
            ),
          ),
      ],
    );
  }
}

enum _IngredientAction { adjust, edit }

class _StockLevelIndicator extends StatelessWidget {
  const _StockLevelIndicator({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    final ratio = stockThresholdRatio(ingredient);
    final color = _stockColor(ingredient);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: ratio.clamp(0, 1),
            minHeight: 8,
            backgroundColor: const Color(0xFFE8E2D8),
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Seuil ${formatStockQty(ingredient.alertThreshold)} ${ingredient.unit}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _StockStatusBadge extends StatelessWidget {
  const _StockStatusBadge({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    final status = stockStatusOf(ingredient);
    return switch (status) {
      StockDerivedStatus.out => const StatusBadge(
          label: 'Rupture',
          tone: StatusTone.danger,
          compact: true,
          icon: Icons.error_outline,
        ),
      StockDerivedStatus.low => const StatusBadge(
          label: 'Sous seuil',
          tone: StatusTone.warning,
          compact: true,
          icon: Icons.warning_amber_outlined,
        ),
      StockDerivedStatus.normal => const StatusBadge(
          label: 'OK',
          tone: StatusTone.success,
          compact: true,
          icon: Icons.check_circle_outline,
        ),
    };
  }
}

Color _stockColor(Ingredient ingredient) {
  return switch (stockStatusOf(ingredient)) {
    StockDerivedStatus.out => AppColors.danger,
    StockDerivedStatus.low => AppColors.warning,
    StockDerivedStatus.normal => AppColors.success,
  };
}

class _StockHealthPanel extends StatelessWidget {
  const _StockHealthPanel({
    required this.alerts,
    required this.ingredients,
  });

  final AsyncValue<List<Ingredient>> alerts;
  final List<Ingredient>? ingredients;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sante stock', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          alerts.when(
            data: (items) {
              final outItems = (ingredients ?? const <Ingredient>[])
                  .where(
                    (ingredient) =>
                        stockStatusOf(ingredient) == StockDerivedStatus.out,
                  )
                  .toList();
              final urgent = [
                ...outItems,
                ...items.where(
                  (item) => stockStatusOf(item) != StockDerivedStatus.out,
                ),
              ];
              if (urgent.isEmpty) {
                return const StatusBadge(
                  label: 'Tous au-dessus du seuil',
                  tone: StatusTone.success,
                  icon: Icons.check_circle_outline,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusBadge(
                    label: '${urgent.length} action(s) stock',
                    tone: StatusTone.danger,
                    icon: Icons.warning_amber_outlined,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final item in urgent.take(5))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        stockStatusOf(item) == StockDerivedStatus.out
                            ? Icons.error_outline
                            : Icons.warning_amber_outlined,
                        color: _stockColor(item),
                      ),
                      title: Text(item.name),
                      subtitle: Text(
                        '${formatStockQty(item.currentQty)} ${item.unit} / seuil ${formatStockQty(item.alertThreshold)}',
                      ),
                    ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => const Text(
              'Alertes indisponibles pour le moment.',
            ),
          ),
          if (ingredients != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${ingredients!.length} ingredient(s) suivis',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdjustmentRequestsPanel extends StatelessWidget {
  const _AdjustmentRequestsPanel({
    required this.requests,
    required this.canReview,
    required this.onReview,
  });

  final AsyncValue<List<StockAdjustmentRequest>> requests;
  final bool canReview;
  final void Function(StockAdjustmentRequest request, bool approve) onReview;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ajustements',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          requests.when(
            data: (items) {
              if (items.isEmpty) {
                return const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('Aucune demande'),
                );
              }
              return Column(
                children: [
                  for (final request in items.take(8))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCF8F0),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: const Color(0xFFD8D0C3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  request.isLargeAdjustment
                                      ? Icons.priority_high_outlined
                                      : Icons.tune_outlined,
                                  color: request.isLargeAdjustment
                                      ? AppColors.danger
                                      : AppColors.infoAlt,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    'Ingredient #${request.ingredientId}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                ),
                                StatusBadge(
                                  label: request.status,
                                  tone: request.status == 'pending'
                                      ? StatusTone.warning
                                      : StatusTone.neutral,
                                  compact: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${formatSignedQty(request.quantityDelta)} - ${request.reason}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if ((request.note ?? '').isNotEmpty)
                              Text(
                                request.note!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                              ),
                            if (canReview && request.status == 'pending') ...[
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => onReview(request, false),
                                      icon: const Icon(Icons.close),
                                      label: const Text('Rejeter'),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => onReview(request, true),
                                      icon: const Icon(Icons.check),
                                      label: const Text('Valider'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => const Text(
              'Demandes indisponibles pour le moment.',
            ),
          ),
        ],
      ),
    );
  }
}

class _StockMovementsPanel extends StatelessWidget {
  const _StockMovementsPanel({
    required this.movements,
    required this.ingredients,
  });

  final AsyncValue<List<StockMovement>> movements;
  final List<Ingredient>? ingredients;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mouvements recents',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          movements.when(
            data: (items) {
              if (items.isEmpty) {
                return const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.history_outlined),
                  title: Text('Aucun mouvement'),
                );
              }
              final names = {
                for (final ingredient in ingredients ?? const <Ingredient>[])
                  ingredient.id: ingredient.name,
              };
              return Column(
                children: [
                  for (final movement in items.take(8))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        movement.quantityDelta >= 0
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline,
                        color: movement.quantityDelta >= 0
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      title: Text(
                        '${names[movement.ingredientId] ?? 'Ingredient #${movement.ingredientId}'} - ${formatSignedQty(movement.quantityDelta)}',
                      ),
                      subtitle: Text(movement.reason),
                      trailing: Text(formatDateTime(movement.createdAt)),
                    ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => const Text(
              'Mouvements indisponibles pour le moment.',
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTableLabel extends StatelessWidget {
  const _StockTableLabel(this.label, {this.width});

  final String label;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
    );
    if (width == null) {
      return text;
    }
    return SizedBox(width: width, child: text);
  }
}

class _BatchesSheet extends ConsumerStatefulWidget {
  const _BatchesSheet({required this.ingredient});

  final Ingredient ingredient;

  @override
  ConsumerState<_BatchesSheet> createState() => _BatchesSheetState();
}

class _BatchesSheetState extends ConsumerState<_BatchesSheet> {
  late Future<List<IngredientBatch>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future =
        ref.read(stockRepositoryProvider).listBatches(widget.ingredient.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<IngredientBatch>>(
      future: _future,
      builder: (context, snapshot) {
        final batches = snapshot.data ?? const <IngredientBatch>[];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lots et DLC',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(
                        widget.ingredient.name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Nouveau lot',
                  onPressed: _createBatch,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator()
            else if (snapshot.hasError)
              const EmptyState(
                icon: Icons.error_outline,
                title: 'Lots indisponibles',
                subtitle: 'Impossible de charger les lots de cet ingredient.',
              )
            else if (batches.isEmpty)
              const ListTile(
                leading: Icon(Icons.event_note_outlined),
                title: Text('Aucun lot'),
              )
            else
              ...batches.map((batch) {
                final expiresAt = batch.effectiveExpiresAt ?? batch.expiresAt;
                final risk = hasDlcRisk(batch, DateTime.now());
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF8F0),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: const Color(0xFFD8D0C3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              risk
                                  ? Icons.timer_outlined
                                  : Icons.inventory_2_outlined,
                              color:
                                  risk ? AppColors.warning : AppColors.infoAlt,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                '${formatStockQty(batch.quantity)} ${widget.ingredient.unit}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            StatusBadge(
                              label: batch.status,
                              tone: batch.status == 'sealed'
                                  ? StatusTone.success
                                  : StatusTone.neutral,
                              compact: true,
                            ),
                          ],
                        ),
                        if (expiresAt != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'DLC',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              LiveCountdown(target: expiresAt),
                            ],
                          ),
                        ],
                        if (batch.openedAt != null)
                          Text(
                            'Ouvert ${formatDateTime(batch.openedAt!)}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                          ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: batch.status == 'sealed'
                                    ? () => _mutate(
                                          () => ref
                                              .read(stockRepositoryProvider)
                                              .openBatch(batch.id),
                                        )
                                    : null,
                                icon: const Icon(Icons.lock_open_outlined),
                                label: const Text('Ouvrir'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _discard(batch.id),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Jeter'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Future<void> _createBatch() async {
    final quantityController = TextEditingController();
    final hoursController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouveau lot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantityController,
              decoration: const InputDecoration(labelText: 'Quantite'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: hoursController,
              decoration: const InputDecoration(
                labelText: 'DLC apres ouverture (heures)',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Creer'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final quantity =
        double.tryParse(quantityController.text.replaceAll(',', '.'));
    if (quantity == null) {
      return;
    }
    await _mutate(
      () => ref.read(stockRepositoryProvider).createBatch(
            ingredientId: widget.ingredient.id,
            quantity: quantity,
            useWithinHoursAfterOpening: int.tryParse(hoursController.text),
          ),
    );
  }

  Future<void> _discard(int batchId) async {
    final reasonController = TextEditingController(text: 'batch_discard');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jeter le lot'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(labelText: 'Raison'),
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
    if (confirmed != true) {
      return;
    }
    await _mutate(
      () => ref.read(stockRepositoryProvider).discardBatch(
            batchId: batchId,
            reason: reasonController.text,
          ),
    );
  }

  Future<void> _mutate(Future<Object?> Function() call) async {
    await call();
    setState(_reload);
  }
}
