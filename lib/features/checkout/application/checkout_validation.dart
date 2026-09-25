class CheckoutValidationInput {
  const CheckoutValidationInput({
    required this.hasItems,
    required this.orderType,
    required this.paymentMethod,
    required this.deliveryAddress,
    required this.externalReference,
    required this.loyaltyUserId,
    required this.loyaltyPointsToUse,
    required this.total,
    required this.amountReceived,
    required this.isOnline,
    required this.isRestaurantOpen,
    this.cartEstablishmentId,
    this.currentEstablishmentId,
  });

  final bool hasItems;
  final String orderType;
  final String paymentMethod;
  final String deliveryAddress;
  final String externalReference;
  final int? loyaltyUserId;
  final int? loyaltyPointsToUse;
  final double total;
  final double? amountReceived;
  final bool isOnline;
  final bool isRestaurantOpen;
  final int? cartEstablishmentId;
  final int? currentEstablishmentId;
}

class CheckoutValidationResult {
  const CheckoutValidationResult.valid() : message = null;

  const CheckoutValidationResult.invalid(this.message);

  final String? message;

  bool get isValid => message == null;
}

CheckoutValidationResult validateCheckout(CheckoutValidationInput input) {
  if (!input.isOnline) {
    return const CheckoutValidationResult.invalid(
      'Connexion indisponible. Encaissement bloque tant que le serveur ne confirme pas.',
    );
  }
  if (!input.isRestaurantOpen) {
    return const CheckoutValidationResult.invalid(
      'Restaurant ferme. Les commandes manuelles sont indisponibles.',
    );
  }
  if (!input.hasItems) {
    return const CheckoutValidationResult.invalid('Panier vide');
  }
  if (input.cartEstablishmentId != null &&
      input.currentEstablishmentId != null &&
      input.cartEstablishmentId != input.currentEstablishmentId) {
    return const CheckoutValidationResult.invalid(
      'Le panier appartient a un autre etablissement. Videz-le puis recommencez.',
    );
  }
  if (input.orderType == 'delivery' && input.deliveryAddress.trim().isEmpty) {
    return const CheckoutValidationResult.invalid(
      'Adresse requise pour une livraison',
    );
  }
  if ({'external_terminal', 'cash_register'}.contains(input.paymentMethod) &&
      input.externalReference.trim().isEmpty) {
    return const CheckoutValidationResult.invalid(
      'Reference externe requise pour ce paiement',
    );
  }
  if (input.loyaltyPointsToUse != null && input.loyaltyUserId == null) {
    return const CheckoutValidationResult.invalid(
      'User ID fidelite requis pour utiliser des points',
    );
  }
  if (input.paymentMethod == 'cash' &&
      input.amountReceived != null &&
      input.amountReceived! < input.total) {
    return const CheckoutValidationResult.invalid(
      'Montant recu insuffisant',
    );
  }
  return const CheckoutValidationResult.valid();
}
