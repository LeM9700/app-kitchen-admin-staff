import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/checkout/domain/checkout_cart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pizza = CatalogProduct(
    id: 10,
    name: 'Margherita',
    basePrice: 12,
    isActive: true,
    effectivePreparationStation: 'kitchen',
  );
  const small = CatalogVariant(
    id: 1,
    productId: 10,
    name: 'Petite',
    priceDelta: 0,
    isActive: true,
  );
  const large = CatalogVariant(
    id: 2,
    productId: 10,
    name: 'Grande',
    priceDelta: 4,
    isActive: true,
  );
  const mozzarella = CatalogExtra(
    id: 30,
    name: 'Mozzarella',
    price: 1.5,
    isActive: true,
  );
  const olives = CatalogExtra(
    id: 31,
    name: 'Olives',
    price: 1,
    isActive: true,
  );

  test('additionne base, variante et extras', () {
    const line = CheckoutCartLine(
      product: pizza,
      quantity: 2,
      variant: large,
      extras: [mozzarella, olives],
    );

    expect(line.unitPrice, 18.5);
    expect(line.total, 37);
  });

  test('garde deux variantes sur deux lignes distinctes', () {
    const smallSelection = CheckoutCartSelection(
      product: pizza,
      variant: small,
    );
    const largeSelection = CheckoutCartSelection(
      product: pizza,
      variant: large,
    );

    expect(smallSelection.key, isNot(largeSelection.key));
  });

  test('garde deux configurations extras sur deux lignes distinctes', () {
    const mozzarellaSelection = CheckoutCartSelection(
      product: pizza,
      extras: [mozzarella],
    );
    const olivesSelection = CheckoutCartSelection(
      product: pizza,
      extras: [olives],
    );

    expect(mozzarellaSelection.key, isNot(olivesSelection.key));
  });

  test('la cle panier ne depend pas de l ordre des extras', () {
    const first = CheckoutCartSelection(
      product: pizza,
      extras: [mozzarella, olives],
    );
    const second = CheckoutCartSelection(
      product: pizza,
      extras: [olives, mozzarella],
    );

    expect(first.key, second.key);
  });

  test('increment et decrement conservent la ligne', () {
    const line = CheckoutCartLine(product: pizza, quantity: 1);

    final incremented = line.copyWith(quantity: line.quantity + 1);
    final decremented =
        incremented.copyWith(quantity: incremented.quantity - 1);

    expect(incremented.quantity, 2);
    expect(decremented.quantity, 1);
  });

  test('total panier additionne les lignes', () {
    const lines = [
      CheckoutCartLine(product: pizza, quantity: 1, variant: large),
      CheckoutCartLine(product: pizza, quantity: 2, extras: [olives]),
    ];

    expect(checkoutCartTotal(lines), 42);
  });
}
