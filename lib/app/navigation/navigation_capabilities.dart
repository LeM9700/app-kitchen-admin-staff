import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:flutter/material.dart';

enum NavigationGroup { primary, more, hidden }

class NavigationCapability {
  const NavigationCapability({
    required this.path,
    required this.label,
    required this.icon,
    this.permission,
    this.requiredRole,
    this.group = NavigationGroup.primary,
    this.mobilePriority = 99,
  });

  final String path;
  final String label;
  final IconData icon;
  final String? permission;
  final String? requiredRole;
  final NavigationGroup group;
  final int mobilePriority;

  bool isVisibleFor(PermissionSet permissions) {
    if (requiredRole != null && !permissions.hasRole(requiredRole!)) {
      return false;
    }
    if (permission != null && !permissions.can(permission!)) {
      return false;
    }
    return group != NavigationGroup.hidden;
  }

  bool isAllowedFor(PermissionSet permissions) {
    if (requiredRole != null && !permissions.hasRole(requiredRole!)) {
      return false;
    }
    if (permission != null && !permissions.can(permission!)) {
      return false;
    }
    return true;
  }
}

const navigationCapabilities = [
  NavigationCapability(
    path: '/home',
    label: 'Accueil',
    icon: Icons.home_outlined,
    mobilePriority: 0,
  ),
  NavigationCapability(
    path: '/dashboard',
    label: 'Accueil',
    icon: Icons.home_outlined,
    group: NavigationGroup.hidden,
  ),
  NavigationCapability(
    path: '/orders',
    label: 'Service',
    icon: Icons.receipt_long_outlined,
    permission: AppPermission.ordersRead,
    mobilePriority: 1,
  ),
  NavigationCapability(
    path: '/kitchen',
    label: 'Cuisine',
    icon: Icons.restaurant_outlined,
    permission: AppPermission.ordersPreparation,
    mobilePriority: 2,
  ),
  NavigationCapability(
    path: '/kitchen/remote',
    label: 'Remote KDS',
    icon: Icons.screenshot_monitor_outlined,
    permission: AppPermission.ordersPreparation,
    group: NavigationGroup.hidden,
  ),
  NavigationCapability(
    path: '/checkout',
    label: 'Caisse',
    icon: Icons.point_of_sale_outlined,
    permission: AppPermission.ordersManual,
    mobilePriority: 3,
  ),
  NavigationCapability(
    path: '/catalog',
    label: 'Catalogue',
    icon: Icons.inventory_2_outlined,
    permission: AppPermission.catalogRead,
    mobilePriority: 4,
  ),
  NavigationCapability(
    path: '/stock',
    label: 'Stock',
    icon: Icons.warehouse_outlined,
    permission: AppPermission.stockRead,
    mobilePriority: 4,
  ),
  NavigationCapability(
    path: '/team',
    label: 'Equipe',
    icon: Icons.group_outlined,
    requiredRole: 'admin',
    mobilePriority: 6,
  ),
  NavigationCapability(
    path: '/customers',
    label: 'Clients',
    icon: Icons.people_alt_outlined,
    requiredRole: 'admin',
    group: NavigationGroup.more,
  ),
  NavigationCapability(
    path: '/haccp',
    label: 'HACCP',
    icon: Icons.health_and_safety_outlined,
    permission: AppPermission.haccpRead,
    group: NavigationGroup.more,
  ),
  NavigationCapability(
    path: '/hr/admin',
    label: 'RH',
    icon: Icons.calendar_month_outlined,
    requiredRole: 'admin',
    group: NavigationGroup.more,
  ),
  NavigationCapability(
    path: '/hr',
    label: 'Mon RH',
    icon: Icons.punch_clock_outlined,
    group: NavigationGroup.more,
    mobilePriority: 5,
  ),
  NavigationCapability(
    path: '/payments',
    label: 'Paiements',
    icon: Icons.payments_outlined,
    permission: AppPermission.paymentsRead,
    group: NavigationGroup.more,
  ),
  NavigationCapability(
    path: '/delivery',
    label: 'Livraison',
    icon: Icons.map_outlined,
    permission: AppPermission.deliveryRead,
    group: NavigationGroup.more,
  ),
  NavigationCapability(
    path: '/loyalty',
    label: 'Fidelite',
    icon: Icons.loyalty_outlined,
    permission: AppPermission.loyaltyRead,
    group: NavigationGroup.more,
  ),
  NavigationCapability(
    path: '/promotions',
    label: 'Promos',
    icon: Icons.local_offer_outlined,
    permission: AppPermission.promotionsRead,
    group: NavigationGroup.more,
  ),
  NavigationCapability(
    path: '/settings',
    label: 'Reglages',
    icon: Icons.settings_outlined,
    group: NavigationGroup.more,
  ),
];

List<NavigationCapability> visibleNavigationFor(PermissionSet permissions) {
  return [
    for (final capability in navigationCapabilities)
      if (capability.isVisibleFor(permissions)) capability,
  ];
}

NavigationCapability? navigationForLocation(String location) {
  final matches = [
    for (final capability in navigationCapabilities)
      if (location == capability.path ||
          location.startsWith('${capability.path}/'))
        capability,
  ]..sort((a, b) => b.path.length.compareTo(a.path.length));
  return matches.isEmpty ? null : matches.first;
}
