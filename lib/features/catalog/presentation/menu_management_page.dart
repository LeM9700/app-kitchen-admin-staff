import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/catalog/data/menu_models.dart';
import 'package:app_admin_staff/features/catalog/data/menu_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MenuManagementPage extends ConsumerStatefulWidget {
  const MenuManagementPage({super.key});

  @override
  ConsumerState<MenuManagementPage> createState() =>
      _MenuManagementPageState();
}

class _MenuManagementPageState extends ConsumerState<MenuManagementPage> {
  int? _selectedMenuId;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final menus = ref.watch(adminMenusProvider);
    final products = ref.watch(catalogProductsProvider);
    final permissionSet = ref.watch(currentPermissionSetProvider);
    final canWrite = permissionSet.can(AppPermission.catalogWrite);

    return Scaffold(
      backgroundColor: AppColors.adminBackground,
      appBar: AppBar(
        title: const Text('Menus'),
        actions: [
          IconButton(
            tooltip: 'Rafraichir',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (canWrite)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: FilledButton.icon(
                onPressed: _busy ? null : _createMenu,
                icon: const Icon(Icons.add),
                label: const Text('Nouveau menu'),
              ),
            ),
        ],
      ),
      body: menus.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _LoadFailure(
          message: error.toString(),
          onRetry: _refresh,
        ),
        data: (items) {
          if (items.isEmpty) {
            return _MenuEmptyState(
              canWrite: canWrite,
              onCreate: _createMenu,
            );
          }
          final selected = _selectedMenu(items);
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 820) {
                return _buildCompact(items, selected, products, canWrite);
              }
              return _buildWide(items, selected, products, canWrite);
            },
          );
        },
      ),
    );
  }

  MenuAdmin _selectedMenu(List<MenuAdmin> menus) {
    return menus.firstWhere(
      (menu) => menu.id == _selectedMenuId,
      orElse: () => menus.first,
    );
  }

  Widget _buildWide(
    List<MenuAdmin> menus,
    MenuAdmin selected,
    AsyncValue<List<CatalogProduct>> products,
    bool canWrite,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          child: _MenuRail(
            menus: menus,
            selectedId: selected.id,
            onSelected: (id) => setState(() => _selectedMenuId = id),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _MenuWorkspace(
            key: ValueKey('${selected.id}-${selected.updatedKey}'),
            menu: selected,
            products: products.valueOrNull ?? const [],
            canWrite: canWrite,
            busy: _busy,
            onEdit: () => _editMenu(selected),
            onDelete: () => _deleteMenu(selected),
            onTogglePublished: () => _togglePublished(selected),
            onAddGroup: () => _createGroup(selected),
            onEditGroup: (group) => _editGroup(selected, group),
            onDeleteGroup: (group) => _deleteGroup(selected, group),
            onAddProduct: (group) => _addProduct(selected, group),
            onRemoveProduct: (group, item) =>
                _removeProduct(selected, group, item),
          ),
        ),
      ],
    );
  }

  Widget _buildCompact(
    List<MenuAdmin> menus,
    MenuAdmin selected,
    AsyncValue<List<CatalogProduct>> products,
    bool canWrite,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: DropdownButtonFormField<int>(
            initialValue: selected.id,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Menu a modifier',
              prefixIcon: Icon(Icons.restaurant_menu),
            ),
            items: menus
                .map(
                  (menu) => DropdownMenuItem(
                    value: menu.id,
                    child: Text(menu.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _selectedMenuId = value),
          ),
        ),
        Expanded(
          child: _MenuWorkspace(
            key: ValueKey('${selected.id}-${selected.updatedKey}'),
            menu: selected,
            products: products.valueOrNull ?? const [],
            canWrite: canWrite,
            busy: _busy,
            compact: true,
            onEdit: () => _editMenu(selected),
            onDelete: () => _deleteMenu(selected),
            onTogglePublished: () => _togglePublished(selected),
            onAddGroup: () => _createGroup(selected),
            onEditGroup: (group) => _editGroup(selected, group),
            onDeleteGroup: (group) => _deleteGroup(selected, group),
            onAddProduct: (group) => _addProduct(selected, group),
            onRemoveProduct: (group, item) =>
                _removeProduct(selected, group, item),
          ),
        ),
      ],
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(adminMenusProvider);
    ref.invalidate(catalogProductsProvider);
    try {
      await Future.wait([
        ref.read(adminMenusProvider.future),
        ref.read(catalogProductsProvider.future),
      ]);
    } catch (_) {
      // The provider renders the actionable error state.
    }
  }

  Future<void> _createMenu() async {
    final draft = await showDialog<MenuDraft>(
      context: context,
      builder: (context) => const _MenuDetailsDialog(),
    );
    if (draft == null) return;
    await _runMutation(
      () => ref.read(menuRepositoryProvider).createMenu(draft),
      success: 'Menu cree. Ajoutez ses groupes avant de le publier.',
    );
  }

  Future<void> _editMenu(MenuAdmin menu) async {
    final draft = await showDialog<MenuDraft>(
      context: context,
      builder: (context) => _MenuDetailsDialog(menu: menu),
    );
    if (draft == null) return;
    await _runMutation(
      () => ref.read(menuRepositoryProvider).updateMenu(menu.id, draft),
      success: 'Menu enregistre.',
    );
  }

  Future<void> _togglePublished(MenuAdmin menu) async {
    if (!menu.isActive && !menu.isPublishable) return;
    final publish = !menu.isActive;
    final draft = MenuDraft(
      name: menu.name,
      description: menu.description,
      fixedPrice: menu.fixedPrice,
      imageUrl: menu.imageUrl,
      displayOrder: menu.displayOrder,
      isActive: publish,
      changeReason: publish ? 'Publication depuis admin staff' : 'Depublication depuis admin staff',
    );
    await _runMutation(
      () => ref.read(menuRepositoryProvider).updateMenu(menu.id, draft),
      success: publish ? 'Menu publie.' : 'Menu depublie.',
    );
  }

  Future<void> _deleteMenu(MenuAdmin menu) async {
    if (!await _confirm(
      title: 'Supprimer ${menu.name} ?',
      message: 'Le menu sera retire du catalogue. Les commandes passees gardent leur historique.',
      actionLabel: 'Supprimer',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(menuRepositoryProvider).deleteMenu(menu.id);
      _selectedMenuId = null;
      ref.invalidate(adminMenusProvider);
      await ref.read(adminMenusProvider.future);
      _snack('Menu supprime.');
    } catch (error) {
      _snack(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createGroup(MenuAdmin menu) async {
    final draft = await showDialog<MenuGroupDraft>(
      context: context,
      builder: (context) => _GroupDialog(nextOrder: menu.groups.length),
    );
    if (draft == null) return;
    await _runMutation(
      () => ref.read(menuRepositoryProvider).createGroup(menu.id, draft),
      success: 'Groupe ajoute.',
      wasActive: menu.isActive,
    );
  }

  Future<void> _editGroup(MenuAdmin menu, MenuGroupAdmin group) async {
    final draft = await showDialog<MenuGroupDraft>(
      context: context,
      builder: (context) => _GroupDialog(group: group),
    );
    if (draft == null) return;
    await _runMutation(
      () => ref.read(menuRepositoryProvider).updateGroup(menu.id, group.id, draft),
      success: 'Groupe enregistre.',
      wasActive: menu.isActive,
    );
  }

  Future<void> _deleteGroup(MenuAdmin menu, MenuGroupAdmin group) async {
    if (!await _confirm(
      title: 'Supprimer ${group.name} ?',
      message: 'Les produits de ce groupe seront retires du menu.',
      actionLabel: 'Supprimer',
    )) {
      return;
    }
    await _runMutation(
      () => ref.read(menuRepositoryProvider).deleteGroup(menu.id, group.id),
      success: 'Groupe supprime.',
      wasActive: menu.isActive,
    );
  }

  Future<void> _addProduct(MenuAdmin menu, MenuGroupAdmin group) async {
    final allProducts = await ref.read(catalogProductsProvider.future);
    if (!mounted) return;
    final selected = await showDialog<CatalogProduct>(
      context: context,
      builder: (context) => _ProductPickerDialog(
        products: allProducts,
        excludedProductIds: group.items.map((item) => item.productId).toSet(),
      ),
    );
    if (selected == null) return;
    await _runMutation(
      () => ref.read(menuRepositoryProvider).addProduct(
            menu.id,
            group.id,
            selected.id,
            displayOrder: group.items.length,
          ),
      success: '${selected.name} ajoute.',
      wasActive: menu.isActive,
    );
  }

  Future<void> _removeProduct(
    MenuAdmin menu,
    MenuGroupAdmin group,
    MenuGroupItemAdmin item,
  ) async {
    await _runMutation(
      () => ref.read(menuRepositoryProvider).removeProduct(
            menu.id,
            group.id,
            item.id,
          ),
      success: '${item.productName} retire.',
      wasActive: menu.isActive,
    );
  }

  Future<void> _runMutation(
    Future<MenuAdmin> Function() action, {
    required String success,
    bool wasActive = false,
  }) async {
    setState(() => _busy = true);
    try {
      final updated = await action();
      _selectedMenuId = updated.id;
      ref.invalidate(adminMenusProvider);
      await ref.read(adminMenusProvider.future);
      final autoUnpublished = wasActive && !updated.isActive;
      _snack(autoUnpublished ? '$success Le menu a ete depublie pour verification.' : success);
    } catch (error) {
      _snack(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String actionLabel,
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
                child: Text(actionLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.dangerAlt : null,
      ),
    );
  }
}

extension on MenuAdmin {
  String get updatedKey =>
      '$isActive-$isPublishable-${groups.length}-$productCount';
}

class _MenuRail extends StatelessWidget {
  const _MenuRail({
    required this.menus,
    required this.selectedId,
    required this.onSelected,
  });

  final List<MenuAdmin> menus;
  final int selectedId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: menus.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) {
        final menu = menus[index];
        final selected = menu.id == selectedId;
        return Material(
          color: selected ? AppColors.infoBg : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: ListTile(
            selected: selected,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(
                color: selected ? AppColors.infoAlt : AppColors.adminBorder,
              ),
            ),
            title: Text(
              menu.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${formatMoney(menu.fixedPrice)} · ${menu.groups.length} groupes',
            ),
            trailing: Icon(
              menu.isActive ? Icons.visibility : Icons.visibility_off_outlined,
              color: menu.isActive ? AppColors.success : AppColors.neutral,
            ),
            onTap: () => onSelected(menu.id),
          ),
        );
      },
    );
  }
}

