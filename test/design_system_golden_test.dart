import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/app/theme/app_theme.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/core/realtime/notification_bus.dart';
import 'package:app_admin_staff/core/widgets/admin_shell.dart';
import 'package:app_admin_staff/features/admin_users/data/admin_users_repository.dart';
import 'package:app_admin_staff/features/admin_users/presentation/admin_users_page.dart';
import 'package:app_admin_staff/features/auth/data/auth_repository.dart';
import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/catalog/presentation/catalog_page.dart';
import 'package:app_admin_staff/features/delivery/data/delivery_repository.dart';
import 'package:app_admin_staff/features/delivery/presentation/delivery_page.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/hr/data/hr_repository.dart';
import 'package:app_admin_staff/features/hr/presentation/hr_page.dart';
import 'package:app_admin_staff/features/loyalty/data/loyalty_repository.dart';
import 'package:app_admin_staff/features/loyalty/presentation/loyalty_page.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/orders/presentation/orders_board_page.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:app_admin_staff/features/payments/presentation/payments_page.dart';
import 'package:app_admin_staff/features/promotions/data/promotions_repository.dart';
import 'package:app_admin_staff/features/promotions/presentation/promotions_page.dart';
import 'package:app_admin_staff/features/settings/presentation/settings_page.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:app_admin_staff/features/stock/presentation/stock_page.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:app_admin_staff/core/api/paginated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _goldenSurfaceKey = ValueKey('golden-surface');
final _fixedWeek = DateTime(2026, 8, 10);

void main() {
  testWidgets('Admin Members 1440 golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1440, 1024),
      location: '/team',
      child: const AdminUsersPage(),
      overrides: _adminOverrides(),
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/admin_members_1440.png'),
    );
  });

  testWidgets('Admin Members 1280 golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1280, 900),
      location: '/team',
      child: const AdminUsersPage(),
      overrides: _adminOverrides(),
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/admin_members_1280.png'),
    );
  });

  testWidgets('Planning 1440 golden', (tester) async {
    await _pumpHrTab(
      tester,
      size: const Size(1440, 1024),
      tab: 'Planning',
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/planning_1440.png'),
    );
  });

  testWidgets('Planning 1280 golden', (tester) async {
    await _pumpHrTab(
      tester,
      size: const Size(1280, 900),
      tab: 'Planning',
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/planning_1280.png'),
    );
  });

  testWidgets('Pointages golden', (tester) async {
    await _pumpHrTab(
      tester,
      size: const Size(1440, 1024),
      tab: 'Pointages',
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/timeclock.png'),
    );
  });

  testWidgets('Alertes RH golden', (tester) async {
    await _pumpHrTab(
      tester,
      size: const Size(1440, 1024),
      tab: 'Alertes',
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/hr_alerts.png'),
    );
  });

  testWidgets('Staff Service 390 golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(390, 844),
      location: '/orders',
      child: const OrdersBoardPage(),
      overrides: _staffOverrides(),
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/staff_service_390.png'),
    );
  });

  testWidgets('Catalogue 1440 golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1440, 1024),
      location: '/catalog',
      child: const CatalogPage(),
      overrides: _adminOverrides(),
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/catalogue_1440.png'),
    );
  });

  testWidgets('Catalogue 1280 golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1280, 900),
      location: '/catalog',
      child: const CatalogPage(),
      overrides: _adminOverrides(),
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/catalogue_1280.png'),
    );
  });

  testWidgets('Edition produit golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1440, 1024),
      location: '/catalog',
      child: const CatalogPage(),
      overrides: _adminOverrides(),
    );
    await tester.tap(find.byTooltip('Modifier produit').first);
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/product_editor.png'),
    );
  });

  testWidgets('Stock Admin golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1440, 1024),
      location: '/stock',
      child: const StockPage(),
      overrides: _adminOverrides(),
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/stock_admin.png'),
    );
  });

  testWidgets('Finance golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1440, 1024),
      location: '/payments',
      child: const PaymentsPage(),
      overrides: _adminOverrides(),
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/finance.png'),
    );
  });

  testWidgets('Promotions 1440 golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1440, 1024),
      location: '/promotions',
      child: const PromotionsPage(),
      overrides: _adminOverrides(),
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/promotions_1440.png'),
    );
  });

  testWidgets('Promotions 1280 golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1280, 900),
      location: '/promotions',
      child: const PromotionsPage(),
      overrides: _adminOverrides(),
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/promotions_1280.png'),
    );
  });

  testWidgets('Loyalty golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1440, 1024),
      location: '/loyalty',
      child: const LoyaltyPage(),
      overrides: _adminOverrides(),
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/loyalty.png'),
    );
  });

  testWidgets('Delivery zones 1440 golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1440, 1024),
      location: '/delivery',
      child: const DeliveryPage(),
      overrides: _adminOverrides(),
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/delivery_zones_1440.png'),
    );
  });

  testWidgets('Delivery zones 1280 golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1280, 900),
      location: '/delivery',
      child: const DeliveryPage(),
      overrides: _adminOverrides(),
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/delivery_zones_1280.png'),
    );
  });

  testWidgets('Parametres golden', (tester) async {
    await _pumpShell(
      tester,
      size: const Size(1440, 1024),
      location: '/settings',
      child: const SettingsPage(),
      overrides: _adminOverrides(),
    );

    await expectLater(
      find.byKey(_goldenSurfaceKey),
      matchesGoldenFile('goldens/settings.png'),
    );
  });
}

