import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:app_admin_staff/app/service_mode.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/core/realtime/notification_bus.dart';
import 'package:app_admin_staff/design_system/theme/api_kitchen_theme.dart';
import 'package:app_admin_staff/design_system/tokens/app_breakpoints.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
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
    final destinations = _destinations.where(
      (item) {
        if (item.requiredRole != null &&
            !permissions.hasRole(item.requiredRole!)) {
          return false;
        }
        return isAdmin ||
            item.permission == null ||
            permissions.can(item.permission!);
      },
    ).toList();
    final selectedIndex = _selectedIndex(destinations, location);

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

    return Scaffold(
      backgroundColor: AppColors.adminBackground,
      body: Row(
        children: [
          _AdminSidebar(
            destinations: destinations,
            selectedIndex: selectedIndex,
            compact: AppBreakpoints.isCompactDesktop(context),
          ),
          Expanded(
            child: ColoredBox(
              color: AppColors.adminBackground,
              child: child,
            ),
          ),
        ],
      ),
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

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.destinations,
    required this.selectedIndex,
    required this.compact,
  });

  final List<_ShellDestination> destinations;
  final int selectedIndex;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppBreakpoints.adminSidebarWidth(context),
      color: AppColors.adminSidebar,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpacing.xs : AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            children: [
              _SidebarBrand(compact: compact),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: ListView.separated(
                  itemBuilder: (context, index) {
                    final item = destinations[index];
                    return _AdminSidebarItem(
                      item: item,
                      selected: index == selectedIndex,
                      compact: compact,
                    );
                  },
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppSpacing.xs),
                  itemCount: destinations.length,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const _SidebarFooter(),
              const SizedBox(height: AppSpacing.sm),
              const _ServiceModeButton(inSidebar: true),
            ],
          ),
        ),
      ),
    );
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

class _AdminSidebarItem extends StatelessWidget {
  const _AdminSidebarItem({
    required this.item,
    required this.selected,
    required this.compact,
  });

  final _ShellDestination item;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.staffText : AppColors.adminSidebarMuted;
    final iconColor = selected ? AppColors.accent : AppColors.adminSidebarIcon;
    final content = InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => context.go(item.path),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 0 : AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.adminSidebarActive : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          mainAxisAlignment:
              compact ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            if (!compact)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color:
                      selected ? AppColors.accent : AppColors.adminSidebarIcon,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            if (!compact) const SizedBox(width: AppSpacing.sm),
            Icon(item.icon, color: iconColor, size: 20),
            if (!compact) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Tooltip(message: item.label, child: content);
  }
}

class _SidebarFooter extends ConsumerWidget {
  const _SidebarFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).valueOrNull;
    final user = session?.user;
    final establishments = ref.watch(availableEstablishmentsProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 120) {
          return const _ShellStatusActions(compact: true);
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.adminSidebarActive,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              establishments.when(
                data: (items) => _EstablishmentFooterControl(items: items),
                loading: () => const _SidebarFooterLabel(
                  label: 'Etablissement',
                  muted: 'Chargement',
                ),
                error: (error, stackTrace) => const _SidebarFooterLabel(
                  label: 'Etablissement',
                  muted: 'Indisponible',
                ),
              ),
              if (user != null)
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.adminSidebarMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              const _ShellStatusActions(compact: true),
            ],
          ),
        );
      },
    );
  }
}

class _SidebarFooterLabel extends StatelessWidget {
  const _SidebarFooterLabel({
    required this.label,
    this.muted,
  });

  final String label;
  final String? muted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.staffText,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        if (muted != null)
          Text(
            muted!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.adminSidebarMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
      ],
    );
  }
}

class _EstablishmentFooterControl extends ConsumerWidget {
  const _EstablishmentFooterControl({required this.items});

