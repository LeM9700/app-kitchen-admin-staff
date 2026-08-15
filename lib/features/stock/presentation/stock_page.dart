import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/core/widgets/live_countdown.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/components/cards/stat_card.dart';
import 'package:app_admin_staff/design_system/components/forms/pill_filter_bar.dart';
import 'package:app_admin_staff/design_system/tokens/app_breakpoints.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
    final isAdmin = user?.role == 'admin' || user?.role == 'super-admin';
    final requests = isAdmin
        ? ref.watch(adjustmentRequestsProvider)
        : const AsyncValue<List<StockAdjustmentRequest>>.data([]);
    final permissions = PermissionSet(
      role: user?.role ?? 'staff',
      permissions: user?.permissions,
    );

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        padding: EdgeInsets.all(
          AppBreakpoints.isMobile(context) ? AppSpacing.md : AppSpacing.xxl,
        ),
        children: [
          _StockHeader(
            isAdmin: isAdmin,
            onRefresh: () => _refresh(ref),
            onCreateIngredient: () => _ingredientDialog(context, ref),
            onRecipe: () => _recipeDialog(context, ref),
          ),
          const SizedBox(height: AppSpacing.lg),
          _StockStatsRow(
            ingredients: ingredients.valueOrNull,
            alerts: alerts.valueOrNull,
            requests: requests.valueOrNull,
            movements: movements.valueOrNull,
          ),
          const SizedBox(height: AppSpacing.lg),
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
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1180;
              final table = _IngredientsPanel(
                ingredients: ingredients,
                isAdmin: isAdmin,
                permissions: permissions,
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
                    isAdmin: isAdmin,
                    onReview: (request, approve) => _review(
                      context,
                      ref,
                      request.id,
                      approve: approve,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _StockMovementsPanel(movements: movements),
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
                  Expanded(child: table),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(width: 360, child: side),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _supply(
    BuildContext context,
    WidgetRef ref,
    Ingredient ingredient,
  ) async {
    final controller = TextEditingController();
    final quantity = await _numberDialog(
      context,
      title: 'Approvisionner ${ingredient.name}',
      controller: controller,
    );
    if (quantity == null) {
      return;
    }
    try {
      await ref.read(stockRepositoryProvider).supply(
            ingredientId: ingredient.id,
            quantity: quantity,
          );
      ref.invalidate(ingredientsProvider);
      ref.invalidate(stockMovementsProvider);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(ingredientsProvider);
    ref.invalidate(stockMovementsProvider);
    ref.invalidate(adjustmentRequestsProvider);
    await Future.wait([
      ref.read(ingredientsProvider.future),
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
    final quantityController = TextEditingController();
    final noteController = TextEditingController();
    var reason = 'correction';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Demande ajustement - ${ingredient.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: const InputDecoration(labelText: 'Raison'),
                items: const [
                  DropdownMenuItem(value: 'waste', child: Text('Perte')),
                  DropdownMenuItem(value: 'loss', child: Text('Casse')),
                  DropdownMenuItem(
                    value: 'correction',
                    child: Text('Correction'),
                  ),
                  DropdownMenuItem(
                    value: 'inventory',
                    child: Text('Inventaire'),
                  ),
                ],
                onChanged: (value) => setState(() => reason = value ?? reason),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                decoration: const InputDecoration(
                  labelText: 'Delta quantite',
                  prefixIcon: Icon(Icons.swap_vert),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note'),
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
              child: const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final quantity = _parseDouble(quantityController.text);
    if (quantity == null) {
      _snack(context, 'Quantite invalide');
      return;
    }
    try {
      await ref.read(stockRepositoryProvider).createAdjustmentRequest(
            ingredientId: ingredient.id,
            quantityDelta: quantity,
            reason: reason,
            note: noteController.text,
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
      ref.invalidate(stockMovementsProvider);
    } catch (error) {
      if (context.mounted) {
        _snack(context, error.toString());
      }
    }
  }

  Future<double?> _numberDialog(
    BuildContext context, {
    required String title,
    required TextEditingController controller,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Quantite',
            prefixIcon: Icon(Icons.scale_outlined),
          ),
          keyboardType: TextInputType.number,
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
      return null;
    }
    return _parseDouble(controller.text);
  }

  double? _parseDouble(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StockHeader extends StatelessWidget {
  const _StockHeader({
    required this.isAdmin,
    required this.onRefresh,
    required this.onCreateIngredient,
    required this.onRecipe,
  });

  final bool isAdmin;
  final VoidCallback onRefresh;
  final VoidCallback onCreateIngredient;
  final VoidCallback onRecipe;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stock', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Inventaire, alertes seuil et demandes d ajustement',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          alignment: WrapAlignment.end,
          children: [
            if (isAdmin) ...[
              IconButton.filled(
                tooltip: 'Nouvel ingredient',
                onPressed: onCreateIngredient,
                icon: const Icon(Icons.add),
              ),
              IconButton.filledTonal(
                tooltip: 'Recette',
                onPressed: onRecipe,
                icon: const Icon(Icons.menu_book_outlined),
              ),
            ],
            IconButton.filledTonal(
              tooltip: 'Rafraichir',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ],
    );
  }
}

class _StockStatsRow extends StatelessWidget {
  const _StockStatsRow({
    required this.ingredients,
    required this.alerts,
    required this.requests,
    required this.movements,
  });

  final List<Ingredient>? ingredients;
  final List<Ingredient>? alerts;
  final List<StockAdjustmentRequest>? requests;
  final List<StockMovement>? movements;

  @override
  Widget build(BuildContext context) {
    final pending =
        requests?.where((request) => request.status == 'pending').length;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        AppStatCard(
          label: 'Ingredients',
          value: ingredients?.length.toString() ?? '-',
          subtitle: 'Charges depuis API',
          icon: Icons.warehouse_outlined,
          accentColor: AppColors.infoAlt,
        ),
        AppStatCard(
          label: 'Alertes basses',
          value: alerts?.length.toString() ?? '-',
          subtitle: 'Seuils actifs',
          icon: Icons.warning_amber_outlined,
          accentColor:
              (alerts?.isEmpty ?? true) ? AppColors.success : AppColors.danger,
        ),
        AppStatCard(
          label: 'Demandes',
          value: pending?.toString() ?? '-',
          subtitle: 'En attente admin',
          icon: Icons.tune_outlined,
          accentColor:
              (pending ?? 0) == 0 ? AppColors.success : AppColors.warning,
        ),
        AppStatCard(
          label: 'Mouvements',
          value: movements?.length.toString() ?? '-',
          subtitle: 'Derniers evenements',
          icon: Icons.history_outlined,
          accentColor: AppColors.accent,
        ),
      ],
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
    required this.isAdmin,
    required this.permissions,
    required this.onEdit,
    required this.onSupply,
    required this.onAdjust,
    required this.onBatches,
  });

  final AsyncValue<List<Ingredient>> ingredients;
  final bool isAdmin;
  final PermissionSet permissions;
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
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  constraints.maxWidth < 840 ? 840.0 : constraints.maxWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      const _IngredientHeader(),
                      const Divider(height: 1),
                      for (final ingredient in items) ...[
                        _IngredientRow(
                          ingredient: ingredient,
                          isAdmin: isAdmin,
                          permissions: permissions,
                          onEdit: onEdit,
                          onSupply: onSupply,
                          onAdjust: onAdjust,
                          onBatches: onBatches,
                        ),
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
        error: (error, stackTrace) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: EmptyState(
            icon: Icons.error_outline,
            title: 'Stock indisponible',
            subtitle: error.toString(),
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
          _StockTableLabel('Seuil', width: 120),
          _StockTableLabel('Etat', width: 130),
          Expanded(child: _StockTableLabel('Actions')),
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.ingredient,
    required this.isAdmin,
    required this.permissions,
    required this.onEdit,
    required this.onSupply,
    required this.onAdjust,
    required this.onBatches,
  });

  final Ingredient ingredient;
  final bool isAdmin;
  final PermissionSet permissions;
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
                  ingredient.isBelowThreshold
                      ? Icons.warning_amber_outlined
                      : Icons.inventory_outlined,
                  color: ingredient.isBelowThreshold
                      ? AppColors.danger
                      : AppColors.infoAlt,
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
            child: Text('${_qty(ingredient.currentQty)} ${ingredient.unit}'),
          ),
          SizedBox(
            width: 120,
            child:
                Text('${_qty(ingredient.alertThreshold)} ${ingredient.unit}'),
          ),
          SizedBox(
            width: 130,
            child: StatusBadge(
              label: ingredient.isBelowThreshold ? 'Sous seuil' : 'OK',
              tone: ingredient.isBelowThreshold
                  ? StatusTone.danger
                  : StatusTone.success,
              compact: true,
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: AppSpacing.xs,
              alignment: WrapAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Modifier',
                  onPressed: isAdmin ? () => onEdit(ingredient) : null,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Approvisionner',
                  onPressed: permissions.can(AppPermission.stockWrite)
                      ? () => onSupply(ingredient)
                      : null,
                  icon: const Icon(Icons.add_box_outlined),
                ),
                IconButton(
                  tooltip: 'Ajustement',
                  onPressed:
                      permissions.can(AppPermission.stockAdjustmentCreate)
                          ? () => onAdjust(ingredient)
                          : null,
                  icon: const Icon(Icons.tune_outlined),
                ),
                IconButton(
                  tooltip: 'Lots',
                  onPressed: () => onBatches(ingredient),
                  icon: const Icon(Icons.event_note_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _qty(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }
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
              if (items.isEmpty) {
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
                    label: '${items.length} alerte(s) basse(s)',
                    tone: StatusTone.danger,
                    icon: Icons.warning_amber_outlined,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final item in items.take(4))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.name),
                      subtitle: Text(
                        '${item.currentQty} ${item.unit} / seuil ${item.alertThreshold}',
                      ),
                    ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => Text(error.toString()),
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
    required this.isAdmin,
    required this.onReview,
  });

  final AsyncValue<List<StockAdjustmentRequest>> requests;
  final bool isAdmin;
  final void Function(StockAdjustmentRequest request, bool approve) onReview;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Demandes', style: Theme.of(context).textTheme.titleMedium),
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
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        request.isLargeAdjustment
                            ? Icons.priority_high_outlined
                            : Icons.tune_outlined,
                      ),
                      title: Text(
                        'Ingredient #${request.ingredientId} - ${request.quantityDelta}',
                      ),
                      subtitle: Text('${request.reason} - ${request.status}'),
                      trailing: isAdmin && request.status == 'pending'
                          ? Wrap(
                              spacing: AppSpacing.xs,
                              children: [
                                IconButton(
                                  tooltip: 'Approuver',
                                  onPressed: () => onReview(request, true),
                                  icon: const Icon(Icons.check_circle_outline),
                                ),
                                IconButton(
                                  tooltip: 'Rejeter',
                                  onPressed: () => onReview(request, false),
                                  icon: const Icon(Icons.cancel_outlined),
                                ),
                              ],
                            )
                          : null,
                    ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => Text(error.toString()),
          ),
        ],
      ),
    );
  }
}

