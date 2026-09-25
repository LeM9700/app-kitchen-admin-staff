import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/components/forms/pill_filter_bar.dart';
import 'package:app_admin_staff/design_system/theme/staggered_entrance.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/catalog/application/catalog_view_state.dart';
import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key});

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage> {
  final _filterController = TextEditingController();
  final _imagePicker = ImagePicker();
  final Set<int> _availabilityBusy = <int>{};

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(catalogProductsProvider);
    final categories = ref.watch(catalogCategoriesProvider);
    final selectedCategoryId = ref.watch(catalogCategoryFilterProvider);
    final availabilityFilter = ref.watch(catalogAvailabilityFilterProvider);
    final permissions = ref.watch(currentPermissionSetProvider);
    final canWrite = permissions.can(AppPermission.catalogWrite);
    final canManageAvailability =
        permissions.can(AppPermission.catalogAvailability);
    final isMobile = Breakpoints.isMobile(context);

    return RefreshIndicator(
      onRefresh: _refreshCatalog,
      child: ColoredBox(
        color: const Color(0xFFE8E2D8),
        child: ListView(
          padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xxl),
          children: [
            _CatalogHeader(
              isMobile: isMobile,
              canWrite: canWrite,
              onRefresh: _refreshCatalog,
              onCreateProduct: () =>
                  _productDialog(categories.valueOrNull ?? const []),
              onCreateCategory: () => _categoryDialog(),
              onImport: _importCsvDialog,
              onExport: _exportCsv,
              onCompleteness: _completenessDialog,
            ),
            const SizedBox(height: AppSpacing.md),
            products.when(
              data: (items) => _CatalogStatsRow(
                products: items,
                categoryCount: categories.valueOrNull?.length,
                onFilter: (filter) {
                  ref.read(catalogAvailabilityFilterProvider.notifier).state =
                      filter;
                },
              ),
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => const EmptyState(
                icon: Icons.error_outline,
                title: 'Indicateurs indisponibles',
                subtitle:
                    'Les indicateurs catalogue ne peuvent pas etre charges.',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            categories.when(
              data: (items) => _CatalogToolbar(
                controller: _filterController,
                categories: items,
                selectedCategoryId: selectedCategoryId,
                availabilityFilter: availabilityFilter,
                onSearchChanged: (value) {
                  ref.read(catalogSearchProvider.notifier).state = value;
                },
                onCategorySelected: (value) {
                  ref.read(catalogCategoryFilterProvider.notifier).state =
                      value;
                },
                onAvailabilitySelected: (value) {
                  ref.read(catalogAvailabilityFilterProvider.notifier).state =
                      value;
                },
                onEditCategory: canWrite
                    ? (category) => _categoryDialog(category: category)
                    : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => const EmptyState(
                icon: Icons.category_outlined,
                title: 'Categories indisponibles',
                subtitle: 'Les categories ne peuvent pas etre chargees.',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1180;
                final productPaneWidth = wide
                    ? constraints.maxWidth - 370 - AppSpacing.md
                    : constraints.maxWidth;
                final compactProducts = productPaneWidth < 1040;
                final productList = products.when(
                  data: (items) {
                    final filtered = _applyAvailabilityFilter(
                      items,
                      availabilityFilter,
                    );
                    return _ProductTable(
                      products: filtered,
                      compactCards: compactProducts,
                      canWrite: canWrite,
                      canManageAvailability: canManageAvailability,
                      busyIds: _availabilityBusy,
                      onOpen: _detail,
                      onEdit: (product) => _productDialog(
                        categories.valueOrNull ?? const [],
                        product: product,
                      ),
                      onDelete: _deleteProduct,
                      onStation: _editStation,
                      onAvailability: (product, available) =>
                          _availability(product, available),
                    );
                  },
                  loading: () => const _CatalogSkeleton(),
                  error: (error, stackTrace) => const EmptyState(
                    icon: Icons.error_outline,
                    title: 'Catalogue indisponible',
                    subtitle: 'Les produits ne peuvent pas etre charges.',
                  ),
                );
                final contextPanel = _CatalogContextPanel(
                  products: products.valueOrNull ?? const [],
                  categories: categories.valueOrNull ?? const [],
                  onIncomplete: () {
                    ref.read(catalogAvailabilityFilterProvider.notifier).state =
                        CatalogAvailabilityFilter.incomplete;
                  },
                  onEditCategory: canWrite
                      ? (category) => _categoryDialog(category: category)
                      : null,
                );

                if (!wide) {
                  return Column(
                    children: [
                      productList,
                      const SizedBox(height: AppSpacing.md),
                      contextPanel,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: productList),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(width: 370, child: contextPanel),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshCatalog() async {
    ref.invalidate(catalogProductsProvider);
    ref.invalidate(catalogCategoriesProvider);
    await Future.wait([
      ref.read(catalogProductsProvider.future),
      ref.read(catalogCategoriesProvider.future),
    ]);
    if (mounted) {
      _snack('Catalogue rafraichi');
    }
  }

  List<CatalogProduct> _applyAvailabilityFilter(
    List<CatalogProduct> products,
    CatalogAvailabilityFilter filter,
  ) {
    return products
        .where((product) => matchesCatalogFilter(product, filter))
        .toList();
  }

  Future<void> _availability(CatalogProduct product, bool available) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(available ? 'Rendre disponible' : 'Indisponibilite'),
        content: TextField(
          controller: reasonController,
          decoration: InputDecoration(
            labelText: available ? 'Raison' : 'Raison obligatoire',
            prefixIcon: const Icon(Icons.notes_outlined),
          ),
          autofocus: !available,
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
    if (!available && reasonController.text.trim().isEmpty) {
      _snack('Raison obligatoire');
      return;
    }
    setState(() => _availabilityBusy.add(product.id));
    try {
      await ref.read(catalogRepositoryProvider).setAvailabilityOverride(
            productId: product.id,
            available: available,
            reason: reasonController.text,
          );
      ref.invalidate(catalogProductsProvider);
      await ref.read(catalogProductsProvider.future);
      if (mounted) {
        _snack('Disponibilite confirmee');
      }
    } catch (error) {
      _snack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _availabilityBusy.remove(product.id));
      }
    }
  }

  Future<void> _categoryDialog({CatalogCategory? category}) async {
    final name = TextEditingController(text: category?.name ?? '');
    var station = category?.preparationStation ?? 'kitchen';
    var active = category?.isActive ?? true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            category == null ? 'Nouvelle categorie' : 'Modifier categorie',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: station,
                decoration: const InputDecoration(labelText: 'Station'),
                items: const [
                  DropdownMenuItem(value: 'kitchen', child: Text('Cuisine')),
                  DropdownMenuItem(value: 'counter', child: Text('Comptoir')),
                  DropdownMenuItem(value: 'none', child: Text('Aucune')),
                ],
                onChanged: (value) =>
                    setState(() => station = value ?? station),
              ),
              if (category != null) ...[
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: active,
                  onChanged: (value) => setState(() => active = value),
                ),
              ],
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
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      final repository = ref.read(catalogRepositoryProvider);
      if (category == null) {
        await repository.createCategory(
          name: name.text.trim(),
          preparationStation: station,
        );
      } else {
        await repository.updateCategory(
          categoryId: category.id,
          name: name.text.trim(),
          preparationStation: station,
          isActive: active,
        );
      }
      ref.invalidate(catalogCategoriesProvider);
      ref.invalidate(catalogProductsProvider);
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _productDialog(
    List<CatalogCategory> categories, {
    CatalogProduct? product,
  }) async {
    final name = TextEditingController(text: product?.name ?? '');
    final description = TextEditingController(text: product?.description ?? '');
    final price =
        TextEditingController(text: product?.basePrice.toString() ?? '');
    final imageUrl = TextEditingController(text: product?.imageUrl ?? '');
    final reason = TextEditingController();
    int? categoryId = product?.categoryId ??
        (categories.isEmpty ? null : categories.first.id);
    var station = product?.preparationStation ?? 'inherit';
    var active = product?.isActive ?? true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(product == null ? 'Nouveau produit' : 'Modifier produit'),
          content: SizedBox(
            width: 720,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'Informations generales',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: price,
                        decoration: const InputDecoration(labelText: 'Prix'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<int?>(
                        initialValue: categoryId,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Categorie'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Sans categorie'),
                          ),
                          ...categories.map(
                            (category) => DropdownMenuItem<int?>(
                              value: category.id,
                              child: Text(category.name),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => categoryId = value),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<String>(
                        initialValue: station,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Station'),
                        items: const [
                          DropdownMenuItem(
                            value: 'inherit',
                            child: Text('Categorie'),
                          ),
                          DropdownMenuItem(
                            value: 'kitchen',
                            child: Text('Cuisine'),
                          ),
                          DropdownMenuItem(
                            value: 'counter',
                            child: Text('Comptoir'),
                          ),
                          DropdownMenuItem(
                            value: 'none',
                            child: Text('Aucune'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => station = value ?? station),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Disponibilite operationnelle',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Produit actif dans le catalogue'),
                  subtitle: Text(
                    product == null
                        ? 'Etat initial envoye a la creation'
                        : 'Champ is_active du produit',
                  ),
                  value: active,
                  onChanged: (value) => setState(() => active = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: imageUrl,
                  decoration: const InputDecoration(
                    labelText: 'Image principale URL',
                    prefixIcon: Icon(Icons.image_outlined),
                  ),
                ),
                if (product != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(
                      labelText: 'Raison changement prix',
                      prefixIcon: Icon(Icons.history_outlined),
                    ),
                  ),
                ],
              ],
            ),
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
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      final repository = ref.read(catalogRepositoryProvider);
      if (product == null) {
        await repository.createProduct(
          categoryId: categoryId,
          name: name.text.trim(),
          description: description.text.trim(),
          basePrice:
              double.tryParse(price.text.trim().replaceAll(',', '.')) ?? 0,
          imageUrl: _emptyToNull(imageUrl.text),
          preparationStation: station == 'inherit' ? null : station,
          isActive: active,
        );
      } else {
        await repository.updateProduct(
          productId: product.id,
          categoryId: categoryId,
          name: name.text.trim(),
          description: description.text.trim(),
          basePrice: double.tryParse(price.text.trim().replaceAll(',', '.')),
          imageUrl: _emptyToNull(imageUrl.text),
          preparationStation: station,
          isActive: active,
          priceChangeReason: reason.text,
        );
      }
      ref.invalidate(catalogProductsProvider);
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _detail(CatalogProduct product) async {
    try {
      final permissions = ref.read(currentPermissionSetProvider);
      final canWrite = permissions.can(AppPermission.catalogWrite);
      final detail =
          await ref.read(catalogRepositoryProvider).getProduct(product.id);
      final history = await ref
          .read(catalogRepositoryProvider)
          .availabilityHistory(product.id);
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(detail.name),
          content: SizedBox(
            width: 620,
            child: ListView(
              shrinkWrap: true,
              children: [
                _ProductDetailHero(detail: detail),
                const SizedBox(height: 16),
                if (canWrite) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(context);
                          _variantDialog(detail);
                        },
                        icon: const Icon(Icons.tune_outlined),
                        label: const Text('Variante'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(context);
                          _extraDialog(detail);
                        },
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Extra'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(context);
                          _priceAuditDialog('product', detail.id);
                        },
                        icon: const Icon(Icons.history_outlined),
                        label: const Text('Prix'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(context);
                          _recommendationDialog(detail);
                        },
                        icon: const Icon(Icons.auto_awesome_motion_outlined),
                        label: const Text('Reco'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(context);
                          _mediaDialog(detail);
                        },
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Media'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.pop(context);
                          _allergensDialog(detail);
                        },
                        icon: const Icon(Icons.health_and_safety_outlined),
                        label: const Text('Allergenes'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (detail.gallery.isNotEmpty ||
                    detail.primaryImage != null) ...[
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final image = detail.gallery.isNotEmpty
                            ? detail.gallery[index]
                            : detail.primaryImage!;
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            image.urlThumbnail,
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const SizedBox(
                                width: 96,
                                height: 96,
                                child: Icon(Icons.broken_image_outlined),
                              );
                            },
                          ),
                        );
                      },
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                      itemCount:
                          detail.gallery.isNotEmpty ? detail.gallery.length : 1,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text(formatMoney(detail.basePrice))),
                    Chip(label: Text(detail.effectivePreparationStation)),
                    Chip(
                      label: Text(
                        detail.regulatoryComplete ? 'Complet' : 'Incomplet',
                      ),
                    ),
                  ],
                ),
                if ((detail.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(detail.description!),
                ],
                const SizedBox(height: 16),
                Text(
                  'Variantes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (detail.variants.isEmpty)
                  const ListTile(title: Text('Aucune variante'))
                else
                  ...detail.variants.map((variant) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(variant.name),
                      trailing: Text(
                        formatMoney(detail.basePrice + variant.priceDelta),
                      ),
                      onTap: canWrite
                          ? () {
                              Navigator.pop(context);
                              _variantDialog(detail, variant: variant);
                            }
                          : null,
                    );
                  }),
                const SizedBox(height: 12),
                Text('Extras', style: Theme.of(context).textTheme.titleMedium),
                if (detail.extras.isEmpty)
                  const ListTile(title: Text('Aucun extra'))
                else
                  ...detail.extras.map((extra) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(extra.name),
                      trailing: Text(formatMoney(extra.price)),
                      onTap: canWrite
                          ? () {
                              Navigator.pop(context);
                              _extraDialog(detail, extra: extra);
                            }
                          : null,
                    );
                  }),
                if (detail.recommendations.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Recommandations',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ...detail.recommendations.map((recommendation) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(recommendation.name),
                      subtitle: Text(recommendation.categoryName ?? '-'),
                      trailing: Text(formatMoney(recommendation.basePrice)),
                    );
                  }),
                ],
                if (detail.allergens.isNotEmpty ||
                    detail.dietaryTags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...detail.allergens
                          .map((name) => Chip(label: Text(name))),
                      ...detail.dietaryTags
                          .map((name) => Chip(label: Text(name))),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Historique disponibilite',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (history.isEmpty)
                  const ListTile(title: Text('Aucun historique'))
                else
                  ...history.take(8).map((entry) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        entry.available
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      title:
                          Text(entry.available ? 'Disponible' : 'Indisponible'),
                      subtitle: Text(entry.reason ?? '-'),
                      trailing: Text(formatDateTime(entry.createdAt)),
                    );
                  }),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _deleteProduct(CatalogProduct product) async {
    final confirmed = await _confirm(
      title: 'Supprimer ${product.name}',
      message: 'Cette action retire le produit du catalogue.',
    );
    if (!confirmed) {
      return;
    }
    try {
      await ref.read(catalogRepositoryProvider).deleteProduct(product.id);
      ref.invalidate(catalogProductsProvider);
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _variantDialog(
    CatalogProduct product, {
    CatalogVariant? variant,
  }) async {
    final name = TextEditingController(text: variant?.name ?? '');
    final price =
        TextEditingController(text: variant?.priceDelta.toString() ?? '0');
    final reason = TextEditingController();
    var active = variant?.isActive ?? true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title:
              Text(variant == null ? 'Nouvelle variante' : 'Modifier variante'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: price,
                decoration: const InputDecoration(labelText: 'Delta prix'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Disponible'),
                value: active,
                onChanged: (value) => setState(() => active = value),
              ),
              if (variant != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Raison prix'),
                ),
              ],
            ],
          ),
          actions: [
            if (variant != null)
              TextButton.icon(
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer'),
              ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == null) {
      return;
    }
    try {
      final repository = ref.read(catalogRepositoryProvider);
      if (confirmed == false && variant != null) {
        await repository.deleteVariant(
          productId: product.id,
          variantId: variant.id,
        );
      } else if (variant == null) {
        await repository.createVariant(
          productId: product.id,
          name: name.text.trim(),
          priceDelta: _double(price.text),
          isAvailable: active,
        );
      } else {
        await repository.updateVariant(
          productId: product.id,
          variantId: variant.id,
          name: name.text.trim(),
          priceDelta: _double(price.text),
          isAvailable: active,
          priceChangeReason: reason.text,
        );
      }
      ref.invalidate(catalogProductsProvider);
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _extraDialog(
    CatalogProduct product, {
    CatalogExtra? extra,
  }) async {
    final name = TextEditingController(text: extra?.name ?? '');
    final price = TextEditingController(text: extra?.price.toString() ?? '0');
    final reason = TextEditingController();
    var active = extra?.isActive ?? true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(extra == null ? 'Nouvel extra' : 'Modifier extra'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: price,
                decoration: const InputDecoration(labelText: 'Prix'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Actif'),
                value: active,
                onChanged: (value) => setState(() => active = value),
              ),
              if (extra != null) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Raison prix'),
                ),
              ],
            ],
          ),
          actions: [
            if (extra != null)
              TextButton.icon(
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.link_off_outlined),
                label: const Text('Retirer'),
              ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == null) {
      return;
    }
    try {
      final repository = ref.read(catalogRepositoryProvider);
      if (confirmed == false && extra != null) {
        await repository.unlinkExtra(productId: product.id, extraId: extra.id);
      } else if (extra == null) {
        final created = await repository.createExtra(
          name: name.text.trim(),
          price: _double(price.text),
          isActive: active,
        );
        await repository.linkExtra(productId: product.id, extraId: created.id);
      } else {
        await repository.updateExtra(
          extraId: extra.id,
          name: name.text.trim(),
          price: _double(price.text),
          isActive: active,
          priceChangeReason: reason.text,
        );
      }
      ref.invalidate(catalogProductsProvider);
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmer'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _editStation(CatalogProduct product) async {
    var station = product.preparationStation ?? 'inherit';
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Station - ${product.name}'),
          content: DropdownButtonFormField<String>(
            initialValue: station,
            decoration: const InputDecoration(
              labelText: 'Station preparation',
              prefixIcon: Icon(Icons.restaurant_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 'inherit', child: Text('Categorie')),
              DropdownMenuItem(value: 'kitchen', child: Text('Cuisine')),
              DropdownMenuItem(value: 'counter', child: Text('Comptoir')),
              DropdownMenuItem(value: 'none', child: Text('Aucune')),
            ],
            onChanged: (value) => setState(() => station = value ?? 'inherit'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, station),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) {
      return;
    }
    try {
      await ref.read(catalogRepositoryProvider).updateProduct(
            productId: product.id,
            preparationStation: selected,
          );
      ref.invalidate(catalogProductsProvider);
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _mediaDialog(CatalogProduct product) async {
    try {
      var images = await ref.read(catalogRepositoryProvider).listImages(
            entityType: 'products',
            entityId: product.id,
          );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            Future<void> refresh() async {
              final fresh =
                  await ref.read(catalogRepositoryProvider).listImages(
                        entityType: 'products',
                        entityId: product.id,
                      );
              if (context.mounted) {
                setState(() => images = fresh);
              }
            }

            Future<void> upload(ImageSource source) async {
              try {
                final picked = await _imagePicker.pickImage(
                  source: source,
                  imageQuality: 86,
                  maxWidth: 1800,
                );
                if (picked == null) {
                  return;
                }
                final bytes = await picked.readAsBytes();
                await ref.read(catalogRepositoryProvider).uploadImage(
                      entityType: 'products',
                      entityId: product.id,
                      bytes: bytes,
                      filename: picked.name,
                      isPrimary: images.isEmpty,
                    );
                await refresh();
                ref.invalidate(catalogProductsProvider);
              } catch (error) {
                _snack(error.toString());
              }
            }

            Future<void> move(int index, int delta) async {
              final target = index + delta;
              if (target < 0 || target >= images.length) {
                return;
              }
              final reordered = [...images];
              final current = reordered.removeAt(index);
              reordered.insert(target, current);
              final fresh =
                  await ref.read(catalogRepositoryProvider).reorderImages(
                        entityType: 'products',
                        entityId: product.id,
                        imageIds: reordered.map((image) => image.id).toList(),
                      );
              if (context.mounted) {
                setState(() => images = fresh);
              }
              ref.invalidate(catalogProductsProvider);
            }

            return AlertDialog(
              title: Text('Medias - ${product.name}'),
              content: SizedBox(
                width: 720,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => upload(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Galerie'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => upload(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Camera'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (images.isEmpty)
                      const ListTile(
                        leading: Icon(Icons.image_not_supported_outlined),
                        title: Text('Aucune image'),
                      )
                    else
                      ...images.asMap().entries.map((entry) {
                        final index = entry.key;
                        final image = entry.value;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              image.urlThumbnail,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: Icon(Icons.broken_image_outlined),
                                );
                              },
                            ),
                          ),
                          title: Text(image.altText ?? 'Image #${image.id}'),
                          subtitle: Text(
                            '${image.format} - ${image.width}x${image.height}',
                          ),
                          trailing: Wrap(
                            spacing: 2,
                            children: [
                              IconButton(
                                tooltip: 'Monter',
                                onPressed:
                                    index == 0 ? null : () => move(index, -1),
                                icon: const Icon(Icons.arrow_upward),
                              ),
                              IconButton(
                                tooltip: 'Descendre',
                                onPressed: index == images.length - 1
                                    ? null
                                    : () => move(index, 1),
                                icon: const Icon(Icons.arrow_downward),
                              ),
                              IconButton(
                                tooltip: 'Image principale',
                                onPressed: image.isPrimary
                                    ? null
                                    : () async {
                                        await ref
                                            .read(catalogRepositoryProvider)
                                            .setPrimaryImage(
                                              imageId: image.id,
                                              entityType: 'products',
                                              entityId: product.id,
                                            );
                                        await refresh();
                                        ref.invalidate(catalogProductsProvider);
                                      },
                                icon: Icon(
                                  image.isPrimary
                                      ? Icons.star
                                      : Icons.star_border_outlined,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Supprimer',
                                onPressed: () async {
                                  await ref
                                      .read(catalogRepositoryProvider)
                                      .deleteImage(image.id);
                                  await refresh();
                                  ref.invalidate(catalogProductsProvider);
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fermer'),
                ),
              ],
            );
          },
        ),
      );
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _allergensDialog(CatalogProduct product) async {
    try {
      final repository = ref.read(catalogRepositoryProvider);
      final definitions = await repository.listAllergens();
      final tags = await repository.listDietaryTags();
      var summary = await repository.productAllergens(product.id);
      if (!mounted) {
        return;
      }
      int? selectedAllergenId =
          definitions.isEmpty ? null : definitions.first.id;
      var level = 'absent';
      final reason = TextEditingController();
      var selectedTags = summary.dietaryTags.map((tag) => tag.id).toSet();
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            Future<void> refreshSummary() async {
              final fresh = await repository.productAllergens(product.id);
              if (context.mounted) {
                setState(() {
                  summary = fresh;
                  selectedTags = fresh.dietaryTags.map((tag) => tag.id).toSet();
                });
              }
            }

            return AlertDialog(
              title: Text('Allergenes - ${product.name}'),
              content: SizedBox(
                width: 760,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: Icon(
                            summary.regulatoryComplete
                                ? Icons.verified_outlined
                                : Icons.warning_amber_outlined,
                          ),
                          label: Text(
                            summary.regulatoryComplete
                                ? 'Declaration complete'
                                : 'Declaration incomplete',
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await repository
                                .recomputeProductAllergens(product.id);
                            await refreshSummary();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Recalculer'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Declaration manuelle',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedAllergenId,
                            decoration:
                                const InputDecoration(labelText: 'Allergene'),
                            items: definitions
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item.id,
                                    child: Text(item.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setState(() {
                              selectedAllergenId = value;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            initialValue: level,
                            decoration:
                                const InputDecoration(labelText: 'Niveau'),
                            items: const [
                              DropdownMenuItem(
                                value: 'absent',
                                child: Text('Absent'),
                              ),
                              DropdownMenuItem(
                                value: 'traces',
                                child: Text('Traces'),
                              ),
                              DropdownMenuItem(
                                value: 'present',
                                child: Text('Present'),
                              ),
                            ],
                            onChanged: (value) => setState(() {
                              level = value ?? level;
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reason,
                      decoration: const InputDecoration(labelText: 'Raison'),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: selectedAllergenId == null
                            ? null
                            : () async {
                                await repository.patchProductAllergen(
                                  productId: product.id,
                                  allergenId: selectedAllergenId!,
                                  level: level,
                                  reason: reason.text,
                                );
                                reason.clear();
                                await refreshSummary();
                                ref.invalidate(catalogProductsProvider);
                              },
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Appliquer'),
                      ),
                    ),
                    const Divider(),
                    Text(
                      'Tags alimentaires',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tags.map((tag) {
                        final selected = selectedTags.contains(tag.id);
                        return FilterChip(
                          label: Text(tag.name),
                          selected: selected,
                          onSelected: (value) {
                            setState(() {
                              if (value) {
                                selectedTags.add(tag.id);
                              } else {
                                selectedTags.remove(tag.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          await repository.setProductDietaryTags(
                            productId: product.id,
                            tagIds: selectedTags.toList()..sort(),
                          );
                          await refreshSummary();
                          ref.invalidate(catalogProductsProvider);
                        },
                        icon: const Icon(Icons.label_outlined),
                        label: const Text('Enregistrer tags'),
                      ),
                    ),
                    const Divider(),
                    Text(
                      'Declarations',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (summary.allergens.isEmpty)
                      const ListTile(title: Text('Aucune declaration'))
                    else
                      ...summary.allergens.map((allergen) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(allergen.allergenName),
                          subtitle:
                              Text('${allergen.level} - ${allergen.source}'),
                          trailing: allergen.isRegulatory
                              ? const Icon(Icons.gpp_good_outlined)
                              : null,
                        );
                      }),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fermer'),
                ),
              ],
            );
          },
        ),
      );
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _completenessDialog() async {
    try {
      final value = await ref.read(catalogRepositoryProvider).completeness();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Produits incomplets'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Produits actifs'),
                  trailing: Text(value.totalProducts.toString()),
                ),
                ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('Complets'),
                  trailing: Text(value.completeProducts.toString()),
                ),
                ListTile(
                  leading: const Icon(Icons.report_problem_outlined),
                  title: const Text('Incomplets'),
                  trailing: Text(value.incompleteProducts.toString()),
                ),
                LinearProgressIndicator(value: value.completionPercent / 100),
                const SizedBox(height: 8),
                Text('${value.completionPercent.toStringAsFixed(2)} %'),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _importCsvDialog() async {
    final filename = TextEditingController(text: 'catalog.csv');
    final csv = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import catalogue CSV'),
        content: SizedBox(
          width: 720,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: filename,
                decoration: const InputDecoration(
                  labelText: 'Nom fichier',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: csv,
                decoration: const InputDecoration(
                  labelText: 'CSV',
                  alignLabelWithHint: true,
                ),
                minLines: 8,
                maxLines: 14,
                keyboardType: TextInputType.multiline,
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
            icon: const Icon(Icons.playlist_add_check_outlined),
            label: const Text('Dry-run'),
          ),
        ],
      ),
    );
    if (submitted != true) {
      return;
    }
    if (csv.text.trim().isEmpty) {
      _snack('CSV requis');
      return;
    }
    try {
      final dryRun = await ref.read(catalogRepositoryProvider).importCsvDryRun(
            csvText: csv.text,
            filename: filename.text,
          );
      if (!mounted) {
        return;
      }
      final confirm = await _showCsvDryRun(dryRun);
      if (confirm != true) {
        return;
      }
      final result = await ref
          .read(catalogRepositoryProvider)
          .importCsvConfirm(dryRun.token);
      ref.invalidate(catalogCategoriesProvider);
      ref.invalidate(catalogProductsProvider);
      if (!mounted) {
        return;
      }
      await _showCsvConfirm(result);
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<bool?> _showCsvDryRun(CatalogCsvDryRun dryRun) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(dryRun.valid ? 'Dry-run valide' : 'Dry-run invalide'),
        content: SizedBox(
          width: 620,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.table_rows_outlined),
                title: const Text('Lignes'),
                trailing: Text(dryRun.totalRows.toString()),
              ),
              if (dryRun.errors.isNotEmpty) ...[
                Text('Erreurs', style: Theme.of(context).textTheme.titleMedium),
                ...dryRun.errors.take(12).map((error) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.error_outline),
                    title: Text('Ligne ${error.row} - ${error.code}'),
                    subtitle: Text(error.detail),
                  );
                }),
              ],
              if (dryRun.previews.isNotEmpty) ...[
                Text('Apercu', style: Theme.of(context).textTheme.titleMedium),
                ...dryRun.previews.take(20).map((preview) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${preview.action} ${preview.entityType}'),
                    subtitle: Text('Ligne ${preview.row} - ${preview.key}'),
                  );
                }),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Fermer'),
          ),
          if (dryRun.valid)
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check),
              label: const Text('Confirmer'),
            ),
        ],
      ),
    );
  }

  Future<void> _showCsvConfirm(CatalogCsvConfirm result) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(result.imported ? 'Import termine' : 'Import non applique'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.table_rows_outlined),
                title: const Text('Lignes'),
                trailing: Text(result.totalRows.toString()),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('Crees'),
                trailing: Text(result.created.toString()),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Mis a jour'),
                trailing: Text(result.updated.toString()),
              ),
              ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text('Liens'),
                trailing: Text(result.linked.toString()),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _priceAuditDialog(String entityType, int entityId) async {
    try {
      final entries = await ref.read(catalogRepositoryProvider).priceAudit(
            entityType: entityType,
            entityId: entityId,
          );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Historique prix'),
          content: SizedBox(
            width: 620,
            child: entries.isEmpty
                ? const ListTile(title: Text('Aucun changement'))
                : ListView(
                    shrinkWrap: true,
                    children: entries.map((entry) {
                      final oldPrice = entry.oldPrice == null
                          ? '-'
                          : formatMoney(entry.oldPrice!);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.euro_outlined),
                        title:
                            Text('$oldPrice -> ${formatMoney(entry.newPrice)}'),
                        subtitle: Text(entry.reason ?? entry.source),
                        trailing: Text(formatDateTime(entry.changedAt)),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _recommendationDialog(CatalogProduct product) async {
    try {
      var recommendations = await ref
          .read(catalogRepositoryProvider)
          .listRecommendations(product.id);
      if (!mounted) {
        return;
      }
      final productId = TextEditingController();
      final displayOrder = TextEditingController(text: '0');
      final label = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text('Recommandations - ${product.name}'),
            content: SizedBox(
              width: 620,
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (recommendations.isEmpty)
                    const ListTile(title: Text('Aucune recommandation'))
                  else
                    ...recommendations.map((recommendation) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          recommendation.product?.name ??
                              'Produit #${recommendation.recommendedProductId}',
                        ),
                        subtitle: Text(recommendation.label ?? '-'),
                        trailing: IconButton(
                          tooltip: 'Retirer',
                          onPressed: () async {
                            await ref
                                .read(catalogRepositoryProvider)
                                .deleteRecommendation(
                                  productId: product.id,
                                  recommendationId: recommendation.id,
                                );
                            setState(() {
                              recommendations = recommendations
                                  .where((item) => item.id != recommendation.id)
                                  .toList();
                            });
                            ref.invalidate(catalogProductsProvider);
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      );
                    }),
                  const Divider(),
                  TextField(
                    controller: productId,
                    decoration: const InputDecoration(
                      labelText: 'ID produit recommande',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: displayOrder,
                    decoration: const InputDecoration(labelText: 'Ordre'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: label,
                    decoration: const InputDecoration(labelText: 'Libelle'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Fermer'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.add_link_outlined),
                label: const Text('Ajouter'),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true) {
        return;
      }
      final recommendedId = int.tryParse(productId.text.trim());
      if (recommendedId == null || recommendedId <= 0) {
        _snack('ID produit recommande requis');
        return;
      }
      await ref.read(catalogRepositoryProvider).addRecommendation(
            productId: product.id,
            recommendedProductId: recommendedId,
            displayOrder: int.tryParse(displayOrder.text.trim()) ?? 0,
            label: label.text,
          );
      ref.invalidate(catalogProductsProvider);
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _exportCsv() async {
    try {
      final csv = await ref.read(catalogRepositoryProvider).exportCsv();
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export catalogue CSV'),
          content: SizedBox(
            width: 720,
            child: SelectableText(csv),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      _snack(error.toString());
    }
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  double _double(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _ProductDetailHero extends StatelessWidget {
  const _ProductDetailHero({required this.detail});

  final CatalogProduct detail;

  @override
  Widget build(BuildContext context) {
    final available = catalogProductAvailable(detail);
    final imageUrl = catalogListImageUrl(detail);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4EC),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: const Color(0xFFD8D0C3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: imageUrl == null
                ? Container(
                    width: 92,
                    height: 92,
                    color: const Color(0xFFE8E2D8),
                    child: const Icon(Icons.restaurant_menu_outlined),
                  )
                : Image.network(
                    imageUrl,
                    width: 92,
                    height: 92,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 92,
                        height: 92,
                        color: const Color(0xFFE8E2D8),
                        child: const Icon(Icons.broken_image_outlined),
                      );
                    },
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                Text(
                  detail.categoryName ?? 'Sans categorie',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    StatusBadge(
                      label: available ? 'Disponible' : 'Indisponible',
                      tone: available ? StatusTone.success : StatusTone.danger,
                      compact: true,
                    ),
                    if (!detail.isActive)
                      const StatusBadge(
                        label: 'Inactif catalogue',
                        tone: StatusTone.neutral,
                        compact: true,
                      ),
                    _StationBadge(product: detail),
                    StatusBadge(
                      label:
                          detail.regulatoryComplete ? 'Conforme' : 'Incomplet',
                      tone: detail.regulatoryComplete
                          ? StatusTone.success
                          : StatusTone.warning,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  formatMoney(detail.basePrice),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Column(
        children: List.generate(
          5,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E2D8),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogContextPanel extends StatelessWidget {
  const _CatalogContextPanel({
    required this.products,
    required this.categories,
    required this.onIncomplete,
    required this.onEditCategory,
  });

  final List<CatalogProduct> products;
  final List<CatalogCategory> categories;
  final VoidCallback onIncomplete;
  final ValueChanged<CatalogCategory>? onEditCategory;

  @override
  Widget build(BuildContext context) {
    final incomplete = products
        .where((product) => !product.regulatoryComplete)
        .take(5)
        .toList();
    final unavailable = products
        .where((product) => !catalogProductAvailable(product))
        .take(4)
        .toList();
    final counts = catalogProductCountsByCategory(products);

    return Column(
      children: [
        DsCard(
          backgroundColor: const Color(0xFFF8F4EC),
          borderColor: const Color(0xFFD8D0C3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A traiter',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (incomplete.isEmpty)
                const StatusBadge(
                  label: 'Toutes les fiches sont conformes',
                  tone: StatusTone.success,
                  icon: Icons.check_circle_outline,
                )
              else ...[
                StatusBadge(
                  label: '${incomplete.length} fiche(s) incomplete(s)',
                  tone: StatusTone.warning,
                  icon: Icons.fact_check_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final product in incomplete)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.fact_check_outlined),
                    title: Text(product.name),
                    subtitle: Text(product.categoryName ?? 'Sans categorie'),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onIncomplete,
                    icon: const Icon(Icons.filter_alt_outlined),
                    label: const Text('Filtrer les incomplets'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DsCard(
          backgroundColor: const Color(0xFFF8F4EC),
          borderColor: const Color(0xFFD8D0C3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Disponibilites',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (unavailable.isEmpty)
                const StatusBadge(
                  label: 'Tout est disponible',
                  tone: StatusTone.success,
                  icon: Icons.visibility_outlined,
                )
              else
                for (final product in unavailable)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: Text(product.name),
                    subtitle: Text(
                      (product.availabilityReason ?? '').isEmpty
                          ? 'Sans raison renseignee'
                          : product.availabilityReason!,
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DsCard(
          backgroundColor: const Color(0xFFF8F4EC),
          borderColor: const Color(0xFFD8D0C3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Categories',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (categories.isEmpty)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.category_outlined),
                  title: Text('Aucune categorie'),
                )
              else
                for (final category in categories.take(6))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      category.isActive
                          ? Icons.category_outlined
                          : Icons.block_outlined,
                    ),
                    title: Text(category.name),
                    subtitle: Text(
                      '${catalogStationLabel(category.preparationStation)} - ${counts[category.id] ?? 0} produit(s)',
                    ),
                    trailing: onEditCategory == null
                        ? null
                        : IconButton(
                            tooltip: 'Modifier categorie',
                            onPressed: () => onEditCategory!(category),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CatalogHeader extends StatelessWidget {
  const _CatalogHeader({
    required this.isMobile,
    required this.canWrite,
    required this.onRefresh,
    required this.onCreateProduct,
    required this.onCreateCategory,
    required this.onImport,
    required this.onExport,
    required this.onCompleteness,
  });

  final bool isMobile;
  final bool canWrite;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreateProduct;
  final VoidCallback onCreateCategory;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onCompleteness;

  @override
  Widget build(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Catalogue',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Carte, disponibilites, stations et conformite menu',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );

    final actions = Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      alignment: WrapAlignment.end,
      children: [
        IconButton.filledTonal(
          tooltip: 'Rafraichir',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
        if (canWrite) ...[
          if (isMobile)
            PopupMenuButton<String>(
              tooltip: 'Actions catalogue',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'export':
                    onExport();
                  case 'import':
                    onImport();
                  case 'incomplete':
                    onCompleteness();
                  case 'category':
                    onCreateCategory();
                  case 'product':
                    onCreateProduct();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'product', child: Text('Produit')),
                PopupMenuItem(value: 'category', child: Text('Categorie')),
                PopupMenuItem(value: 'export', child: Text('Export CSV')),
                PopupMenuItem(value: 'import', child: Text('Import CSV')),
                PopupMenuItem(
                  value: 'incomplete',
                  child: Text('Produits incomplets'),
                ),
              ],
            )
          else ...[
            IconButton.filledTonal(
              tooltip: 'Export CSV',
              onPressed: onExport,
              icon: const Icon(Icons.download_outlined),
            ),
            IconButton.filledTonal(
              tooltip: 'Import CSV',
              onPressed: onImport,
              icon: const Icon(Icons.upload_file_outlined),
            ),
            IconButton.filledTonal(
              tooltip: 'Produits incomplets',
              onPressed: onCompleteness,
              icon: const Icon(Icons.fact_check_outlined),
            ),
            IconButton.filledTonal(
              tooltip: 'Categorie',
              onPressed: onCreateCategory,
              icon: const Icon(Icons.category_outlined),
            ),
            FilledButton.icon(
              onPressed: onCreateProduct,
              icon: const Icon(Icons.add),
              label: const Text('Produit'),
            ),
          ],
        ],
      ],
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: AppSpacing.md),
          actions,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: title),
        actions,
      ],
    );
  }
}

class _CatalogStatsRow extends StatelessWidget {
  const _CatalogStatsRow({
    required this.products,
    required this.categoryCount,
    required this.onFilter,
  });

  final List<CatalogProduct> products;
  final int? categoryCount;
  final ValueChanged<CatalogAvailabilityFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final unavailable =
        products.where((product) => !catalogProductAvailable(product)).length;
    final complete =
        products.where((product) => product.regulatoryComplete).length;
    final incomplete = products.length - complete;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _CatalogMetric(
          value: products.length.toString(),
          label: 'produits',
          icon: Icons.restaurant_menu_outlined,
          color: AppColors.accent,
          onTap: () => onFilter(CatalogAvailabilityFilter.all),
        ),
        _CatalogMetric(
          value: unavailable.toString(),
          label: 'indisponibles',
          icon: Icons.visibility_off_outlined,
          color: unavailable == 0 ? AppColors.success : AppColors.danger,
          onTap: () => onFilter(CatalogAvailabilityFilter.unavailable),
        ),
        _CatalogMetric(
          value: categoryCount?.toString() ?? '-',
          label: 'categories',
          icon: Icons.category_outlined,
          color: AppColors.infoAlt,
        ),
        _CatalogMetric(
          value: products.isEmpty
              ? '0%'
              : '${(complete * 100 / products.length).round()}%',
          label: incomplete == 0 ? 'conformes' : '$incomplete a corriger',
          icon: Icons.fact_check_outlined,
          color: incomplete == 0 ? AppColors.success : AppColors.warning,
          onTap: () => onFilter(CatalogAvailabilityFilter.incomplete),
        ),
      ],
    );
  }
}

class _CatalogMetric extends StatelessWidget {
  const _CatalogMetric({
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
      width: 170,
      child: DsCard(
        onTap: onTap,
        backgroundColor: const Color(0xFFF8F4EC),
        borderColor: const Color(0xFFD8D0C3),
        borderRadius: AppRadius.md,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
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

class _CatalogToolbar extends StatelessWidget {
  const _CatalogToolbar({
    required this.controller,
    required this.categories,
    required this.selectedCategoryId,
    required this.availabilityFilter,
    required this.onSearchChanged,
    required this.onCategorySelected,
    required this.onAvailabilitySelected,
    required this.onEditCategory,
  });

  final TextEditingController controller;
  final List<CatalogCategory> categories;
  final int? selectedCategoryId;
  final CatalogAvailabilityFilter availabilityFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int?> onCategorySelected;
  final ValueChanged<CatalogAvailabilityFilter> onAvailabilitySelected;
  final ValueChanged<CatalogCategory>? onEditCategory;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 360,
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Recherche produit',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: onSearchChanged,
                ),
              ),
              PillFilterBar<int?>(
                selected: selectedCategoryId,
                onSelected: onCategorySelected,
                options: [
                  const PillFilterOption<int?>(
                    value: null,
                    label: 'Toutes',
                    icon: Icons.widgets_outlined,
                  ),
                  for (final category in categories)
                    PillFilterOption<int?>(
                      value: category.id,
                      label: category.name,
                      icon: category.isActive
                          ? Icons.category_outlined
                          : Icons.block_outlined,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PillFilterBar<CatalogAvailabilityFilter>(
                selected: availabilityFilter,
                onSelected: onAvailabilitySelected,
                options: const [
                  PillFilterOption<CatalogAvailabilityFilter>(
                    value: CatalogAvailabilityFilter.all,
                    label: 'Tous',
                    icon: Icons.inventory_2_outlined,
                  ),
                  PillFilterOption<CatalogAvailabilityFilter>(
                    value: CatalogAvailabilityFilter.available,
                    label: 'Disponibles',
                    icon: Icons.visibility_outlined,
                  ),
                  PillFilterOption<CatalogAvailabilityFilter>(
                    value: CatalogAvailabilityFilter.unavailable,
                    label: 'Indisponibles',
                    icon: Icons.visibility_off_outlined,
                  ),
                  PillFilterOption<CatalogAvailabilityFilter>(
                    value: CatalogAvailabilityFilter.incomplete,
                    label: 'Incomplets',
                    icon: Icons.fact_check_outlined,
                  ),
                ],
              ),
              if (onEditCategory != null && categories.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    final selected = categories.firstWhere(
                      (category) => category.id == selectedCategoryId,
                      orElse: () => categories.first,
                    );
                    onEditCategory!(selected);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editer categorie'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductTable extends StatelessWidget {
  const _ProductTable({
    required this.products,
    required this.compactCards,
    required this.canWrite,
    required this.canManageAvailability,
    required this.busyIds,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onStation,
    required this.onAvailability,
  });

  final List<CatalogProduct> products;
  final bool compactCards;
  final bool canWrite;
  final bool canManageAvailability;
  final Set<int> busyIds;
  final ValueChanged<CatalogProduct> onOpen;
  final ValueChanged<CatalogProduct> onEdit;
  final ValueChanged<CatalogProduct> onDelete;
  final ValueChanged<CatalogProduct> onStation;
  final void Function(CatalogProduct product, bool available) onAvailability;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const DsCard(
        child: EmptyState(
          icon: Icons.inventory_2_outlined,
          title: 'Aucun produit',
          subtitle: 'Aucun produit ne correspond aux filtres actifs.',
        ),
      );
    }

    if (compactCards) {
      return Column(
        children: [
          for (final (index, product) in products.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _ProductCard(
                product: product,
                canWrite: canWrite,
                canManageAvailability: canManageAvailability,
                busy: busyIds.contains(product.id),
                onOpen: onOpen,
                onEdit: onEdit,
                onDelete: onDelete,
                onStation: onStation,
                onAvailability: onAvailability,
              ).staggeredEntrance(index),
            ),
        ],
      );
    }

    return DsCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth < 1180 ? 1180.0 : constraints.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  const _ProductTableHeader(),
                  const Divider(height: 1),
                  for (final (index, product) in products.indexed) ...[
                    _ProductTableRow(
                      product: product,
                      canWrite: canWrite,
                      canManageAvailability: canManageAvailability,
                      busy: busyIds.contains(product.id),
                      onOpen: onOpen,
                      onEdit: onEdit,
                      onDelete: onDelete,
                      onStation: onStation,
                      onAvailability: onAvailability,
                    ).staggeredEntrance(index),
                    const Divider(height: 1),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProductTableHeader extends StatelessWidget {
  const _ProductTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: const Row(
        children: [
          _TableLabel('Produit', width: 330),
          _TableLabel('Categorie', width: 150),
          _TableLabel('Prix', width: 100),
          _TableLabel('Station', width: 130),
          _TableLabel('Disponibilite', width: 170),
          _TableLabel('Fiche', width: 130),
          Expanded(child: _TableLabel('Actions')),
        ],
      ),
    );
  }
}

class _ProductTableRow extends StatelessWidget {
  const _ProductTableRow({
    required this.product,
    required this.canWrite,
    required this.canManageAvailability,
    required this.busy,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onStation,
    required this.onAvailability,
  });

  final CatalogProduct product;
  final bool canWrite;
  final bool canManageAvailability;
  final bool busy;
  final ValueChanged<CatalogProduct> onOpen;
  final ValueChanged<CatalogProduct> onEdit;
  final ValueChanged<CatalogProduct> onDelete;
  final ValueChanged<CatalogProduct> onStation;
  final void Function(CatalogProduct product, bool available) onAvailability;

  @override
  Widget build(BuildContext context) {
    final available = catalogProductAvailable(product);
    return InkWell(
      onTap: () => onOpen(product),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 330,
              child: Row(
                children: [
                  _ProductThumb(product: product, available: available),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          product.description?.isNotEmpty == true
                              ? product.description!
                              : '#${product.id}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 150,
              child: Text(
                product.categoryName ?? 'Sans categorie',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: 100, child: Text(formatMoney(product.basePrice))),
            SizedBox(
              width: 130,
              child: _StationBadge(product: product),
            ),
            SizedBox(
              width: 170,
              child: StatusBadge(
                label: available ? 'Disponible' : 'Indisponible',
                tone: available ? StatusTone.success : StatusTone.danger,
                icon: available
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                compact: true,
              ),
            ),
            SizedBox(
              width: 130,
              child: StatusBadge(
                label: product.regulatoryComplete ? 'Complete' : 'A completer',
                tone: product.regulatoryComplete
                    ? StatusTone.success
                    : StatusTone.warning,
                compact: true,
              ),
            ),
            Expanded(
              child: _ProductActions(
                product: product,
                canWrite: canWrite,
                canManageAvailability: canManageAvailability,
                busy: busy,
                onOpen: onOpen,
                onEdit: onEdit,
                onDelete: onDelete,
                onStation: onStation,
                onAvailability: onAvailability,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.canWrite,
    required this.canManageAvailability,
    required this.busy,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onStation,
    required this.onAvailability,
  });

  final CatalogProduct product;
  final bool canWrite;
  final bool canManageAvailability;
  final bool busy;
  final ValueChanged<CatalogProduct> onOpen;
  final ValueChanged<CatalogProduct> onEdit;
  final ValueChanged<CatalogProduct> onDelete;
  final ValueChanged<CatalogProduct> onStation;
  final void Function(CatalogProduct product, bool available) onAvailability;

  @override
  Widget build(BuildContext context) {
    final available = catalogProductAvailable(product);
    return DsCard(
      onTap: () => onOpen(product),
      backgroundColor: const Color(0xFFFCF8F0),
      borderColor: const Color(0xFFD8D0C3),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ProductThumb(product: product, available: available),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      product.categoryName ?? 'Sans categorie',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                formatMoney(product.basePrice),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              StatusBadge(
                label: available ? 'Disponible' : 'Indisponible',
                tone: available ? StatusTone.success : StatusTone.danger,
                compact: true,
              ),
              if (!product.isActive)
                const StatusBadge(
                  label: 'Inactif',
                  tone: StatusTone.neutral,
                  compact: true,
                ),
              _StationBadge(product: product),
              StatusBadge(
                label: product.regulatoryComplete ? 'Conforme' : 'Incomplet',
                tone: product.regulatoryComplete
                    ? StatusTone.success
                    : StatusTone.warning,
                compact: true,
              ),
            ],
          ),
          if ((product.availabilityReason ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              product.availabilityReason!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _ProductActions(
            product: product,
            canWrite: canWrite,
            canManageAvailability: canManageAvailability,
            busy: busy,
            onOpen: onOpen,
            onEdit: onEdit,
            onDelete: onDelete,
            onStation: onStation,
            onAvailability: onAvailability,
          ),
        ],
      ),
    );
  }
}

class _ProductActions extends StatelessWidget {
  const _ProductActions({
    required this.product,
    required this.canWrite,
    required this.canManageAvailability,
    required this.busy,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onStation,
    required this.onAvailability,
  });

  final CatalogProduct product;
  final bool canWrite;
  final bool canManageAvailability;
  final bool busy;
  final ValueChanged<CatalogProduct> onOpen;
  final ValueChanged<CatalogProduct> onEdit;
  final ValueChanged<CatalogProduct> onDelete;
  final ValueChanged<CatalogProduct> onStation;
  final void Function(CatalogProduct product, bool available) onAvailability;

  @override
  Widget build(BuildContext context) {
    final available = catalogProductAvailable(product);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      alignment: WrapAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: () => onOpen(product),
          icon: const Icon(Icons.open_in_new_outlined),
          label: const Text('Ouvrir'),
        ),
        if (canManageAvailability)
          FilledButton.tonalIcon(
            onPressed: busy ? null : () => onAvailability(product, !available),
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    available
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
            label: Text(available ? 'Indispo' : 'Dispo'),
          ),
        if (canWrite)
          PopupMenuButton<_ProductAction>(
            key: ValueKey('catalog-product-actions-${product.id}'),
            tooltip: 'Actions produit',
            onSelected: (action) {
              switch (action) {
                case _ProductAction.edit:
                  onEdit(product);
                case _ProductAction.station:
                  onStation(product);
                case _ProductAction.delete:
                  onDelete(product);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ProductAction.edit,
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Modifier'),
                ),
              ),
              PopupMenuItem(
                value: _ProductAction.station,
                child: ListTile(
                  leading: Icon(Icons.restaurant_menu_outlined),
                  title: Text('Station'),
                ),
              ),
              PopupMenuItem(
                value: _ProductAction.delete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Supprimer'),
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

enum _ProductAction { edit, station, delete }

class _StationBadge extends StatelessWidget {
  const _StationBadge({required this.product});

  final CatalogProduct product;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          'Station effective : ${catalogStationLabel(product.effectivePreparationStation)} - Source : ${catalogStationSource(product)}',
      child: StatusBadge(
        label: catalogStationLabel(product.effectivePreparationStation),
        tone: _stationTone(product.effectivePreparationStation),
        compact: true,
      ),
    );
  }
}

StatusTone _stationTone(String value) {
  return switch (value) {
    'kitchen' => StatusTone.info,
    'counter' => StatusTone.neutral,
    'none' => StatusTone.warning,
    _ => StatusTone.neutral,
  };
}

class _TableLabel extends StatelessWidget {
  const _TableLabel(this.label, {this.width});

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

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({
    required this.product,
    required this.available,
  });

  final CatalogProduct product;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final url = catalogListImageUrl(product);
    if (url == null || url.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFE8E2D8),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: const Color(0xFFD8D0C3)),
        ),
        child: Icon(
          Icons.restaurant_menu_outlined,
          color: available ? AppColors.infoAlt : AppColors.textSecondary,
        ),
      );
    }
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.broken_image_outlined),
              );
            },
          ),
        ),
        Icon(
          available ? Icons.check_circle : Icons.pause_circle,
          size: 16,
          color: available
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
      ],
    );
  }
}
