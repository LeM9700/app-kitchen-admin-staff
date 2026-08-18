class ApiEndpoints {
  static const authLogin = '/auth/login';
  static const authRefresh = '/auth/refresh';
  static const authLogout = '/auth/logout';
  static const authMe = '/auth/me';
  static const authChangePassword = '/auth/change-password';
  static const authSessions = '/auth/sessions';
  static String authSession(int sessionId) => '/auth/sessions/$sessionId';

  static const orders = '/orders';
  static const manualOrder = '/orders/manual';
  static const ordersExportCsv = '/orders/export/csv';
  static String orderDetail(int orderId) => '/orders/$orderId';
  static String orderStatus(int orderId) => '/orders/$orderId/status';
  static String orderCancel(int orderId) => '/orders/$orderId/cancel';
  static String orderReceipt(int orderId) => '/orders/$orderId/receipt';
  static String orderItemPreparation(int orderId, int itemId) {
    return '/orders/$orderId/items/$itemId/preparation';
  }

  static const kdsScreens = '/kds/screens';
  static String kdsScreen(int screenId) => '/kds/screens/$screenId';
  static const kdsPair = '/kds/pair';
  static const kdsRemoteSession = '/kds/remote/session';
  static const kdsRemoteSessionRevoke = '/kds/remote/session/revoke';
  static String kdsScreenPairingCode(int screenId) {
    return '/kds/screens/$screenId/pairing-code';
  }

  static String kdsScreenRevokeSessions(int screenId) {
    return '/kds/screens/$screenId/revoke-sessions';
  }

  static const catalogProducts = '/catalog/products';
  static const catalogCategories = '/catalog/categories';
  static const catalogExtras = '/catalog/extras';
  static const catalogExportCsv = '/catalog/exports/csv';
  static const catalogImportDryRun = '/catalog/imports/csv/dry-run';
  static const catalogCompleteness = '/catalog/admin/completeness';
  static String catalogProduct(int productId) => '/catalog/products/$productId';
  static String catalogProductVariants(int productId) {
    return '/catalog/products/$productId/variants';
  }

  static String catalogProductVariant(int productId, int variantId) {
    return '/catalog/products/$productId/variants/$variantId';
  }

  static String catalogProductExtras(int productId) {
    return '/catalog/products/$productId/extras';
  }

  static String catalogProductExtra(int productId, int extraId) {
    return '/catalog/products/$productId/extras/$extraId';
  }

  static String catalogProductRecommendations(int productId) {
    return '/catalog/products/$productId/recommendations';
  }

  static String catalogProductRecommendation(
    int productId,
    int recommendationId,
  ) {
    return '/catalog/products/$productId/recommendations/$recommendationId';
  }

  static String catalogEntityImages(String entityType, int entityId) {
    return '/catalog/$entityType/$entityId/images';
  }

  static String catalogEntityImagesReorder(String entityType, int entityId) {
    return '/catalog/$entityType/$entityId/images/reorder';
  }

  static String catalogImage(int imageId) => '/catalog/images/$imageId';
  static String catalogImagePrimary(int imageId) {
    return '/catalog/images/$imageId/primary';
  }

  static const catalogAllergens = '/catalog/allergens';
  static const catalogDietaryTags = '/catalog/dietary-tags';
  static String catalogProductAllergens(int productId) {
    return '/catalog/products/$productId/allergens';
  }

  static String catalogProductAllergen(int productId, int allergenId) {
    return '/catalog/products/$productId/allergens/$allergenId';
  }

  static String catalogProductAllergensRecompute(int productId) {
    return '/catalog/products/$productId/allergens/recompute';
  }

  static String catalogProductDietaryTags(int productId) {
    return '/catalog/products/$productId/dietary-tags';
  }

  static String catalogExtra(int extraId) => '/catalog/extras/$extraId';

  static String catalogPriceAudit(String entityType, int entityId) {
    return '/catalog/price-audit/$entityType/$entityId';
  }

  static String catalogImportConfirm(String token) {
    return '/catalog/imports/csv/$token/confirm';
  }

  static String productAvailabilityOverride(int productId) {
    return '/catalog/products/$productId/availability-override';
  }

  static String productAvailabilityHistory(int productId) {
    return '/catalog/products/$productId/availability-history';
  }

  static const stockIngredients = '/stock/ingredients';
  static const stockSupply = '/stock/supply';
  static const stockAdjustmentRequests = '/stock/adjustment-requests';
  static const stockAlerts = '/stock/alerts';
  static const stockMovements = '/stock/movements';
  static const stockRecipeProduct = '/stock/recipes';
  static const stockRecipeVariant = '/stock/recipes/variant';
  static const stockRecipeExtra = '/stock/recipes/extra';
  static String stockIngredientBatches(int ingredientId) {
    return '/stock/ingredients/$ingredientId/batches';
  }

  static String stockBatchOpen(int batchId) => '/stock/batches/$batchId/open';
  static String stockBatchDiscard(int batchId) {
    return '/stock/batches/$batchId/discard';
  }

  static String stockAdjustmentApprove(int requestId) {
    return '/stock/adjustment-requests/$requestId/approve';
  }

  static String stockAdjustmentReject(int requestId) {
    return '/stock/adjustment-requests/$requestId/reject';
  }

  static const payments = '/payments';
  static const paymentSummary = '/payments/summary';
  static const paymentsExportCsv = '/payments/export/csv';
  static const connectOnboarding = '/payments/connect/onboarding';
  static const connectStatus = '/payments/connect/status';
  static const connectDashboard = '/payments/connect/dashboard';
  static const terminalConnectionToken = '/payments/terminal/connection-token';
  static const terminalIntent = '/payments/terminal/intent';
  static const terminalReaders = '/payments/terminal/readers';
  static const localTestPaymentConfirm = '/payments/local-test/confirm';
  static String paymentDetail(int orderId) => '/payments/$orderId';
  static String paymentRefund(int orderId) => '/payments/$orderId/refund';
  static String terminalReaderProcess(String readerId) {
    return '/payments/terminal/readers/$readerId/process';
  }

  static String terminalReaderCancel(String readerId) {
    return '/payments/terminal/readers/$readerId/cancel';
  }

  static const tenantStatus = '/tenant/status';
  static const tenantConfig = '/tenant/config';
  static const tenantHours = '/tenant/hours';
  static const tenantClosures = '/tenant/closures';
  static const tenantAudit = '/tenant/audit';
  static const tenantPrintConfig = '/tenant/print-config';
  static const tenantToggleClosure = '/tenant/toggle-closure';
  static const tenantEstablishments = '/tenant/establishments';
  static String tenantHoursDay(int day) => '/tenant/hours/$day';
  static String tenantClosure(int closureId) => '/tenant/closures/$closureId';

  static const deliveryZones = '/delivery/zones';
  static const deliveryCheck = '/delivery/check';
  static String deliveryZone(int zoneId) => '/delivery/zones/$zoneId';

  static const loyaltyConfig = '/loyalty/config';
  static const loyaltyRules = '/loyalty/rules';
  static const loyaltyRewards = '/loyalty/rewards';
  static const loyaltyStats = '/loyalty/stats';
  static String loyaltyRule(int ruleId) => '/loyalty/rules/$ruleId';
  static String loyaltyReward(int rewardId) => '/loyalty/rewards/$rewardId';
  static String loyaltyUser(int userId) => '/loyalty/users/$userId';
  static String loyaltyUserTransactions(int userId) {
    return '/loyalty/users/$userId/transactions';
  }

  static const promotions = '/promotions';
  static const promotionsAdmin = '/promotions/admin';
  static const promotionsBulkGenerate = '/promotions/bulk-generate';
  static const promotionsCleanupExpired = '/promotions/cleanup-expired';
  static String promotion(int promoId) => '/promotions/$promoId';
  static String promotionToggle(int promoId) => '/promotions/$promoId/toggle';
  static String promotionUsages(int promoId) => '/promotions/$promoId/usages';

  static const adminStatsLive = '/admin/stats/live';
  static const adminStatsStock = '/admin/stats/stock';
  static const adminStatsSummary = '/admin/stats/summary';
  static const adminStatsDaily = '/admin/stats/daily';
  static const adminStatsMonthly = '/admin/stats/monthly';
  static const adminStatsTopProducts = '/admin/stats/top-products';

  static const adminUsers = '/admin/users';
  static String adminUserPermissions(int userId) {
    return '/admin/users/$userId/permissions';
  }

  static String adminUserDeactivate(int userId) {
    return '/admin/users/$userId/deactivate';
  }

  static String adminUserReactivate(int userId) {
    return '/admin/users/$userId/reactivate';
  }

  static String adminUserResetPassword(int userId) {
    return '/admin/users/$userId/reset-password';
  }

  static const hrEmployees = '/hr/employees';
  static const hrEmployeeMe = '/hr/employees/me';
  static String hrEmployee(int employeeId) => '/hr/employees/$employeeId';

  static const hrShifts = '/hr/shifts';
  static const hrShiftsMe = '/hr/shifts/me';
  static String hrShift(int shiftId) => '/hr/shifts/$shiftId';

  static const hrClockIn = '/hr/timeclock/clock-in';
  static const hrClockOut = '/hr/timeclock/clock-out';
  static const hrTimeClockEntries = '/hr/timeclock/entries';
  static const hrTimeClockEntriesMe = '/hr/timeclock/entries/me';
  static String hrTimeClockEntry(int entryId) {
    return '/hr/timeclock/entries/$entryId';
  }

  static const hrAlerts = '/hr/alerts';
  static String hrAlertResolve(int alertId) => '/hr/alerts/$alertId/resolve';

  static const notificationsWs = '/ws/notifications';
}