  final List<Establishment> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const _SidebarFooterLabel(
        label: 'Aucun etablissement',
        muted: 'Contexte manquant',
      );
    }

    if (items.length == 1) {
      return _SidebarFooterLabel(
        label: items.first.name,
        muted: items.first.isActive ? items.first.timezone : 'Inactif',
      );
    }

    final selectedId = ref.watch(selectedEstablishmentIdProvider);
    final current = items.any((item) => item.id == selectedId)
        ? selectedId
        : items.first.id;

    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: current,
        isDense: true,
        isExpanded: true,
        dropdownColor: AppColors.adminSidebarActive,
        iconEnabledColor: AppColors.adminSidebarMuted,
        style: const TextStyle(
          color: AppColors.staffText,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
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
          ref.read(selectedEstablishmentIdProvider.notifier).state = value;
          invalidateEstablishmentScopedProviders(ref);
        },
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
  const _ServiceModeButton({this.inSidebar = false});

  final bool inSidebar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serviceMode = ref.watch(serviceModeProvider);
    return IconButton(
      tooltip: 'Mode service',
      onPressed: () {
        ref.read(serviceModeProvider.notifier).state = !serviceMode;
      },
      icon: Icon(serviceMode ? Icons.dark_mode : Icons.light_mode),
      color: inSidebar ? AppColors.adminSidebarMuted : null,
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
  });

  final String path;
  final String label;
  final IconData icon;
  final String? permission;
  final String? requiredRole;
}

const _destinations = [
  _ShellDestination(
    path: '/dashboard',
    label: 'Pilotage',
    icon: Icons.dashboard_outlined,
    permission: AppPermission.ordersRead,
    requiredRole: 'admin',
  ),
  _ShellDestination(
    path: '/orders',
    label: 'Service',
    icon: Icons.receipt_long_outlined,
    permission: AppPermission.ordersRead,
  ),
  _ShellDestination(
    path: '/kitchen',
    label: 'Cuisine',
    icon: Icons.restaurant_outlined,
    permission: AppPermission.ordersPreparation,
  ),
  _ShellDestination(
    path: '/checkout',
    label: 'Caisse',
    icon: Icons.point_of_sale_outlined,
    permission: AppPermission.ordersManual,
  ),
  _ShellDestination(
    path: '/catalog',
    label: 'Catalogue',
    icon: Icons.inventory_2_outlined,
    permission: AppPermission.catalogRead,
  ),
  _ShellDestination(
    path: '/stock',
    label: 'Stock',
    icon: Icons.warehouse_outlined,
    permission: AppPermission.stockRead,
  ),
  _ShellDestination(
    path: '/team',
    label: 'Equipe',
    icon: Icons.group_outlined,
    requiredRole: 'admin',
  ),
  _ShellDestination(
    path: '/hr/admin',
    label: 'RH',
    icon: Icons.calendar_month_outlined,
    requiredRole: 'admin',
  ),
  _ShellDestination(
    path: '/hr',
    label: 'Mon RH',
    icon: Icons.punch_clock_outlined,
  ),
  _ShellDestination(
    path: '/payments',
    label: 'Paiements',
    icon: Icons.payments_outlined,
    permission: AppPermission.paymentsRead,
  ),
  _ShellDestination(
    path: '/delivery',
    label: 'Livraison',
    icon: Icons.map_outlined,
    permission: AppPermission.deliveryRead,
  ),
  _ShellDestination(
    path: '/loyalty',
    label: 'Fidelite',
    icon: Icons.loyalty_outlined,
    permission: AppPermission.loyaltyRead,
  ),
  _ShellDestination(
    path: '/promotions',
    label: 'Promos',
    icon: Icons.local_offer_outlined,
    permission: AppPermission.promotionsRead,
  ),
  _ShellDestination(
    path: '/settings',
    label: 'Reglages',
    icon: Icons.settings_outlined,
  ),
];

List<_ShellDestination> _staffMobileDestinations(
  List<_ShellDestination> destinations,
) {
  const preferred = ['/orders', '/kitchen', '/stock', '/hr'];
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
    '/orders' => 'Service',
    '/kitchen' => 'Commandes',
    '/stock' => 'Stock',
    '/hr' => 'Activite',
    _ => item.label,
  };
}
