import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';

class CheckoutCartSelection {
  const CheckoutCartSelection({
    required this.product,
    this.variant,
    this.extras = const [],
  });

  final CatalogProduct product;
  final CatalogVariant? variant;
  final List<CatalogExtra> extras;

  String get key => checkoutCartKey(
        productId: product.id,
        variantId: variant?.id,
        extras: extras,
      );

  double get unitPrice => checkoutLineUnitPrice(
        product: product,
        variant: variant,
        extras: extras,
      );
}

class CheckoutCartLine {
  const CheckoutCartLine({
    required this.product,
    required this.quantity,
    this.variant,
    this.extras = const [],
  });

  final CatalogProduct product;
  final int quantity;
  final CatalogVariant? variant;
  final List<CatalogExtra> extras;

  String get key => checkoutCartKey(
        productId: product.id,
        variantId: variant?.id,
        extras: extras,
      );

  double get unitPrice => checkoutLineUnitPrice(
        product: product,
        variant: variant,
        extras: extras,
      );

  double get total => unitPrice * quantity;

  CheckoutCartLine copyWith({int? quantity}) {
    return CheckoutCartLine(
      product: product,
      quantity: quantity ?? this.quantity,
      variant: variant,
      extras: extras,
    );
  }
}

String checkoutCartKey({
  required int productId,
  int? variantId,
  List<CatalogExtra> extras = const [],
}) {
  final extraIds = extras.map((extra) => extra.id).toList()..sort();
  return [
    productId,
    variantId ?? 'base',
    ...extraIds,
  ].join(':');
}

double checkoutLineUnitPrice({
  required CatalogProduct product,
  CatalogVariant? variant,
  List<CatalogExtra> extras = const [],
}) {
  return product.basePrice +
      (variant?.priceDelta ?? 0) +
      extras.fold<double>(0, (sum, extra) => sum + extra.price);
}

double checkoutCartTotal(Iterable<CheckoutCartLine> lines) {
  return lines.fold<double>(0, (sum, line) => sum + line.total);
}
