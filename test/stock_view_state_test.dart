import 'package:app_admin_staff/features/stock/application/stock_view_state.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('derives stock status from current quantity and threshold flag', () {
    expect(
      stockStatusOf(_ingredient(currentQty: 8)),
      StockDerivedStatus.normal,
    );
    expect(
      stockStatusOf(_ingredient(currentQty: 3, isBelowThreshold: true)),
      StockDerivedStatus.low,
    );
    expect(
      stockStatusOf(_ingredient(currentQty: 0, isBelowThreshold: true)),
      StockDerivedStatus.out,
    );
  });

  test('matches all, low and out filters locally', () {
    final normal = _ingredient(currentQty: 8);
    final low = _ingredient(currentQty: 2, isBelowThreshold: true);
    final out = _ingredient(currentQty: 0, isBelowThreshold: true);

    expect(matchesStockFilter(normal, StockLevelFilter.all), isTrue);
    expect(matchesStockFilter(low, StockLevelFilter.low), isTrue);
    expect(matchesStockFilter(out, StockLevelFilter.out), isTrue);
    expect(matchesStockFilter(normal, StockLevelFilter.low), isFalse);
    expect(matchesStockFilter(low, StockLevelFilter.out), isFalse);
  });

  test('formats stock quantities and signed movement deltas', () {
    expect(formatStockQty(4), '4');
    expect(formatStockQty(4.5), '4.5');
    expect(formatStockQty(4.25), '4.25');
    expect(formatSignedQty(3), '+3');
    expect(formatSignedQty(-1.5), '-1.5');
  });

  test('uses threshold ratio as a bounded threshold indicator', () {
    expect(stockThresholdRatio(_ingredient(currentQty: 5)), 1);
    expect(stockThresholdRatio(_ingredient(currentQty: 1)), 0.2);
    expect(stockThresholdRatio(_ingredient(currentQty: 50)), 1.4);
    expect(
      stockThresholdRatio(_ingredient(currentQty: 2, alertThreshold: 0)),
      1,
    );
  });

  test('detects DLC risk in the next 24 hours', () {
    final now = DateTime(2026, 9, 25, 12);

    expect(
      hasDlcRisk(
        IngredientBatch(
          id: 1,
          ingredientId: 2,
          quantity: 1,
          status: 'sealed',
          expiresAt: now.add(const Duration(hours: 23)),
        ),
        now,
      ),
      isTrue,
    );
    expect(
      hasDlcRisk(
        IngredientBatch(
          id: 1,
          ingredientId: 2,
          quantity: 1,
          status: 'sealed',
          expiresAt: now.add(const Duration(hours: 30)),
        ),
        now,
      ),
      isFalse,
    );
  });
}

Ingredient _ingredient({
  double currentQty = 5,
  double alertThreshold = 5,
  bool isBelowThreshold = false,
}) {
  return Ingredient(
    id: 1,
    name: 'Mozzarella',
    unit: 'kg',
    currentQty: currentQty,
    alertThreshold: alertThreshold,
    isBelowThreshold: isBelowThreshold,
  );
}
