import 'package:app_admin_staff/features/checkout/application/checkout_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CheckoutValidationInput input({
    bool hasItems = true,
    String orderType = 'pickup',
    String paymentMethod = 'cash',
    String deliveryAddress = '',
    String externalReference = '',
    int? loyaltyUserId,
    int? loyaltyPointsToUse,
    double total = 24,
    double? amountReceived,
    bool isOnline = true,
    bool isRestaurantOpen = true,
    int? cartEstablishmentId = 1,
    int? currentEstablishmentId = 1,
  }) {
    return CheckoutValidationInput(
      hasItems: hasItems,
      orderType: orderType,
      paymentMethod: paymentMethod,
      deliveryAddress: deliveryAddress,
      externalReference: externalReference,
      loyaltyUserId: loyaltyUserId,
      loyaltyPointsToUse: loyaltyPointsToUse,
      total: total,
      amountReceived: amountReceived,
      isOnline: isOnline,
      isRestaurantOpen: isRestaurantOpen,
      cartEstablishmentId: cartEstablishmentId,
      currentEstablishmentId: currentEstablishmentId,
    );
  }

  test('refuse un panier vide', () {
    final result = validateCheckout(input(hasItems: false));

    expect(result.isValid, isFalse);
    expect(result.message, 'Panier vide');
  });

  test('refuse une livraison sans adresse', () {
    final result = validateCheckout(input(orderType: 'delivery'));

    expect(result.isValid, isFalse);
    expect(result.message, contains('Adresse'));
  });

  test('refuse un TPE sans reference externe', () {
    final result = validateCheckout(
      input(paymentMethod: 'external_terminal'),
    );

    expect(result.isValid, isFalse);
    expect(result.message, contains('Reference externe'));
  });

  test('refuse une caisse externe sans reference externe', () {
    final result = validateCheckout(input(paymentMethod: 'cash_register'));

    expect(result.isValid, isFalse);
    expect(result.message, contains('Reference externe'));
  });

  test('accepte le cash sans montant recu', () {
    final result = validateCheckout(input(paymentMethod: 'cash'));

    expect(result.isValid, isTrue);
  });

  test('refuse le cash si le montant recu est insuffisant', () {
    final result = validateCheckout(
      input(paymentMethod: 'cash', amountReceived: 20),
    );

    expect(result.isValid, isFalse);
    expect(result.message, 'Montant recu insuffisant');
  });

  test('accepte le cash si le montant recu couvre le total', () {
    final result = validateCheckout(
      input(paymentMethod: 'cash', amountReceived: 30),
    );

    expect(result.isValid, isTrue);
  });

  test('refuse des points fidelite sans user id', () {
    final result = validateCheckout(input(loyaltyPointsToUse: 120));

    expect(result.isValid, isFalse);
    expect(result.message, contains('fidelite'));
  });

  test('refuse le submit hors ligne', () {
    final result = validateCheckout(input(isOnline: false));

    expect(result.isValid, isFalse);
    expect(result.message, contains('Connexion'));
  });

  test('refuse le submit restaurant ferme', () {
    final result = validateCheckout(input(isRestaurantOpen: false));

    expect(result.isValid, isFalse);
    expect(result.message, contains('Restaurant ferme'));
  });

  test('refuse un panier cree sur un autre etablissement', () {
    final result = validateCheckout(
      input(cartEstablishmentId: 1, currentEstablishmentId: 2),
    );

    expect(result.isValid, isFalse);
    expect(result.message, contains('autre etablissement'));
  });
}
