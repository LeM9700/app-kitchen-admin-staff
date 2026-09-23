import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin can access every permission', () {
    const permissions = PermissionSet(role: 'admin', permissions: {});
    expect(permissions.can(AppPermission.paymentsTerminal), isTrue);
    expect(permissions.can('anything'), isTrue);
  });

  test('super admin can access every permission', () {
    const permissions = PermissionSet(role: 'super-admin', permissions: {});
    expect(permissions.can(AppPermission.catalogWrite), isTrue);
    expect(permissions.can('anything'), isTrue);
  });

  test('staff permissions null are deny by default', () {
    const permissions = PermissionSet(role: 'staff', permissions: null);
    expect(permissions.can(AppPermission.ordersPreparation), isFalse);
    expect(permissions.can(AppPermission.ordersRead), isFalse);
    expect(permissions.can('unknown'), isFalse);
  });

  test('staff permissions empty are deny by default', () {
    const permissions = PermissionSet(role: 'staff', permissions: {});
    expect(permissions.can(AppPermission.ordersPreparation), isFalse);
    expect(permissions.can(AppPermission.ordersRead), isFalse);
    expect(permissions.can('unknown'), isFalse);
  });

  test('explicit staff permissions are authoritative', () {
    const permissions = PermissionSet(
      role: 'staff',
      permissions: {AppPermission.ordersRead},
    );
    expect(permissions.can(AppPermission.ordersRead), isTrue);
    expect(permissions.can(AppPermission.ordersWrite), isFalse);
  });

  test('hasRole treats super-admin as admin', () {
    const permissions = PermissionSet(role: 'super-admin', permissions: null);
    expect(permissions.hasRole('admin'), isTrue);
    expect(permissions.hasRole('staff'), isFalse);
  });
}
