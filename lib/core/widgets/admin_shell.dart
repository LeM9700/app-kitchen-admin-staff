import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/app/navigation/navigation_capabilities.dart';
import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:app_admin_staff/app/service_mode.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/core/offline/sync_worker.dart';
import 'package:app_admin_staff/core/realtime/notification_bus.dart';
import 'package:app_admin_staff/design_system/theme/api_kitchen_theme.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_elevation.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/establishments/application/establishment_invalidation.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdminShell extends ConsumerWidget {
  const AdminShell({
    required this.location,
    required this.child,
    super.key,
  });

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(currentPermissionSetProvider);
    final isAdmin =
        permissions.role == 'admin' || permissions.role == 'super-admin';
    final destinations = visibleNavigationFor(permissions)
        .map(_ShellDestination.fromCapability)
        .toList();
    final selectedIndex = _selectedIndex(destinations, location);

    // ── Auto-flush : déclenche la synchronisation au retour réseau ────────────
    // [⚡ PERF] Le flush ne se déclenche que lors d'une transition offline→online,
    // pas à chaque rebuild. Si la queue est vide, aucun appel réseau n'est émis.
    ref.listen<AsyncValue<bool>>(onlineStatusProvider, (previous, next) {
      final wasOffline = !(previous?.valueOrNull ?? true);
      final isNowOnline = next.valueOrNull ?? false;
      if (wasOffline && isNowOnline) {
        final queue = ref.read(syncQueueProvider);
        if (queue.isNotEmpty) {
          ref.read(syncWorkerProvider).flush(queue);
        }
      }
    });

    if (Breakpoints.isMobile(context)) {
      if (!isAdmin) {
        return _StaffMobileShell(
          destinations: _staffMobileDestinations(destinations),
          location: location,
          child: child,
        );
      }
      return _AdminMobileShell(
        destinations: destinations,
        selectedIndex: selectedIndex,
        child: child,
      );
    }

    return _KitchenDesktopShell(
      destinations: destinations,
      selectedIndex: selectedIndex,
      child: child,
    );
  }

  int _selectedIndex(List<_ShellDestination> destinations, String path) {
    if (destinations.isEmpty) {
      return 0;
    }
    final index = destinations.indexWhere((item) => path.startsWith(item.path));
    return index < 0 ? 0 : index;
  }
}

class _KitchenDesktopShell extends StatelessWidget {
  const _KitchenDesktopShell({
    required this.destinations,
    required this.selectedIndex,
    required this.child,
  });

