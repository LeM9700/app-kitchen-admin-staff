import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/app/theme/app_theme_mode.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/core/widgets/admin_shell.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile drawer switch toggles dark mode', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        currentPermissionSetProvider.overrideWithValue(
          const PermissionSet(role: 'admin', permissions: null),
        ),
        onlineStatusProvider.overrideWith((ref) => Stream.value(true)),
        tenantStatusProvider.overrideWith(
          (ref) async => const TenantStatus(
            isOpen: true,
            estimatedPrepTimeMinutes: 20,
            activeOrdersCount: 2,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AdminShell(
            location: '/home',
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(container.read(appThemeModeProvider), ThemeMode.light);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(
      const ValueKey('mobile-theme-mode-switch'),
    );
    expect(switchFinder, findsOneWidget);
    expect(find.text('Apparence sombre'), findsOneWidget);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(container.read(appThemeModeProvider), ThemeMode.dark);
  });
}