class _StockMovementsPanel extends StatelessWidget {
  const _StockMovementsPanel({required this.movements});

  final AsyncValue<List<StockMovement>> movements;

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
              return Column(
                children: [
                  for (final movement in items.take(8))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        movement.quantityDelta >= 0
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline,
                      ),
                      title: Text(
                        'Ingredient #${movement.ingredientId} - ${movement.quantityDelta}',
                      ),
                      subtitle: Text(movement.reason),
                      trailing: Text(formatDateTime(movement.createdAt)),
                    ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => Text(error.toString()),
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
                Text(
                  'Lots - ${widget.ingredient.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
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
            else if (batches.isEmpty)
              const ListTile(
                leading: Icon(Icons.event_note_outlined),
                title: Text('Aucun lot'),
              )
            else
              ...batches.map((batch) {
                return ListTile(
                  title: Text('${batch.quantity} ${widget.ingredient.unit}'),
                  subtitle: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${batch.status} - DLC'),
                      LiveCountdown(
                        target: batch.effectiveExpiresAt ?? batch.expiresAt,
                      ),
                    ],
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      IconButton(
                        tooltip: 'Ouvrir',
                        onPressed: batch.status == 'sealed'
                            ? () => _mutate(
                                  () => ref
                                      .read(stockRepositoryProvider)
                                      .openBatch(batch.id),
                                )
                            : null,
                        icon: const Icon(Icons.lock_open_outlined),
                      ),
                      IconButton(
                        tooltip: 'Jeter',
                        onPressed: () => _discard(batch.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
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
