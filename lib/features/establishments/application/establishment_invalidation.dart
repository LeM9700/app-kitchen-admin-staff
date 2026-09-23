import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/dashboard/data/dashboard_repository.dart';
import 'package:app_admin_staff/features/hr/data/hr_repository.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void invalidateEstablishmentScopedProviders(WidgetRef ref) {
  ref
    ..invalidate(catalogProductsProvider)
    ..invalidate(catalogCategoriesProvider)
    ..invalidate(activeOrdersProvider)
    ..invalidate(liveStatsProvider)
    ..invalidate(statsSummaryProvider)
    ..invalidate(dailyStatsProvider)
    ..invalidate(monthlyStatsProvider)
    ..invalidate(topProductsProvider)
    ..invalidate(groupOverviewProvider)
    ..invalidate(ingredientsProvider)
    ..invalidate(stockAlertsProvider)
    ..invalidate(stockMovementsProvider)
    ..invalidate(adjustmentRequestsProvider)
    ..invalidate(paymentsSummaryProvider)
    ..invalidate(paymentsProvider)
    ..invalidate(tenantStatusProvider)
    ..invalidate(tenantConfigProvider)
    ..invalidate(tenantBusinessHoursProvider)
    ..invalidate(tenantClosuresProvider)
    ..invalidate(myEmployeeProfileProvider)
    ..invalidate(employeesProvider)
    ..invalidate(shiftsProvider)
    ..invalidate(myShiftsProvider)
    ..invalidate(timeClockEntriesProvider)
    ..invalidate(myTimeClockEntriesProvider)
    ..invalidate(hrAlertsProvider);
}