class _MenuWorkspace extends StatelessWidget {
  const _MenuWorkspace({
    required this.menu,
    required this.products,
    required this.canWrite,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePublished,
    required this.onAddGroup,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.onAddProduct,
    required this.onRemoveProduct,
    this.compact = false,
    super.key,
  });

  final MenuAdmin menu;
  final List<CatalogProduct> products;
  final bool canWrite;
  final bool busy;
  final bool compact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePublished;
  final VoidCallback onAddGroup;
  final ValueChanged<MenuGroupAdmin> onEditGroup;
  final ValueChanged<MenuGroupAdmin> onDeleteGroup;
  final ValueChanged<MenuGroupAdmin> onAddProduct;
  final void Function(MenuGroupAdmin, MenuGroupItemAdmin) onRemoveProduct;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSidePreview = !compact && constraints.maxWidth >= 1040;
        final editor = ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            _MenuSummary(
              menu: menu,
              canWrite: canWrite,
              busy: busy,
              onEdit: onEdit,
              onDelete: onDelete,
              onTogglePublished: onTogglePublished,
            ),
            if (menu.validationErrors.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _ValidationPanel(errors: menu.validationErrors),
            ],
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Groupes de choix',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                if (canWrite)
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : onAddGroup,
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter un groupe'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (menu.groups.isEmpty)
              const _InlineEmpty(
                icon: Icons.view_list_outlined,
                title: 'Aucun groupe',
                message: 'Ajoutez au moins un groupe obligatoire.',
              )
            else
              ...menu.groups.map(
                (group) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _GroupCard(
                    group: group,
                    canWrite: canWrite,
                    busy: busy,
                    onEdit: () => onEditGroup(group),
                    onDelete: () => onDeleteGroup(group),
                    onAddProduct: () => onAddProduct(group),
                    onRemoveProduct: (item) => onRemoveProduct(group, item),
                  ),
                ),
              ),
            if (!showSidePreview) ...[
              const SizedBox(height: AppSpacing.md),
              _MenuPreview(menu: menu),
            ],
          ],
        );
        if (!showSidePreview) return editor;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: editor),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 340,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: _MenuPreview(menu: menu),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MenuSummary extends StatelessWidget {
  const _MenuSummary({
    required this.menu,
    required this.canWrite,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePublished,
  });

  final MenuAdmin menu;
  final bool canWrite;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePublished;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              menu.name,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            StatusBadge(
              label: menu.isActive ? 'Publie' : 'Brouillon',
              tone: menu.isActive ? StatusTone.success : StatusTone.neutral,
              icon: menu.isActive ? Icons.visibility : Icons.edit_outlined,
            ),
            StatusBadge(
              label: menu.isPublishable ? 'Pret' : 'A completer',
              tone: menu.isPublishable ? StatusTone.info : StatusTone.warning,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          menu.description?.trim().isNotEmpty == true
              ? menu.description!
              : 'Aucune description.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            _Fact(icon: Icons.euro, label: formatMoney(menu.fixedPrice)),
            _Fact(
              icon: Icons.view_list_outlined,
              label: '${menu.groups.length} groupes',
            ),
            _Fact(
              icon: Icons.inventory_2_outlined,
              label: '${menu.productCount} produits',
            ),
          ],
        ),
        if (canWrite) ...[
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              FilledButton.icon(
                onPressed: busy || (!menu.isActive && !menu.isPublishable)
                    ? null
                    : onTogglePublished,
                icon: Icon(
                  menu.isActive ? Icons.visibility_off : Icons.publish,
                ),
                label: Text(menu.isActive ? 'Depublier' : 'Publier'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modifier'),
              ),
              IconButton(
                tooltip: 'Supprimer le menu',
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.canWrite,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onAddProduct,
    required this.onRemoveProduct,
  });

  final MenuGroupAdmin group;
  final bool canWrite;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddProduct;
  final ValueChanged<MenuGroupItemAdmin> onRemoveProduct;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      borderRadius: AppRadius.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      group.minChoices == group.maxChoices
                          ? '${group.minChoices} choix requis'
                          : '${group.minChoices} a ${group.maxChoices} choix',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (canWrite) ...[
                IconButton(
                  tooltip: 'Modifier le groupe',
                  onPressed: busy ? null : onEdit,
                  icon: const Icon(Icons.tune),
                ),
                IconButton(
                  tooltip: 'Supprimer le groupe',
                  onPressed: busy ? null : onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
          const Divider(),
          if (group.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text('Aucun produit dans ce groupe.'),
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: group.items
                  .map(
                    (item) => InputChip(
                      avatar: Icon(
                        item.isPosManaged ? Icons.sync : Icons.inventory_2_outlined,
                        size: 18,
                      ),
                      label: Text(
                        item.isPosManaged
                            ? '${item.productName} · POS'
                            : item.productName,
                      ),
                      tooltip: item.isPosManaged
                          ? 'Produit synchronise, donnees produit non modifiables ici'
                          : null,
                      onDeleted: canWrite && !busy
                          ? () => onRemoveProduct(item)
                          : null,
                    ),
                  )
                  .toList(),
            ),
          if (canWrite) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: busy ? null : onAddProduct,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter des produits'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuPreview extends StatelessWidget {
  const _MenuPreview({required this.menu});

  final MenuAdmin menu;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      borderRadius: AppRadius.md,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (menu.imageUrl != null && menu.imageUrl!.trim().isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                menu.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _PreviewImageFallback(),
              ),
            )
          else
            const AspectRatio(
              aspectRatio: 16 / 9,
              child: _PreviewImageFallback(),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Apercu client',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.infoAlt,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  menu.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  formatMoney(menu.fixedPrice),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                if ((menu.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(menu.description!),
                ],
                const SizedBox(height: AppSpacing.md),
                ...menu.groups.map(
                  (group) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          group.items.isEmpty
                              ? 'Aucun choix disponible'
                              : group.items.map((item) => item.productName).join(', '),
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
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

class _PreviewImageFallback extends StatelessWidget {
  const _PreviewImageFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.adminSurfaceMuted,
      child: Center(
        child: Icon(Icons.restaurant_menu, size: 48, color: AppColors.neutral),
      ),
    );
  }
}

class _ValidationPanel extends StatelessWidget {
  const _ValidationPanel({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningSoftBg,
        border: Border.all(color: AppColors.warning),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.warning),
              SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Avant publication',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ...errors.map((error) => Text('• $error')),
        ],
      ),
    );
  }
}