  final List<_ShellDestination> destinations;
  final int selectedIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.adminBackground,
      body: SafeArea(
        child: Column(
          children: [
            const _KitchenTopBar(),
            _KitchenModuleBar(
              destinations: destinations,
              selectedIndex: selectedIndex,
            ),
            Expanded(
              child: ColoredBox(
                color: AppColors.adminBackground,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KitchenTopBar extends ConsumerWidget {
  const _KitchenTopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).valueOrNull;
    final user = session?.user;
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.adminSurface,
        border: const Border(
          bottom: BorderSide(color: AppColors.adminBorder),
        ),
        boxShadow:
            AppElevation.raisedSm(AppColors.adminSurface, intensity: .35),
      ),
      child: Row(
        children: [
          const _KitchenBrandMark(),
          const SizedBox(width: AppSpacing.lg),
          const SizedBox(width: 280, child: _KitchenTenantSwitcher()),
          const SizedBox(width: AppSpacing.lg),
          const Expanded(child: _KitchenGlobalSearch()),
          const SizedBox(width: AppSpacing.lg),
          const _ShellStatusActions(),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {},
            icon: const Icon(Icons.notifications_outlined),
          ),
          const _ServiceModeButton(),
          const SizedBox(width: AppSpacing.xs),
          Tooltip(
            message: user?.email ?? 'Utilisateur',
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.neutralBg,
              foregroundColor: AppColors.textPrimary,
              child: Text(
                _initialsFor(user?.fullName ?? user?.email ?? 'K'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KitchenBrandMark extends StatelessWidget {
  const _KitchenBrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.adminSurface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.adminBorder),
            boxShadow:
                AppElevation.raisedSm(AppColors.adminSurface, intensity: .65),
          ),
          child: const Icon(
            Icons.local_pizza_outlined,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kitchen',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            Text(
              'Restaurant OS',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KitchenTenantSwitcher extends ConsumerWidget {
  const _KitchenTenantSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final establishments = ref.watch(availableEstablishmentsProvider);
    return establishments.when(
      data: (items) {
        if (items.isEmpty) {
          return const _TenantShellLabel(
            title: 'Aucun etablissement',
            subtitle: 'Contexte manquant',
          );
        }
        if (items.length == 1) {
          return _TenantShellLabel(
            title: items.first.name,
            subtitle: items.first.isActive ? items.first.timezone : 'Inactif',
          );
        }

        final selectedId = ref.watch(selectedEstablishmentIdProvider);
        final current = items.any((item) => item.id == selectedId)
            ? selectedId
            : items.first.id;

        return InputDecorator(
          decoration: InputDecoration(
            labelText: 'Etablissement actif',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: current,
              isDense: true,
              isExpanded: true,
              icon: const Icon(Icons.expand_more),
              items: [
                for (final item in items)
                  DropdownMenuItem<int>(
                    value: item.id,
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null || value == current) {
                  return;
                }
                ref.read(selectedEstablishmentIdProvider.notifier).state =
                    value;
                invalidateEstablishmentScopedProviders(ref);
              },
            ),
          ),
        );
      },
      loading: () => const _TenantShellLabel(
        title: 'Etablissement',
        subtitle: 'Chargement',
      ),
      error: (error, stackTrace) => const _TenantShellLabel(
        title: 'Etablissement',
        subtitle: 'Indisponible',
      ),
    );
  }
}

class _TenantShellLabel extends StatelessWidget {
  const _TenantShellLabel({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.adminSurfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.adminBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _KitchenGlobalSearch extends ConsumerStatefulWidget {
  const _KitchenGlobalSearch();

  @override
  ConsumerState<_KitchenGlobalSearch> createState() =>
      _KitchenGlobalSearchState();
}

class _KitchenGlobalSearchState extends ConsumerState<_KitchenGlobalSearch> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(currentPermissionSetProvider);
    return Semantics(
      textField: true,
      label: 'Recherche globale',
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.adminSurfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.adminBorder),
          boxShadow: AppElevation.pressed(
            AppColors.adminSurfaceMuted,
            intensity: .25,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: AppColors.textMuted, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration.collapsed(
                  hintText: 'Rechercher une commande, un module, une action',
                ),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                onSubmitted: (value) => _openResults(
                  context,
                  permissions,
                  value,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(
              Icons.keyboard_return,
              color: AppColors.textMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openResults(
    BuildContext context,
    PermissionSet permissions,
    String rawQuery,
  ) async {
    final query = rawQuery.trim();
    final hits = _searchHits(permissions, query);
    final selected = await showDialog<_SearchHit>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recherche globale'),
        content: SizedBox(
          width: 520,
          child: hits.isEmpty
              ? const _SearchEmptyState()
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: hits.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final hit = hits[index];
                    return ListTile(
                      leading: Icon(hit.icon),
                      title: Text(hit.title),
                      subtitle: Text(hit.subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).pop(hit),
                    );
                  },
                ),
        ),
      ),
    );
    if (selected == null || !context.mounted) {
      return;
    }
    _controller.clear();
    context.go(selected.route);
  }

  List<_SearchHit> _searchHits(PermissionSet permissions, String query) {
    final normalized = query.toLowerCase();
    final hits = <_SearchHit>[];

    final orderId = _extractOrderId(query);
    if (orderId != null && permissions.can(AppPermission.ordersRead)) {
      hits.add(
        _SearchHit(
          icon: Icons.receipt_long_outlined,
          title: 'Commande #$orderId',
          subtitle: 'Ouvrir le module Service',
          route: '/orders',
        ),
      );
    }

    for (final capability in visibleNavigationFor(permissions)) {
      if (capability.group == NavigationGroup.hidden) {
        continue;
      }
      final haystack = '${capability.label} ${capability.path}'.toLowerCase();
      if (normalized.isEmpty || haystack.contains(normalized)) {
        hits.add(
          _SearchHit(
            icon: capability.icon,
            title: capability.label,
            subtitle: 'Ouvrir ${capability.path}',
            route: capability.path,
          ),
        );
      }
    }

    if (permissions.can(AppPermission.stockRead) &&
        _matches(normalized, ['stock', 'rupture', 'ingredient'])) {
      hits.add(
        const _SearchHit(
          icon: Icons.inventory_2_outlined,
          title: 'Alertes stock',
          subtitle: 'Voir les niveaux critiques',
          route: '/stock',
        ),
      );
    }
    if (permissions.can(AppPermission.paymentsRead) &&
        _matches(normalized, ['paiement', 'tpe', 'terminal', 'stripe'])) {
      hits.add(
        const _SearchHit(
          icon: Icons.point_of_sale_outlined,
          title: 'Paiements et TPE',
          subtitle: 'Voir encaissements et lecteurs',
          route: '/payments',
        ),
      );
    }
    if (_matches(normalized, ['planning', 'shift', 'pointage', 'service'])) {
      hits.add(
        const _SearchHit(
          icon: Icons.punch_clock_outlined,
          title: 'Mon RH',
          subtitle: 'Voir pointage et prochains shifts',
          route: '/hr',
        ),
      );
    }

    final seen = <String>{};
    return [
      for (final hit in hits)
        if (seen.add('${hit.title}:${hit.route}')) hit,
    ].take(8).toList();
  }

  int? _extractOrderId(String query) {
    final match = RegExp(r'#?(\d{1,8})$').firstMatch(query.trim());
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1) ?? '');
  }

  bool _matches(String query, List<String> terms) {
    return query.isNotEmpty &&
        terms.any((term) => term.contains(query) || query.contains(term));
  }
}

class _SearchHit {
  const _SearchHit({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Icon(Icons.search_off_outlined, color: AppColors.textSecondary),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Aucun resultat accessible avec vos permissions.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KitchenModuleBar extends StatelessWidget {
  const _KitchenModuleBar({
    required this.destinations,
    required this.selectedIndex,
  });

  final List<_ShellDestination> destinations;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final primary = destinations
        .where((item) => item.group == NavigationGroup.primary)
        .toList();
    final more = destinations
        .where((item) => item.group == NavigationGroup.more)
        .toList();
    final selectedPath = destinations.isEmpty
        ? ''
        : destinations[selectedIndex.clamp(0, destinations.length - 1).toInt()]
            .path;

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: const BoxDecoration(
        color: AppColors.adminBackground,
        border: Border(
          bottom: BorderSide(color: AppColors.adminBorder),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in primary) ...[
              _KitchenModuleButton(
                item: item,
                selected: item.path == selectedPath,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            if (more.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              _KitchenMoreMenu(
                destinations: more,
                selectedPath: selectedPath,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KitchenModuleButton extends StatefulWidget {
  const _KitchenModuleButton({
    required this.item,
    required this.selected,
  });

  final _ShellDestination item;
  final bool selected;

  @override
  State<_KitchenModuleButton> createState() => _KitchenModuleButtonState();
}

class _KitchenModuleButtonState extends State<_KitchenModuleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final fill =
        selected ? AppColors.adminSurface : AppColors.adminSurfaceMuted;
    return Tooltip(
      message: widget.item.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => context.go(widget.item.path),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: _pressed ? NeumorphicShadows.pressedFill(fill) : fill,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.adminBorder,
            ),
            boxShadow: selected || _pressed
                ? AppElevation.pressed(fill, intensity: .35)
                : AppElevation.raisedSm(fill, intensity: .35),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.item.icon,
                size: 19,
                color: selected ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                widget.item.label,
                style: TextStyle(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KitchenMoreMenu extends StatelessWidget {
  const _KitchenMoreMenu({
    required this.destinations,
    required this.selectedPath,
  });

  final List<_ShellDestination> destinations;
  final String selectedPath;

  @override
  Widget build(BuildContext context) {
    final selected = destinations.any((item) => item.path == selectedPath);
    return PopupMenuButton<String>(
      tooltip: 'Plus de modules',
      onSelected: context.go,
      itemBuilder: (context) => [
        for (final item in destinations)
          PopupMenuItem(
            value: item.path,
            child: Row(
              children: [
                Icon(item.icon, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Text(item.label),
              ],
            ),
          ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.adminSurface : AppColors.adminSurfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.adminBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.apps_outlined,
              size: 19,
              color: selected ? AppColors.accent : AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            const Text(
              'Plus',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}

class _AdminMobileShell extends StatelessWidget {
  const _AdminMobileShell({
    required this.destinations,
    required this.selectedIndex,
    required this.child,
  });

  final List<_ShellDestination> destinations;
  final int selectedIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.adminBackground,
      appBar: AppBar(
        title: Text(destinations[selectedIndex].label),
        actions: const [
          _ShellStatusActions(compact: true),
          _ServiceModeButton(),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const _SidebarBrand(compact: false),
              const SizedBox(height: AppSpacing.lg),
              for (var index = 0; index < destinations.length; index++)
                ListTile(
                  leading: Icon(destinations[index].icon),
                  title: Text(destinations[index].label),
                  selected: index == selectedIndex,
                  onTap: () {
                    Navigator.of(context).pop();
                    context.go(destinations[index].path);
                  },
                ),
            ],
          ),
        ),
      ),
      body: child,
    );
  }
}

class _StaffMobileShell extends StatelessWidget {
  const _StaffMobileShell({
    required this.destinations,
    required this.location,
    required this.child,
  });

  final List<_ShellDestination> destinations;
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex(destinations, location);
    return Theme(
      data: ApiKitchenTheme.staffDark(),
      child: Scaffold(
        backgroundColor: AppColors.staffBackground,
        appBar: AppBar(
          backgroundColor: AppColors.staffBackground,
          foregroundColor: AppColors.staffText,
          titleSpacing: 20,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'API KITCHEN',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.staffText,
                      fontSize: 14,
                    ),
              ),
              Text(
                destinations[selectedIndex].label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.staffMuted,
                    ),
              ),
            ],
          ),
          actions: const [
            _LiveBadge(),
            SizedBox(width: AppSpacing.sm),
          ],
        ),
        body: ColoredBox(
          color: AppColors.staffBackground,
          child: child,
        ),
        bottomNavigationBar: NavigationBar(
          height: 68,
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) =>
              context.go(destinations[index].path),
          destinations: [
            for (final item in destinations)
              NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.icon),
                label: _staffMobileLabel(item),
              ),
          ],
        ),
      ),
    );
  }

  int _selectedIndex(List<_ShellDestination> destinations, String path) {
    final index = destinations.indexWhere((item) => path.startsWith(item.path));
    return index < 0 ? 0 : index;
  }
}

class _SidebarBrand extends StatelessWidget {
  const _SidebarBrand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(
        message: 'API KITCHEN',
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.adminSidebarActive,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppElevation.raisedSm(AppColors.adminSidebarActive),
          ),
          child: const Text(
            'AK',
            style: TextStyle(
              color: AppColors.staffText,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      );
    }

    return const SizedBox(
      height: 48,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'API KITCHEN',
            style: TextStyle(
              color: AppColors.staffText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'RESTAURANT OS',
            style: TextStyle(
              color: AppColors.adminSidebarMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.successDarkBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(
          color: AppColors.success,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ShellStatusActions extends ConsumerWidget {
  const _ShellStatusActions({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineStatusProvider).valueOrNull ?? true;
    final tenant = ref.watch(tenantStatusProvider).valueOrNull;
    final queued = ref.watch(syncQueueProvider).length;
    final notifications = ref.watch(notificationBusProvider).length;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            online ? Icons.wifi_outlined : Icons.wifi_off_outlined,
            color: online
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
          if (queued > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Badge(
                label: Text(queued.toString()),
                child: const Icon(Icons.cloud_sync_outlined),
              ),
            ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Chip(
          avatar: Icon(
            online ? Icons.wifi_outlined : Icons.wifi_off_outlined,
            size: 18,
          ),
          label: Text(online ? 'Online' : 'Offline'),
        ),
        if (tenant != null)
          Chip(
            avatar: Icon(
              tenant.isOpen ? Icons.storefront_outlined : Icons.lock_outline,
              size: 18,
            ),
            label: Text(tenant.isOpen ? 'Ouvert' : 'Ferme'),
          ),
        if (queued > 0)
          Chip(
            avatar: const Icon(Icons.cloud_sync_outlined, size: 18),
            label: Text('$queued sync'),
          ),
        if (notifications > 0)
          Chip(
            avatar: const Icon(Icons.notifications_outlined, size: 18),
            label: Text(notifications.toString()),
          ),
      ],
    );
  }
}

class _ServiceModeButton extends ConsumerWidget {
  const _ServiceModeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serviceMode = ref.watch(serviceModeProvider);
    return IconButton(
      tooltip: 'Mode service',
      onPressed: () {
        ref.read(serviceModeProvider.notifier).state = !serviceMode;
      },
      icon: Icon(serviceMode ? Icons.dark_mode : Icons.light_mode),
    );
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.path,
    required this.label,
    required this.icon,
    this.permission,
    this.requiredRole,
    this.group = NavigationGroup.primary,
  });

  factory _ShellDestination.fromCapability(NavigationCapability capability) {
    return _ShellDestination(
      path: capability.path,
      label: capability.label,
      icon: capability.icon,
      permission: capability.permission,
      requiredRole: capability.requiredRole,
      group: capability.group,
    );
  }

  final String path;
  final String label;
  final IconData icon;
  final String? permission;
  final String? requiredRole;
  final NavigationGroup group;
}

String _initialsFor(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+|@'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return 'K';
  }
  final initials = parts.take(2).map((part) => part[0].toUpperCase()).join();
  return initials.isEmpty ? 'K' : initials;
}

List<_ShellDestination> _staffMobileDestinations(
  List<_ShellDestination> destinations,
) {
  const preferred = ['/home', '/orders', '/kitchen', '/stock', '/hr'];
  final selected = <_ShellDestination>[];
  for (final path in preferred) {
    for (final item in destinations) {
      if (item.path == path) {
        selected.add(item);
      }
    }
  }
  if (selected.isEmpty) {
    return destinations.take(4).toList();
  }
  return selected;
}

String _staffMobileLabel(_ShellDestination item) {
  return switch (item.path) {
    '/home' => 'Accueil',
    '/orders' => 'Service',
    '/kitchen' => 'Commandes',
    '/stock' => 'Stock',
    '/hr' => 'Activite',
    _ => item.label,
  };
}
