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
import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
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
    final missingRecipes = ref.watch(stockMissingRecipesProvider);
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
                    _MissingRecipesPanel(
                      missingRecipes: missingRecipes,
                      onManageRecipe: () => _recipeDialog(context, ref),
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
    ref.invalidate(stockMissingRecipesProvider);
    ref.invalidate(adjustmentRequestsProvider);
    await Future.wait([
      ref.read(ingredientsProvider.future),
      ref.read(stockAlertsProvider.future),
      ref.read(stockMovementsProvider.future),
      ref.read(stockMissingRecipesProvider.future),
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
    final purchasePrice = TextEditingController(
      text: ingredient?.purchasePricePerUnit?.toString() ?? '',
    );
    final purchaseUnit = TextEditingController(
      text: ingredient?.purchaseUnit ?? ingredient?.unit ?? '',
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
            const SizedBox(height: 12),
            TextField(
              controller: purchasePrice,
              decoration: const InputDecoration(
                labelText: 'Prix achat par unite',
                hintText: 'Ex. 2.40',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: purchaseUnit,
              decoration: const InputDecoration(
                labelText: 'Unite achat',
                hintText: 'Ex. kg, l, piece',
              ),
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
          purchasePricePerUnit: _parseDouble(purchasePrice.text),
          purchaseUnit: purchaseUnit.text.trim(),
        );
      } else {
        await repository.patchIngredient(
          ingredientId: ingredient.id,
          name: name.text.trim(),
          unit: unit.text.trim(),
          alertThreshold: _parseDouble(threshold.text) ?? 0,
          purchasePricePerUnit: _parseDouble(purchasePrice.text),
          purchaseUnit: purchaseUnit.text.trim(),
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
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StockRecipeDialog(
        catalogRepository: ref.read(catalogRepositoryProvider),
        stockRepository: ref.read(stockRepositoryProvider),
      ),
    );
    if (saved == true && context.mounted) {
      ref.invalidate(stockMissingRecipesProvider);
      _snack(context, 'Recette enregistree');
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

class StockRecipeDialog extends StatefulWidget {
  const StockRecipeDialog({
    super.key,
    required this.catalogRepository,
    required this.stockRepository,
    this.initialTargetType = 'product',
    this.initialProductId,
  });

  final CatalogRepository catalogRepository;
  final StockRepository stockRepository;
  final String initialTargetType;
  final int? initialProductId;

  @override
  State<StockRecipeDialog> createState() => _RecipeDialogState();
}

class _RecipeDialogState extends State<StockRecipeDialog> {
  static const _units = ['g', 'kg', 'ml', 'l', 'piece', 'portion'];

  final _productSearchController = TextEditingController();
  final _ingredientSearchController = TextEditingController();
  final _quantityController = TextEditingController();

  String _targetType = 'product';
  List<CatalogProduct> _products = const [];
  List<Ingredient> _ingredients = const [];
  List<_RecipeDraftLine> _lines = const [];
  int? _selectedProductId;
  int? _selectedVariantId;
  int? _selectedExtraId;
  int? _selectedIngredientId;
  String _selectedUnit = 'g';
  bool _loading = true;
  bool _loadingRecipe = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _targetType = widget.initialTargetType;
    _loadLookups();
  }

  @override
  void dispose() {
    _productSearchController.dispose();
    _ingredientSearchController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  CatalogProduct? get _selectedProduct => _productById(_selectedProductId);

  CatalogVariant? get _selectedVariant {
    final id = _selectedVariantId;
    if (id == null) {
      return null;
    }
    for (final product in _products) {
      for (final variant in product.variants) {
        if (variant.id == id) {
          return variant;
        }
      }
    }
    return null;
  }

  CatalogExtra? get _selectedExtra {
    final id = _selectedExtraId;
    if (id == null) {
      return null;
    }
    for (final product in _products) {
      for (final extra in product.extras) {
        if (extra.id == id) {
          return extra;
        }
      }
    }
    return null;
  }

  Ingredient? get _selectedIngredient {
    final id = _selectedIngredientId;
    if (id == null) {
      return null;
    }
    for (final ingredient in _ingredients) {
      if (ingredient.id == id) {
        return ingredient;
      }
    }
    return null;
  }

  int? get _targetId {
    return switch (_targetType) {
      'variant' => _selectedVariantId,
      'extra' => _selectedExtraId,
      _ => _selectedProductId,
    };
  }

  String get _targetName {
    return switch (_targetType) {
      'variant' => _selectedVariant?.name ?? 'Variante',
      'extra' => _selectedExtra?.name ?? 'Extra',
      _ => _selectedProduct?.name ?? 'Produit',
    };
  }

  Future<void> _loadLookups() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await widget.catalogRepository.listProducts(
        pageSize: 100,
      );
      final ingredients = await widget.stockRepository.listIngredients(
        pageSize: 100,
      );
      if (!mounted) {
        return;
      }
      final initialProductId = widget.initialProductId;
      final productId = initialProductId != null &&
              products.any((product) => product.id == initialProductId)
          ? initialProductId
          : (products.isEmpty ? null : products.first.id);
      setState(() {
        _products = products;
        _ingredients = ingredients;
        _selectedProductId = productId;
        _selectedIngredientId =
            _ingredients.isEmpty ? null : _ingredients.first.id;
        _selectedUnit = _ingredients.isEmpty
            ? _selectedUnit
            : _normalizedUnit(_ingredients.first.unit);
        _syncTargetChildren();
        _loading = false;
      });
      await _loadSelectedRecipe();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadSelectedRecipe() async {
    final targetId = _targetId;
    if (targetId == null) {
      setState(() {
        _lines = const [];
      });
      return;
    }
    setState(() {
      _loadingRecipe = true;
      _error = null;
    });
    try {
      final recipe = switch (_targetType) {
        'variant' => await widget.stockRepository.getVariantRecipe(targetId),
        'extra' => await widget.stockRepository.getExtraRecipe(targetId),
        _ => await widget.stockRepository.getProductRecipe(targetId),
      };
      if (!mounted) {
        return;
      }
      setState(() {
        _lines = recipe.items
            .map(
              (line) => _RecipeDraftLine.fromRecipeLine(
                  line,
                  _ingredientById(line.ingredientId),
                ),
            )
            .toList();
        _loadingRecipe = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingRecipe = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _knownTotalCost();
    return AlertDialog(
      title: const Text('Recette stock'),
      content: SizedBox(
        width: 760,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'product',
                          icon: Icon(Icons.local_pizza_outlined),
                          label: Text('Produit'),
                        ),
                        ButtonSegment(
                          value: 'variant',
                          icon: Icon(Icons.tune_outlined),
                          label: Text('Variante'),
                        ),
                        ButtonSegment(
                          value: 'extra',
                          icon: Icon(Icons.add_circle_outline),
                          label: Text('Extra'),
                        ),
                      ],
                      selected: {_targetType},
                      onSelectionChanged: _saving
                          ? null
                          : (value) {
                              setState(() {
                                _targetType = value.first;
                                _syncTargetChildren();
                              });
                              _loadSelectedRecipe();
                            },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _targetFields(),
                    const SizedBox(height: AppSpacing.lg),
                    _recipeLines(total),
                    const SizedBox(height: AppSpacing.lg),
                    _ingredientPicker(),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _error!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Enregistrer'),
        ),
      ],
    );
  }

  Widget _targetFields() {
    final products = _filteredProducts();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _productSearchController,
          decoration: const InputDecoration(
            labelText: 'Recherche produit',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<int>(
          initialValue: _valueIfPresent(
            _selectedProductId,
            products.map((product) => product.id),
          ),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Produit',
            prefixIcon: Icon(Icons.restaurant_menu_outlined),
          ),
          items: products
              .map(
                (product) => DropdownMenuItem<int>(
                  value: product.id,
                  child: Text(
                    product.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _saving
              ? null
              : (value) {
                  setState(() {
                    _selectedProductId = value;
                    _syncTargetChildren();
                  });
                  _loadSelectedRecipe();
                },
        ),
        if (_targetType == 'variant') ...[
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<int>(
            initialValue: _valueIfPresent(
              _selectedVariantId,
              (_selectedProduct?.variants ?? const <CatalogVariant>[])
                  .map((variant) => variant.id),
            ),
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Variante',
              prefixIcon: Icon(Icons.tune_outlined),
            ),
            items: (_selectedProduct?.variants ?? const <CatalogVariant>[])
                .map(
                  (variant) => DropdownMenuItem<int>(
                    value: variant.id,
                    child: Text(variant.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) {
                    setState(() => _selectedVariantId = value);
                    _loadSelectedRecipe();
                  },
          ),
        ],
        if (_targetType == 'extra') ...[
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<int>(
            initialValue: _valueIfPresent(
              _selectedExtraId,
              (_selectedProduct?.extras ?? const <CatalogExtra>[])
                  .map((extra) => extra.id),
            ),
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Extra',
              prefixIcon: Icon(Icons.add_circle_outline),
            ),
            items: (_selectedProduct?.extras ?? const <CatalogExtra>[])
                .map(
                  (extra) => DropdownMenuItem<int>(
                    value: extra.id,
                    child: Text(extra.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) {
                    setState(() => _selectedExtraId = value);
                    _loadSelectedRecipe();
                  },
          ),
        ],
      ],
    );
  }

  Widget _recipeLines(double? total) {
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD8D0C3)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _targetName,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (_loadingRecipe)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    total == null ? 'Cout incomplet' : formatMoney(total),
                    style: textTheme.labelLarge?.copyWith(
                      color:
                          total == null ? AppColors.warning : AppColors.success,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_lines.isEmpty)
              Text(
                'Recette manquante',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w800,
                ),
              )
            else
              ..._lines.map(
                (line) {
                  final cost = _lineCost(line);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(line.ingredientName),
                    subtitle: Text(
                      '${formatStockQty(line.quantity)} ${line.unit}'
                      '${cost == null ? ' - prix achat manquant' : ' - ${formatMoney(cost)}'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Modifier',
                          onPressed: _saving ? null : () => _editLine(line),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Retirer',
                          onPressed: _saving
                              ? null
                              : () {
                                  setState(() {
                                    _lines = _lines
                                        .where(
                                          (item) =>
                                              item.ingredientId !=
                                              line.ingredientId,
                                        )
                                        .toList();
                                  });
                                },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _ingredientPicker() {
    final ingredients = _ingredientsForDropdown();
    final suggestions = _ingredientSuggestions();
    final canCreateIngredient = _canCreateIngredientFromSearch();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ajouter un ingredient',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _ingredientSearchController,
          decoration: const InputDecoration(
            labelText: 'Recherche ingredient',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: suggestions
                .map(
                  (ingredient) => ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: Text(ingredient.name),
                    onPressed: () => _selectIngredient(ingredient),
                  ),
                )
                .toList(),
          ),
        ],
        if (canCreateIngredient) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _saving ? null : _createIngredientFromRecipe,
            icon: const Icon(Icons.add_box_outlined),
            label: Text(
              suggestions.isEmpty
                  ? 'Creer cet ingredient'
                  : 'Creer un nouvel ingredient',
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<int>(
          initialValue: _valueIfPresent(
            _selectedIngredientId,
            ingredients.map((ingredient) => ingredient.id),
          ),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Ingredient',
            prefixIcon: Icon(Icons.inventory_outlined),
          ),
          items: ingredients
              .map(
                (ingredient) => DropdownMenuItem<int>(
                  value: ingredient.id,
                  child: Text(
                    ingredient.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _saving
              ? null
              : (value) {
                  final ingredient = _ingredientById(value);
                  if (ingredient != null) {
                    _selectIngredient(ingredient);
                  }
                },
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _quantityController,
                decoration: const InputDecoration(
                  labelText: 'Quantite',
                  prefixIcon: Icon(Icons.scale_outlined),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedUnit,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Unite'),
                items: _units
                    .map(
                      (unit) => DropdownMenuItem<String>(
                        value: unit,
                        child: Text(unit),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedUnit = value);
                        }
                      },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: _saving ? null : _addLine,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _selectIngredient(Ingredient ingredient) {
    setState(() {
      _selectedIngredientId = ingredient.id;
      _selectedUnit = _normalizedUnit(ingredient.unit);
      _error = null;
    });
  }

  bool _canCreateIngredientFromSearch() {
    final query = _ingredientSearchController.text.trim().toLowerCase();
    if (query.length < 3) {
      return false;
    }
    return !_ingredients.any(
      (ingredient) => ingredient.name.trim().toLowerCase() == query,
    );
  }

  Future<void> _createIngredientFromRecipe() async {
    final created = await _ingredientInlineDialog(
      initialName: _ingredientSearchController.text.trim(),
    );
    if (created == null || !mounted) {
      return;
    }
    setState(() {
      _ingredients = [..._ingredients, created]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _selectedIngredientId = created.id;
      _selectedUnit = _normalizedUnit(created.unit);
      _ingredientSearchController.text = created.name;
      _error = null;
    });
  }

  Future<Ingredient?> _ingredientInlineDialog({
    required String initialName,
  }) async {
    final name = TextEditingController(text: initialName);
    final qty = TextEditingController(text: '0');
    final threshold = TextEditingController(text: '0');
    final purchasePrice = TextEditingController();
    var unit = _selectedUnit;
    var purchaseUnit = _selectedUnit;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nouvel ingredient'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Nom ingredient',
                    prefixIcon: Icon(Icons.inventory_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        initialValue: unit,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Unite stock',
                        ),
                        items: _units
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            unit = value;
                            purchaseUnit = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: qty,
                        decoration: const InputDecoration(
                          labelText: 'Stock initial',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: threshold,
                        decoration: const InputDecoration(
                          labelText: 'Seuil alerte',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SizedBox(
                      width: 190,
                      child: TextField(
                        controller: purchasePrice,
                        decoration: const InputDecoration(
                          labelText: 'Prix achat par unite',
                          prefixIcon: Icon(Icons.euro_outlined),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        initialValue: purchaseUnit,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Unite achat',
                        ),
                        items: _units
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => purchaseUnit = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check_outlined),
              label: const Text('Creer'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      return null;
    }

    final ingredientName = name.text.trim();
    if (ingredientName.isEmpty) {
      setState(() => _error = 'Nom ingredient obligatoire.');
      return null;
    }
    try {
      return await widget.stockRepository.createIngredient(
        name: ingredientName,
        unit: unit,
        currentQty: _parseDouble(qty.text) ?? 0,
        alertThreshold: _parseDouble(threshold.text) ?? 0,
        purchasePricePerUnit: _parseDouble(purchasePrice.text),
        purchaseUnit: purchaseUnit,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
      return null;
    }
  }

  void _editLine(_RecipeDraftLine line) {
    setState(() {
      _selectedIngredientId = line.ingredientId;
      _selectedUnit = _normalizedUnit(line.unit);
      _quantityController.text = formatStockQty(line.quantity);
      _ingredientSearchController.text = line.ingredientName;
      _lines = _lines
          .where((item) => item.ingredientId != line.ingredientId)
          .toList();
      _error = null;
    });
  }

  double? _parseDouble(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  void _addLine() {
    final ingredient = _selectedIngredient;
    final quantity =
        double.tryParse(_quantityController.text.trim().replaceAll(',', '.'));
    if (ingredient == null || quantity == null || quantity <= 0) {
      setState(() => _error = 'Saisie ingredient invalide.');
      return;
    }
    final draft = _RecipeDraftLine.fromIngredient(
      ingredient,
      quantity: quantity,
      unit: _selectedUnit,
    );
    final next = [..._lines];
    final existingIndex = next.indexWhere(
      (line) => line.ingredientId == draft.ingredientId,
    );
    if (existingIndex >= 0) {
      final existing = next[existingIndex];
      next[existingIndex] = existing.copyWith(
        quantity: existing.quantity + draft.quantity,
        unit: draft.unit,
      );
    } else {
      next.add(draft);
    }
    setState(() {
      _lines = next;
      _quantityController.clear();
      _error = null;
    });
  }

  Future<void> _save() async {
    final targetId = _targetId;
    if (targetId == null) {
      setState(() => _error = 'Selectionnez une cible valide.');
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _error = 'Ajoutez au moins un ingredient.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final items = _lines
        .map(
          (line) => StockRecipeInputLine(
            ingredientId: line.ingredientId,
            quantity: line.quantity,
            unit: line.unit,
          ),
        )
        .toList();
    try {
      switch (_targetType) {
        case 'variant':
          await widget.stockRepository.replaceVariantRecipe(
            variantId: targetId,
            items: items,
          );
        case 'extra':
          await widget.stockRepository.replaceExtraRecipe(
            extraId: targetId,
            items: items,
          );
        default:
          await widget.stockRepository.replaceProductRecipe(
            productId: targetId,
            items: items,
          );
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  void _syncTargetChildren() {
    final product = _selectedProduct;
    final variants = product?.variants ?? const <CatalogVariant>[];
    final extras = product?.extras ?? const <CatalogExtra>[];
    if (variants.every((variant) => variant.id != _selectedVariantId)) {
      _selectedVariantId = variants.isEmpty ? null : variants.first.id;
    }
    if (extras.every((extra) => extra.id != _selectedExtraId)) {
      _selectedExtraId = extras.isEmpty ? null : extras.first.id;
    }
  }

  List<CatalogProduct> _filteredProducts() {
    final query = _productSearchController.text.trim().toLowerCase();
    final filtered = query.length < 3
        ? _products
        : _products
            .where((product) => product.name.toLowerCase().contains(query))
            .toList();
    final selected = _selectedProduct;
    if (selected == null ||
        filtered.any((product) => product.id == selected.id)) {
      return filtered;
    }
    return [selected, ...filtered];
  }

  List<Ingredient> _ingredientsForDropdown() {
    final selected = _selectedIngredient;
    if (selected == null ||
        _ingredients.any((ingredient) => ingredient.id == selected.id)) {
      return _ingredients;
    }
    return [selected, ..._ingredients];
  }

  List<Ingredient> _ingredientSuggestions() {
    final query = _ingredientSearchController.text.trim().toLowerCase();
    if (query.length < 3) {
      return const [];
    }
    return _ingredients
        .where((ingredient) => ingredient.name.toLowerCase().contains(query))
        .take(8)
        .toList();
  }

  CatalogProduct? _productById(int? id) {
    if (id == null) {
      return null;
    }
    for (final product in _products) {
      if (product.id == id) {
        return product;
      }
    }
    return null;
  }

  Ingredient? _ingredientById(int? id) {
    if (id == null) {
      return null;
    }
    for (final ingredient in _ingredients) {
      if (ingredient.id == id) {
        return ingredient;
      }
    }
    return null;
  }

  int? _valueIfPresent(int? value, Iterable<int> values) {
    if (value == null) {
      return null;
    }
    return values.contains(value) ? value : null;
  }

  double? _knownTotalCost() {
    if (_lines.isEmpty) {
      return null;
    }
    var total = 0.0;
    for (final line in _lines) {
      final cost = _lineCost(line);
      if (cost == null) {
        return null;
      }
      total += cost;
    }
    return total;
  }

  double? _lineCost(_RecipeDraftLine line) {
    final price = line.purchasePricePerUnit;
    final purchaseUnit = line.purchaseUnit;
    if (price == null || purchaseUnit == null || purchaseUnit.isEmpty) {
      return null;
    }
    final converted = _convertQuantity(
      line.quantity,
      fromUnit: line.unit,
      toUnit: purchaseUnit,
    );
    return converted == null ? null : converted * price;
  }

  double? _convertQuantity(
    double quantity, {
    required String fromUnit,
    required String toUnit,
  }) {
    final from = fromUnit.trim().toLowerCase();
    final to = toUnit.trim().toLowerCase();
    if (from == to) {
      return quantity;
    }
    const factors = {
      'g': 1.0,
      'kg': 1000.0,
      'ml': 1.0,
      'l': 1000.0,
    };
    final mass = factors[from] != null && factors[to] != null;
    final bothMass = (from == 'g' || from == 'kg') && (to == 'g' || to == 'kg');
    final bothVolume =
        (from == 'ml' || from == 'l') && (to == 'ml' || to == 'l');
    if (!mass || (!bothMass && !bothVolume)) {
      return null;
    }
    return quantity * factors[from]! / factors[to]!;
  }

  String _normalizedUnit(String unit) {
    final normalized = unit.trim().toLowerCase();
    return _units.contains(normalized) ? normalized : 'piece';
  }
}

class _RecipeDraftLine {
  const _RecipeDraftLine({
    required this.ingredientId,
    required this.ingredientName,
    required this.quantity,
    required this.unit,
    this.purchasePricePerUnit,
    this.purchaseUnit,
  });

  factory _RecipeDraftLine.fromIngredient(
    Ingredient ingredient, {
    required double quantity,
    required String unit,
  }) {
    return _RecipeDraftLine(
      ingredientId: ingredient.id,
      ingredientName: ingredient.name,
      quantity: quantity,
      unit: unit,
      purchasePricePerUnit: ingredient.purchasePricePerUnit,
      purchaseUnit: ingredient.purchaseUnit,
    );
  }

  factory _RecipeDraftLine.fromRecipeLine(
    StockRecipeLine line,
    Ingredient? ingredient,
  ) {
    return _RecipeDraftLine(
      ingredientId: line.ingredientId,
      ingredientName:
          line.ingredientName ?? ingredient?.name ?? 'Ingredient #${line.ingredientId}',
      quantity: line.quantity,
      unit: line.unit ?? ingredient?.unit ?? 'piece',
      purchasePricePerUnit: ingredient?.purchasePricePerUnit,
      purchaseUnit: ingredient?.purchaseUnit,
    );
  }

  final int ingredientId;
  final String ingredientName;
  final double quantity;
  final String unit;
  final double? purchasePricePerUnit;
  final String? purchaseUnit;

  _RecipeDraftLine copyWith({
    double? quantity,
    String? unit,
  }) {
    return _RecipeDraftLine(
      ingredientId: ingredientId,
      ingredientName: ingredientName,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      purchasePricePerUnit: purchasePricePerUnit,
      purchaseUnit: purchaseUnit,
    );
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final searchWidth =
            constraints.maxWidth < 460 ? constraints.maxWidth : 340.0;
        return DsCard(
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: searchWidth,
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
      },
    );
  }
}

class _IngredientCardHeader extends StatelessWidget {
  const _IngredientCardHeader({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final veryNarrow = constraints.maxWidth < 320;
        final title = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.inventory_2_outlined,
                color: _stockColor(ingredient),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                ingredient.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ],
        );

        if (veryNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: AppSpacing.xs),
              _StockStatusBadge(ingredient: ingredient),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: _StockStatusBadge(ingredient: ingredient),
            ),
          ],
        );
      },
    );
  }
}

class _IngredientActionButton extends StatelessWidget {
  const _IngredientActionButton({
    required this.child,
    required this.compact,
  });

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!compact) return child;
    return SizedBox(
      width: 122,
      child: child,
    );
  }
}

class _IngredientMoreButton extends StatelessWidget {
  const _IngredientMoreButton({
    required this.ingredient,
    required this.canAdjust,
    required this.canEdit,
    required this.onAdjust,
    required this.onEdit,
  });

  final Ingredient ingredient;
  final bool canAdjust;
  final bool canEdit;
  final ValueChanged<Ingredient> onAdjust;
  final ValueChanged<Ingredient> onEdit;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_IngredientAction>(
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
          _IngredientCardHeader(ingredient: ingredient),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 340;
        return Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          alignment: compact ? WrapAlignment.start : WrapAlignment.end,
          children: [
            if (canSupply)
              _IngredientActionButton(
                compact: compact,
                child: FilledButton.icon(
                  onPressed: () => onSupply(ingredient),
                  icon: const Icon(Icons.add),
                  label: const Text('Appro'),
                ),
              ),
            _IngredientActionButton(
              compact: compact,
              child: OutlinedButton.icon(
                onPressed: () => onBatches(ingredient),
                icon: const Icon(Icons.event_note_outlined),
                label: const Text('Lots'),
              ),
            ),
            if (canAdjust || canEdit)
              _IngredientMoreButton(
                ingredient: ingredient,
                canAdjust: canAdjust,
                canEdit: canEdit,
                onAdjust: onAdjust,
                onEdit: onEdit,
              ),
          ],
        );
      },
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

class _MissingRecipesPanel extends StatelessWidget {
  const _MissingRecipesPanel({
    required this.missingRecipes,
    required this.onManageRecipe,
  });

  final AsyncValue<List<MissingStockRecipe>> missingRecipes;
  final VoidCallback onManageRecipe;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recettes a completer',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          missingRecipes.when(
            data: (items) {
              if (items.isEmpty) {
                return const StatusBadge(
                  label: 'Toutes les recettes sont definies',
                  tone: StatusTone.success,
                  icon: Icons.check_circle_outline,
                );
              }
              final productCount = items.where((item) => item.isProduct).length;
              final variantCount = items.where((item) => item.isVariant).length;
              final extraCount = items.where((item) => item.isExtra).length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusBadge(
                    label: '${items.length} recette(s) manquante(s)',
                    tone: StatusTone.warning,
                    icon: Icons.menu_book_outlined,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _RecipeCountChip(
                        label: 'Produits',
                        value: productCount,
                        icon: Icons.local_pizza_outlined,
                      ),
                      _RecipeCountChip(
                        label: 'Variantes',
                        value: variantCount,
                        icon: Icons.tune_outlined,
                      ),
                      _RecipeCountChip(
                        label: 'Extras',
                        value: extraCount,
                        icon: Icons.add_circle_outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final item in items.take(6))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_missingRecipeIcon(item.recipeType)),
                      title: Text(item.name),
                      subtitle: Text(_missingRecipeLabel(item.recipeType)),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onManageRecipe,
                      icon: const Icon(Icons.edit_note_outlined),
                      label: const Text('Gerer les recettes'),
                    ),
                  ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => const Text(
              'Recettes manquantes indisponibles pour le moment.',
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipeCountChip extends StatelessWidget {
  const _RecipeCountChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: '$label $value',
      tone: value == 0 ? StatusTone.success : StatusTone.warning,
      icon: icon,
      compact: true,
    );
  }
}

IconData _missingRecipeIcon(String recipeType) {
  return switch (recipeType) {
    'variant' => Icons.tune_outlined,
    'extra' => Icons.add_circle_outline,
    _ => Icons.local_pizza_outlined,
  };
}

String _missingRecipeLabel(String recipeType) {
  return switch (recipeType) {
    'variant' => 'Variante a verifier',
    'extra' => 'Extra sans recette',
    _ => 'Produit sans recette',
  };
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
