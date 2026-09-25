import 'package:app_admin_staff/features/stock/data/stock_repository.dart';

enum StockDerivedStatus {
  normal,
  low,
  out,
}

StockDerivedStatus stockStatusOf(Ingredient ingredient) {
  if (ingredient.currentQty <= 0) {
    return StockDerivedStatus.out;
  }
  if (ingredient.isBelowThreshold) {
    return StockDerivedStatus.low;
  }
  return StockDerivedStatus.normal;
}

bool matchesStockFilter(Ingredient ingredient, StockLevelFilter filter) {
  return switch (filter) {
    StockLevelFilter.all => true,
    StockLevelFilter.low => ingredient.isBelowThreshold,
    StockLevelFilter.out => ingredient.currentQty <= 0,
  };
}

String formatStockQty(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

String formatSignedQty(double value) {
  final sign = value >= 0 ? '+' : '';
  return '$sign${formatStockQty(value)}';
}

double stockThresholdRatio(Ingredient ingredient) {
  if (ingredient.alertThreshold <= 0) {
    return ingredient.currentQty > 0 ? 1 : 0;
  }
  return (ingredient.currentQty / ingredient.alertThreshold).clamp(0, 1.4);
}

bool hasDlcRisk(IngredientBatch batch, DateTime now) {
  final target = batch.effectiveExpiresAt ?? batch.expiresAt;
  if (target == null) {
    return false;
  }
  return target.difference(now).inHours <= 24;
}