class _MenuDetailsDialog extends StatefulWidget {
  const _MenuDetailsDialog({this.menu});

  final MenuAdmin? menu;

  @override
  State<_MenuDetailsDialog> createState() => _MenuDetailsDialogState();
}

class _MenuDetailsDialogState extends State<_MenuDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _image;
  late final TextEditingController _displayOrder;

  @override
  void initState() {
    super.initState();
    final menu = widget.menu;
    _name = TextEditingController(text: menu?.name ?? '');
    _description = TextEditingController(text: menu?.description ?? '');
    _price = TextEditingController(text: menu?.fixedPrice.toString() ?? '');
    _image = TextEditingController(text: menu?.imageUrl ?? '');
    _displayOrder = TextEditingController(text: '${menu?.displayOrder ?? 0}');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _image.dispose();
    _displayOrder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.menu == null ? 'Nouveau menu' : 'Modifier le menu'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nom',
                    prefixIcon: Icon(Icons.restaurant_menu),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Le nom est obligatoire.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    prefixIcon: Icon(Icons.notes),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Prix fixe',
                          prefixIcon: Icon(Icons.euro),
                        ),
                        validator: (value) {
                          final price = double.tryParse((value ?? '').replaceAll(',', '.'));
                          return price == null || price < 0 ? 'Prix invalide.' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 150,
                      child: TextFormField(
                        controller: _displayOrder,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Ordre'),
                        validator: (value) {
                          final order = int.tryParse(value ?? '');
                          return order == null || order < 0 ? 'Ordre invalide.' : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _image,
                  decoration: const InputDecoration(
                    labelText: 'Image URL',
                    prefixIcon: Icon(Icons.image_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.menu == null ? 'Creer' : 'Enregistrer'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      MenuDraft(
        name: _name.text,
        description: _description.text,
        fixedPrice: double.parse(_price.text.replaceAll(',', '.')),
        imageUrl: _image.text,
        displayOrder: int.parse(_displayOrder.text),
        isActive: widget.menu?.isActive ?? false,
      ),
    );
  }
}

class _GroupDialog extends StatefulWidget {
  const _GroupDialog({this.group, this.nextOrder = 0});

  final MenuGroupAdmin? group;
  final int nextOrder;

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late int _min;
  late int _max;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.group?.name ?? '');
    _min = widget.group?.minChoices ?? 1;
    _max = widget.group?.maxChoices ?? 1;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.group == null ? 'Ajouter un groupe' : 'Modifier le groupe'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nom du groupe',
                  hintText: 'Pizza, boisson, dessert...',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Le nom est obligatoire.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _ChoiceStepper(
                      label: 'Minimum',
                      value: _min,
                      onChanged: (value) => setState(() {
                        _min = value;
                        if (_max < _min) _max = _min;
                      }),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _ChoiceStepper(
                      label: 'Maximum',
                      value: _max,
                      minimum: _min,
                      onChanged: (value) => setState(() => _max = value),
                    ),
                  ),
                ],
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
            Navigator.pop(
              context,
              MenuGroupDraft(
                name: _name.text,
                minChoices: _min,
                maxChoices: _max,
                displayOrder: widget.group?.displayOrder ?? widget.nextOrder,
              ),
            );
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _ChoiceStepper extends StatelessWidget {
  const _ChoiceStepper({
    required this.label,
    required this.value,
    required this.onChanged,
    this.minimum = 1,
  });

  final String label;
  final int value;
  final int minimum;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            IconButton.outlined(
              tooltip: 'Diminuer',
              onPressed: value > minimum ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton.outlined(
              tooltip: 'Augmenter',
              onPressed: value < 20 ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({
    required this.products,
    required this.excludedProductIds,
  });

  final List<CatalogProduct> products;
  final Set<int> excludedProductIds;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final products = widget.products
        .where((product) => !widget.excludedProductIds.contains(product.id))
        .where(
          (product) => product.name.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return AlertDialog(
      title: const Text('Ajouter un produit'),
      content: SizedBox(
        width: 600,
        height: 520,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Rechercher par nom',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: products.isEmpty
                  ? const _InlineEmpty(
                      icon: Icons.search_off,
                      title: 'Aucun produit',
                      message: 'Modifiez la recherche ou choisissez un autre groupe.',
                    )
                  : ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        final available = product.available ?? product.isActive;
                        return ListTile(
                          leading: Icon(
                            available ? Icons.check_circle_outline : Icons.block,
                            color: available ? AppColors.success : AppColors.danger,
                          ),
                          title: Text(product.name),
                          subtitle: Text(
                            [
                              product.categoryName ?? 'Sans categorie',
                              formatMoney(product.basePrice),
                              if (!product.regulatoryComplete) 'Conformite a completer',
                              if (!available)
                                product.availabilityReason ?? 'Indisponible',
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          enabled: product.isActive,
                          trailing: const Icon(Icons.add),
                          onTap: product.isActive
                              ? () => Navigator.pop(context, product)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xxs),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.neutral),
          const SizedBox(height: AppSpacing.xs),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.xxs),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _MenuEmptyState extends StatelessWidget {
  const _MenuEmptyState({required this.canWrite, required this.onCreate});

  final bool canWrite;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.restaurant_menu,
                size: 44,
                color: AppColors.neutral,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Aucun menu',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                canWrite
                    ? 'Creez une formule, ajoutez ses groupes puis publiez-la.'
                    : 'Aucun menu configure pour le moment.',
                textAlign: TextAlign.center,
              ),
              if (canWrite) ...[
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('Creer un menu'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 44, color: AppColors.danger),
          const SizedBox(height: AppSpacing.sm),
          const Text('Menus indisponibles'),
          const SizedBox(height: AppSpacing.xs),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reessayer'),
          ),
        ],
      ),
    );
  }
}