Future<void> _pumpHrTab(
  WidgetTester tester, {
  required Size size,
  required String tab,
}) async {
  await _pumpShell(
    tester,
    size: size,
    location: '/hr/admin',
    child: const HrAdminPage(),
    overrides: _adminOverrides(),
  );
  await tester.tap(find.text(tab));
  await tester.pumpAndSettle();
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required Size size,
  required String location,
  required Widget child,
  required List<Override> overrides,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: RepaintBoundary(
        key: _goldenSurfaceKey,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AdminShell(location: location, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

List<Override> _adminOverrides() {
  return [
    sessionControllerProvider.overrideWith(_AdminSessionController.new),
    onlineStatusProvider.overrideWith((ref) => Stream.value(true)),
    availableEstablishmentsProvider.overrideWith(
      (ref) async => _establishments(),
    ),
    tenantStatusProvider.overrideWith(
      (ref) async => const TenantStatus(
        isOpen: true,
        estimatedPrepTimeMinutes: 20,
        activeOrdersCount: 4,
      ),
    ),
    tenantConfigProvider.overrideWith((ref) async => _tenantConfig()),
    tenantBusinessHoursProvider.overrideWith((ref) async => _businessHours()),
    tenantClosuresProvider.overrideWith((ref) async => _closures()),
    tenantAuditProvider.overrideWith((ref) async => _tenantAudit()),
    tenantPrintConfigProvider.overrideWith((ref) async => _printConfig()),
    authSessionsProvider.overrideWith((ref) async => _authSessions()),
    syncQueueProvider.overrideWith(_EmptySyncQueue.new),
    notificationBusProvider.overrideWith(_EmptyNotificationBus.new),
    catalogProductsProvider.overrideWith((ref) async => _catalogProducts()),
    catalogCategoriesProvider.overrideWith((ref) async => _catalogCategories()),
    ingredientsProvider.overrideWith((ref) async => _ingredients()),
    stockAlertsProvider.overrideWith((ref) async => _stockAlerts()),
    stockMovementsProvider.overrideWith((ref) async => _stockMovements()),
    adjustmentRequestsProvider.overrideWith(
      (ref) async => _adjustmentRequests(),
    ),
    paymentsSummaryProvider.overrideWith((ref) async => _paymentSummary()),
    paymentsProvider.overrideWith((ref) async => _payments()),
    terminalReadersProvider.overrideWith((ref) async => _terminalReaders()),
    connectStatusProvider.overrideWith((ref) async => _connectStatus()),
    promotionsProvider.overrideWith((ref) async => _promotions()),
    loyaltyConfigProvider.overrideWith((ref) async => _loyaltyConfig()),
    loyaltyStatsProvider.overrideWith((ref) async => _loyaltyStats()),
    loyaltyRulesProvider.overrideWith((ref) async => _loyaltyRules()),
    loyaltyRewardsProvider.overrideWith((ref) async => _loyaltyRewards()),
    deliveryZonesProvider.overrideWith((ref) async => _deliveryZones()),
    adminUsersProvider.overrideWith((ref, query) async {
      return PaginatedResult<AdminUser>(
        items: _users(),
        total: _users().length,
        page: 1,
        pageSize: 100,
      );
    }),
    employeesProvider.overrideWith((ref) async => _employees()),
    hrWeekStartProvider.overrideWith((ref) => _fixedWeek),
    shiftsProvider.overrideWith((ref, query) async => _shifts()),
    timeClockEntriesProvider.overrideWith((ref, query) async => _entries()),
    hrAlertsProvider.overrideWith((ref, query) async => _alerts()),
    myEmployeeProfileProvider.overrideWith((ref) async => _selfProfile()),
    myShiftsProvider
        .overrideWith((ref, query) async => _shifts().take(2).toList()),
    myTimeClockEntriesProvider.overrideWith((ref, query) async => _entries()),
  ];
}

List<Override> _staffOverrides() {
  return [
    ..._adminOverrides(),
    sessionControllerProvider.overrideWith(_StaffSessionController.new),
    activeOrdersProvider.overrideWith((ref) async => _orders()),
  ];
}

List<AdminUser> _users() {
  return [
    AdminUser(
      id: 1,
      email: 'yanis.costa@test.local',
      fullName: 'Yanis Costa',
      role: 'staff',
      permissions: const [
        AppPermission.ordersRead,
        AppPermission.ordersPreparation,
        AppPermission.stockRead,
      ],
      isActive: true,
      emailVerified: true,
      createdAt: DateTime(2026, 8, 8, 9),
      mustChangePassword: true,
    ),
    AdminUser(
      id: 2,
      email: 'nora.admin@test.local',
      fullName: 'Nora Admin',
      role: 'admin',
      permissions: null,
      isActive: true,
      emailVerified: true,
      createdAt: DateTime(2026, 7, 28, 10),
      mustChangePassword: false,
    ),
    AdminUser(
      id: 3,
      email: 'samir.staff@test.local',
      fullName: 'Samir Bensaid',
      role: 'staff',
      permissions: const [AppPermission.ordersRead],
      isActive: false,
      emailVerified: false,
      createdAt: DateTime(2026, 8, 1, 14),
      mustChangePassword: false,
    ),
  ];
}

List<EmployeeProfile> _employees() {
  return [
    EmployeeProfile(
      id: 1,
      userId: 1,
      establishmentId: 1,
      hourlyRateCents: 1500,
      weeklyHoursContract: 35,
      isActive: true,
      createdAt: DateTime(2026, 8, 1),
    ),
    EmployeeProfile(
      id: 2,
      userId: 3,
      establishmentId: 1,
      hourlyRateCents: 1400,
      weeklyHoursContract: 28,
      isActive: true,
      createdAt: DateTime(2026, 8, 1),
    ),
  ];
}

List<HrShift> _shifts() {
  return [
    HrShift(
      id: 1,
      employeeId: 1,
      establishmentId: 1,
      startsAt: DateTime(2026, 8, 10, 9),
      endsAt: DateTime(2026, 8, 10, 13),
      breakMinutes: 15,
      status: 'scheduled',
    ),
    HrShift(
      id: 2,
      employeeId: 1,
      establishmentId: 1,
      startsAt: DateTime(2026, 8, 12, 17),
      endsAt: DateTime(2026, 8, 12, 22),
      breakMinutes: 30,
      status: 'scheduled',
    ),
    HrShift(
      id: 3,
      employeeId: 2,
      establishmentId: 1,
      startsAt: DateTime(2026, 8, 11, 10),
      endsAt: DateTime(2026, 8, 11, 15),
      breakMinutes: 20,
      status: 'cancelled',
    ),
  ];
}

List<TimeClockEntry> _entries() {
  return [
    TimeClockEntry(
      id: 1,
      employeeId: 1,
      establishmentId: 1,
      clockInAt: DateTime(2026, 8, 10, 9, 2),
      method: 'web',
      status: 'open',
    ),
    TimeClockEntry(
      id: 2,
      employeeId: 2,
      establishmentId: 1,
      clockInAt: DateTime(2026, 8, 10, 8, 58),
      clockOutAt: DateTime(2026, 8, 10, 13, 8),
      method: 'web',
      status: 'corrected',
    ),
  ];
}

List<HrAlert> _alerts() {
  return [
    HrAlert(
      id: 1,
      employeeId: 1,
      establishmentId: 1,
      type: 'late',
      severity: 'critical',
      payload: const {'minutes_late': 8, 'shift_id': 1},
      triggeredAt: DateTime(2026, 8, 10, 9, 8),
    ),
    HrAlert(
      id: 2,
      employeeId: 2,
      establishmentId: 1,
      type: 'weekly_overtime',
      severity: 'warning',
      payload: const {'planned_hours': 39},
      triggeredAt: DateTime(2026, 8, 10, 11, 40),
      resolvedAt: DateTime(2026, 8, 10, 12, 5),
    ),
  ];
}

EmployeeProfileSelf _selfProfile() {
  return const EmployeeProfileSelf(
    id: 1,
    userId: 1,
    establishmentId: 1,
    weeklyHoursContract: 35,
    isActive: true,
  );
}

List<OrderSummary> _orders() {
  // createdAt is relative to "now": LiveElapsed renders DateTime.now() -
  // createdAt live, so a fixed calendar date drifts out of the mm:ss format
  // (and out of the golden's frozen pixels) a few days after the golden was
  // captured. Keep these well under an hour old so the rendered elapsed
  // text stays a stable "mm:ss" width regardless of when the suite runs.
  final now = DateTime.now();
  return [
    OrderSummary(
      id: 142,
      orderType: 'dine_in',
      status: 'preparing',
      paymentStatus: 'paid',
      source: 'staff',
      total: 36.5,
      deliveryFee: 0,
      tableNumber: '18',
      customerName: 'Table 18',
      createdAt: now.subtract(const Duration(minutes: 9)),
    ),
    OrderSummary(
      id: 138,
      orderType: 'pickup',
      status: 'confirmed',
      paymentStatus: 'paid',
      source: 'customer',
      total: 21.8,
      deliveryFee: 0,
      customerName: 'Client comptoir',
      createdAt: now.subtract(const Duration(minutes: 6)),
    ),
    OrderSummary(
      id: 141,
      orderType: 'delivery',
      status: 'ready',
      paymentStatus: 'paid',
      source: 'customer',
      total: 29.2,
      deliveryFee: 4,
      deliveryAddress: '12 rue de la Loge',
      customerName: 'Livraison',
      createdAt: now.subtract(const Duration(minutes: 3)),
    ),
  ];
}

List<Establishment> _establishments() {
  return const [
    Establishment(
      id: 1,
      name: 'API Kitchen Centre',
      timezone: 'Europe/Paris',
      isActive: true,
    ),
    Establishment(
      id: 2,
      name: 'API Kitchen Nord',
      timezone: 'Europe/Paris',
      isActive: true,
    ),
  ];
}

List<CatalogCategory> _catalogCategories() {
  return const [
    CatalogCategory(
      id: 1,
      name: 'Pizzas',
      displayOrder: 1,
      preparationStation: 'kitchen',
      isActive: true,
    ),
    CatalogCategory(
      id: 2,
      name: 'Boissons',
      displayOrder: 2,
      preparationStation: 'counter',
      isActive: true,
    ),
    CatalogCategory(
      id: 3,
      name: 'Desserts',
      displayOrder: 3,
      preparationStation: 'counter',
      isActive: false,
    ),
  ];
}

List<CatalogProduct> _catalogProducts() {
  return const [
    CatalogProduct(
      id: 11,
      categoryId: 1,
      categoryName: 'Pizzas',
      name: 'Margherita',
      description: 'Tomate, mozzarella, basilic',
      basePrice: 11.5,
      isActive: true,
      available: true,
      effectivePreparationStation: 'kitchen',
      regulatoryComplete: true,
    ),
    CatalogProduct(
      id: 12,
      categoryId: 1,
      categoryName: 'Pizzas',
      name: 'Regina',
      description: 'Jambon, champignons, mozzarella',
      basePrice: 14,
      isActive: true,
      available: false,
      availabilityReason: 'Rupture champignons',
      effectivePreparationStation: 'kitchen',
      regulatoryComplete: false,
    ),
    CatalogProduct(
      id: 21,
      categoryId: 2,
      categoryName: 'Boissons',
      name: 'San Pellegrino',
      description: 'Eau petillante 50 cl',
      basePrice: 3.2,
      isActive: true,
      available: true,
      effectivePreparationStation: 'counter',
      regulatoryComplete: true,
    ),
    CatalogProduct(
      id: 31,
      categoryId: 3,
      categoryName: 'Desserts',
      name: 'Tiramisu',
      description: 'Dessert maison',
      basePrice: 5.5,
      isActive: false,
      available: false,
      effectivePreparationStation: 'counter',
      regulatoryComplete: true,
    ),
  ];
}

List<Ingredient> _ingredients() {
  return const [
    Ingredient(
      id: 1,
      name: 'Farine',
      unit: 'kg',
      currentQty: 18,
      alertThreshold: 12,
      isBelowThreshold: false,
    ),
    Ingredient(
      id: 2,
      name: 'Mozzarella',
      unit: 'kg',
      currentQty: 3.5,
      alertThreshold: 5,
      isBelowThreshold: true,
    ),
    Ingredient(
      id: 3,
      name: 'Sauce tomate',
      unit: 'L',
      currentQty: 8,
      alertThreshold: 6,
      isBelowThreshold: false,
    ),
  ];
}

List<Ingredient> _stockAlerts() {
  return _ingredients()
      .where((ingredient) => ingredient.isBelowThreshold)
      .toList();
}

List<StockMovement> _stockMovements() {
  return [
    StockMovement(
      id: 1,
      ingredientId: 2,
      quantityDelta: -1.5,
      reason: 'waste',
      userId: 10,
      createdAt: DateTime(2026, 8, 10, 12, 20),
    ),
    StockMovement(
      id: 2,
      ingredientId: 1,
      quantityDelta: 8,
      reason: 'supply',
      userId: 10,
      createdAt: DateTime(2026, 8, 10, 8, 10),
    ),
  ];
}

List<StockAdjustmentRequest> _adjustmentRequests() {
  return [
    StockAdjustmentRequest(
      id: 1,
      ingredientId: 2,
      quantityDelta: -2,
      reason: 'inventory',
      status: 'pending',
      requestedByUserId: 11,
      isLargeAdjustment: false,
      note: 'Comptage rush midi',
      createdAt: DateTime(2026, 8, 10, 12, 45),
    ),
  ];
}

PaymentSummary _paymentSummary() {
  return const PaymentSummary(
    collectedAmountCents: 18540,
    refundedAmountCents: 2200,
    netAmountCents: 16340,
    paymentCount: 12,
    refundCount: 2,
    countsByStatus: {
      'paid': 9,
      'partially_refunded': 2,
      'failed': 1,
    },
  );
}

List<PaymentListItem> _payments() {
  return [
    PaymentListItem(
      id: 1,
      orderId: 142,
      provider: 'stripe',
      amount: 36.5,
      currency: 'eur',
      status: 'paid',
      refundedAmountCents: 0,
      externalReference: 'pi_142',
      createdAt: DateTime(2026, 8, 10, 12, 36),
    ),
    PaymentListItem(
      id: 2,
      orderId: 138,
      provider: 'stripe',
      amount: 21.8,
      currency: 'eur',
      status: 'partially_refunded',
      refundedAmountCents: 800,
      externalReference: 'pi_138',
      createdAt: DateTime(2026, 8, 10, 12, 12),
    ),
    PaymentListItem(
      id: 3,
      orderId: 129,
      provider: 'terminal',
      amount: 18,
      currency: 'eur',
      status: 'refunded',
      refundedAmountCents: 1800,
      createdAt: DateTime(2026, 8, 10, 11, 48),
    ),
  ];
}

List<TerminalReader> _terminalReaders() {
  return const [
    TerminalReader(
      id: 'tmr_1',
      label: 'Comptoir',
      status: 'online',
      raw: {},
    ),
  ];
}

ConnectStatus _connectStatus() {
  return const ConnectStatus(
    stripeAccountId: 'acct_test_123',
    detailsSubmitted: true,
    payoutsEnabled: true,
    chargesEnabled: true,
    onboardingComplete: true,
  );
}

List<PromotionAdminItem> _promotions() {
  return [
    PromotionAdminItem.fromJson({
      'id': 1,
      'code': 'WELCOME20',
      'description': 'Nouveaux clients',
      'discount_type': 'percent',
      'discount_value': 20,
      'min_order_amount': 25,
      'starts_at': '2026-08-01T00:00:00Z',
      'ends_at': '2026-09-01T00:00:00Z',
      'is_active': true,
      'is_public': true,
      'is_stackable': false,
      'first_order_only': true,
      'max_uses': 200,
      'current_uses': 42,
      'remaining_uses': 158,
      'usage_count': 42,
      'unique_users': 39,
      'revenue_net': 1460.5,
      'discount_total': 292.1,
      'targets': {'category_ids': [], 'product_ids': []},
    }),
    PromotionAdminItem.fromJson({
      'id': 2,
      'code': 'MIDI5',
      'description': 'Service midi',
      'discount_type': 'fixed',
      'discount_value': 5,
      'min_order_amount': 18,
      'is_active': true,
      'is_public': true,
      'is_stackable': true,
      'max_uses_per_user': 2,
      'usage_count': 88,
      'current_uses': 88,
      'revenue_net': 980,
      'discount_total': 440,
      'targets': {
        'category_ids': [1],
        'product_ids': [],
      },
    }),
    PromotionAdminItem.fromJson({
      'id': 3,
      'code': 'SUMMER10',
      'description': 'Fin de saison',
      'discount_type': 'percent',
      'discount_value': 10,
      'starts_at': '2026-09-15T00:00:00Z',
      'is_active': true,
      'is_public': false,
      'usage_count': 0,
      'current_uses': 0,
      'revenue_net': 0,
      'discount_total': 0,
    }),
    PromotionAdminItem.fromJson({
      'id': 4,
      'code': 'OLDVIP',
      'discount_type': 'fixed',
      'discount_value': 8,
      'ends_at': '2026-07-01T00:00:00Z',
      'is_active': false,
      'is_public': false,
      'usage_count': 12,
      'current_uses': 12,
      'revenue_net': 310,
      'discount_total': 96,
    }),
  ];
}

LoyaltyConfig _loyaltyConfig() {
  return const LoyaltyConfig(
    id: 1,
    baseRatio: 1.2,
    pointsExpiryDays: 365,
    pointsToEuroRate: 0.02,
    maxCumulativeMultiplier: 4,
    isActive: true,
  );
}

LoyaltyStats _loyaltyStats() {
  return const LoyaltyStats(
    memberCount: 742,
    activeMemberCount: 318,
    pointsDistributed: 18420,
    pointsRedeemed: 6320,
    pointsExpired: 540,
    circulatingBalance: 11560,
    redemptionRate: 34.3,
  );
}

List<LoyaltyRule> _loyaltyRules() {
  return const [
    LoyaltyRule(
      id: 1,
      name: 'Premiere commande',
      ruleType: 'first_order',
      multiplier: 2,
      priority: 1,
      isActive: true,
    ),
    LoyaltyRule(
      id: 2,
      name: 'Mercredi midi',
      ruleType: 'day_multiplier',
      multiplier: 1.5,
      priority: 5,
      isActive: true,
    ),
    LoyaltyRule(
      id: 3,
      name: 'Categorie pizzas',
      ruleType: 'category_multiplier',
      multiplier: 1.2,
      priority: 8,
      isActive: false,
      categoryId: 1,
    ),
  ];
}

List<LoyaltyReward> _loyaltyRewards() {
  return const [
    LoyaltyReward(
      id: 1,
      name: '5 EUR de remise',
      rewardType: 'discount_euros',
      pointsRequired: 250,
      discountAmount: 5,
      isActive: true,
    ),
    LoyaltyReward(
      id: 2,
      name: 'Pizza offerte',
      rewardType: 'free_product',
      pointsRequired: 600,
      productId: 11,
      isActive: true,
    ),
    LoyaltyReward(
      id: 3,
      name: 'Ancien palier',
      rewardType: 'discount_euros',
      pointsRequired: 100,
      discountAmount: 2,
      isActive: false,
    ),
  ];
}

List<DeliveryZone> _deliveryZones() {
  return [
    DeliveryZone.fromJson({
      'id': 1,
      'name': 'Centre-ville',
      'fee': 3.5,
      'min_order_amount': 18,
      'estimated_minutes': 25,
      'is_active': true,
      'polygon': {
        'type': 'Polygon',
        'coordinates': [
          [
            [2.34, 48.85],
            [2.35, 48.86],
            [2.36, 48.85],
            [2.34, 48.85],
          ],
        ],
      },
    }),
    DeliveryZone.fromJson({
      'id': 2,
      'name': 'Nord',
      'fee': 4.5,
      'min_order_amount': 22,
      'estimated_minutes': 35,
      'is_active': true,
    }),
    DeliveryZone.fromJson({
      'id': 3,
      'name': 'Sud archive',
      'fee': 5.5,
      'min_order_amount': 28,
      'estimated_minutes': 40,
      'is_active': false,
    }),
  ];
}

TenantConfig _tenantConfig() {
  return TenantConfig(
    id: 1,
    isTemporarilyClosed: false,
    defaultClosureMessage: 'Service momentanement ferme',
    prepTimeNormalMinutes: 20,
    prepTimePeakMinutes: 35,
    peakOrdersThreshold: 8,
    autoCalcPrepTime: true,
    overheadPerOrderMinutes: 3,
    timezone: 'Europe/Paris',
    largeStockAdjustmentThreshold: 25,
    printEnabled: true,
    printConfig: const {'kitchen_printer': 'Cuisine'},
    updatedAt: DateTime(2026, 8, 10, 9),
  );
}

List<BusinessHour> _businessHours() {
  return List.generate(
    7,
    (day) => BusinessHour(
      id: day + 1,
      dayOfWeek: day,
      slotIndex: 0,
      opensAt: day == 0 ? '18:00:00' : '11:30:00',
      closesAt: '22:30:00',
      isActive: day != 6,
    ),
  );
}

List<ExceptionalClosure> _closures() {
  return [
    ExceptionalClosure(
      id: 1,
      closureDate: '2026-08-15',
      useDefaultMessage: false,
      customMessage: 'Equipe en evenement local',
      createdAt: DateTime(2026, 8, 1),
    ),
  ];
}

List<TenantAuditEntry> _tenantAudit() {
  return [
    TenantAuditEntry(
      id: 1,
      changedByUserId: 10,
      userEmail: 'admin@test.local',
      fieldName: 'prep_time_peak_minutes',
      oldValue: '30',
      newValue: '35',
      changedAt: DateTime(2026, 8, 10, 9),
    ),
  ];
}

TenantPrintConfig _printConfig() {
  return const TenantPrintConfig(
    enabled: true,
    config: {'kitchen_printer': 'Cuisine', 'counter_printer': 'Comptoir'},
  );
}

List<AuthSession> _authSessions() {
  return [
    AuthSession(
      id: 1,
      createdAt: DateTime(2026, 8, 10, 8),
      expiresAt: DateTime(2026, 8, 11, 8),
      isCurrent: true,
      userAgent: 'Flutter test',
      ipAddress: '127.0.0.1',
    ),
  ];
}

class _AdminSessionController extends SessionController {
  @override
  Future<SessionState> build() async {
    return SessionState.authenticated(
      user: _sessionUser(role: 'admin', permissions: null),
      tenantSlug: 'pizza',
      sessionId: 1,
    );
  }
}

class _StaffSessionController extends SessionController {
  @override
  Future<SessionState> build() async {
    return SessionState.authenticated(
      user: _sessionUser(
        role: 'staff',
        permissions: AppPermission.staffDefaults,
      ),
      tenantSlug: 'pizza',
      sessionId: 2,
    );
  }
}

StaffUser _sessionUser({
  required String role,
  required Set<String>? permissions,
}) {
  return StaffUser(
    id: role == 'admin' ? 10 : 11,
    email: role == 'admin' ? 'admin@test.local' : 'staff@test.local',
    fullName: role == 'admin' ? 'Nora Admin' : 'Yanis Costa',
    role: role,
    tenantSlug: 'pizza',
    permissions: permissions,
    mustChangePassword: false,
    isActive: true,
    emailVerified: true,
  );
}

class _EmptySyncQueue extends SyncQueue {
  @override
  List<QueuedAction> build() => const [];
}

class _EmptyNotificationBus extends NotificationBus {
  @override
  List<RealtimeNotification> build() => const [];
}
