import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final currentPermissionSetProvider = Provider<PermissionSet>((ref) {
  final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
  return PermissionSet(
    role: user?.role ?? 'staff',
    permissions: user?.permissions,
  );
});

class AppPermission {
  static const ordersRead = 'orders:read';
  static const ordersManual = 'orders:manual';
  static const ordersWrite = 'orders:write';
  static const ordersPreparation = 'orders:preparation';
  static const paymentsRead = 'payments:read';
  static const paymentsTerminal = 'payments:terminal';
  static const stockRead = 'stock:read';
  static const stockWrite = 'stock:write';
  static const stockAdjustmentCreate = 'stock:adjustment:create';
  static const catalogRead = 'catalog:read';
  static const catalogWrite = 'catalog:write';
  static const catalogAvailability = 'catalog:availability';
  static const printRead = 'print:read';
  static const deliveryRead = 'delivery:read';
  static const promotionsRead = 'promotions:read';
  static const loyaltyRead = 'loyalty:read';

  static const staffDefaults = <String>{
    ordersRead,
    ordersManual,
    ordersWrite,
    ordersPreparation,
    paymentsRead,
    paymentsTerminal,
    stockRead,
    stockWrite,
    stockAdjustmentCreate,
    catalogRead,
    catalogAvailability,
    printRead,
    deliveryRead,
    promotionsRead,
    loyaltyRead,
  };
}

class PermissionSet {
  const PermissionSet({
    required this.role,
    required this.permissions,
  });

  final String role;
  final Set<String>? permissions;

  bool can(String permission) {
    if (role == 'admin' || role == 'super-admin') {
      return true;
    }
    if (role != 'staff') {
      return false;
    }
    if (permissions == null) {
      return AppPermission.staffDefaults.contains(permission);
    }
    return permissions!.contains('*') || permissions!.contains(permission);
  }

  bool hasRole(String expectedRole) {
    if (role == expectedRole) {
      return true;
    }
    return expectedRole == 'admin' && role == 'super-admin';
  }
}

class PermissionGuard extends ConsumerWidget {
  const PermissionGuard({
    required this.permission,
    required this.child,
    this.fallback = const SizedBox.shrink(),
    super.key,
  });

  final String permission;
  final Widget child;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(currentPermissionSetProvider);
    if (!permissions.can(permission)) {
      return fallback;
    }
    return child;
  }
}
