import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void invalidateEstablishmentScopedProviders(WidgetRef ref) {
  ref
    ..invalidate(catalogProductsProvider)
    ..invalidate(catalogCategoriesProvider)
    ..invalidate(ingredientsProvider)
    ..invalidate(stockAlertsProvider)
    ..invalidate(stockMovementsProvider)
    ..invalidate(adjustmentRequestsProvider)
    ..invalidate(paymentsSummaryProvider)
    ..invalidate(paymentsProvider)
    ..invalidate(tenantStatusProvider)
    ..invalidate(tenantConfigProvider)
    ..invalidate(tenantBusinessHoursProvider)
    ..invalidate(tenantClosuresProvider);
}
