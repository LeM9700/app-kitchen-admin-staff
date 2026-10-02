class CheckoutValidationInput {
  const CheckoutValidationInput({
    required this.hasItems,
    required this.orderType,
    required this.paymentMethod,
    required this.deliveryAddress,
    required this.externalReference,
    required this.loyaltyCustomerId,
    required this.loyaltyRewardId,
    required this.loyaltyOralConfirmed,
    required this.total,
    required this.amountReceived,
    required this.isOnline,
    required this.isRestaurantOpen,
    this.cartEstablishmentId,
    this.currentEstablishmentId,
    this.customerPhone = '',
    this.customerEmail = '',
    this.deliveryZoneId,
  });

  final bool hasItems;
  final String orderType;
  final String paymentMethod;
  final String deliveryAddress;
  final String externalReference;
  final int? loyaltyCustomerId;
  final int? loyaltyRewardId;
  final bool loyaltyOralConfirmed;
  final double total;
  final double? amountReceived;
  final bool isOnline;
  final bool isRestaurantOpen;
  final int? cartEstablishmentId;
  final int? currentEstablishmentId;
  final String customerPhone;
  final String customerEmail;
  final int? deliveryZoneId;
}

/// Meme regle que l'API (`orders/schemas.py::_PHONE_RE`) : chiffres, espaces,
/// `+ ( ) . -`, 6 a 32 caracteres, avec au moins 6 chiffres.
bool isValidCustomerPhone(String value) {
  final phone = value.trim();
  if (!RegExp(r'^\+?[0-9 ().-]{6,32}$').hasMatch(phone)) {
    return false;
  }
  return phone.replaceAll(RegExp(r'[^0-9]'), '').length >= 6;
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
  if (input.orderType == 'delivery' && input.customerPhone.trim().isEmpty) {
    return const CheckoutValidationResult.invalid(
      'Telephone requis pour une livraison',
    );
  }
  if (input.customerPhone.trim().isNotEmpty &&
      !isValidCustomerPhone(input.customerPhone)) {
    return const CheckoutValidationResult.invalid('Telephone invalide');
  }
  if (input.orderType == 'delivery' && input.deliveryZoneId == null) {
    return const CheckoutValidationResult.invalid(
      'Zone de livraison requise : elle determine les frais',
    );
  }
  if (input.orderType == 'delivery' && input.paymentMethod == 'cash') {
    // Especes non encaissees au comptoir : le client doit laisser une empreinte (lien).
    return const CheckoutValidationResult.invalid(
      'Livraison : envoyez un lien de paiement (empreinte bancaire) au lieu des especes',
    );
  }
  if (input.paymentMethod == 'payment_link') {
    if (input.orderType == 'dine_in') {
      return const CheckoutValidationResult.invalid(
        'Le lien de paiement n\'est pas disponible pour une commande sur place',
      );
    }
    if (input.customerPhone.trim().isEmpty &&
        input.customerEmail.trim().isEmpty) {
      return const CheckoutValidationResult.invalid(
        'Telephone ou email requis pour envoyer le lien de paiement',
      );
    }
  }
  if ({'external_terminal', 'cash_register'}.contains(input.paymentMethod) &&
      input.externalReference.trim().isEmpty) {
    return const CheckoutValidationResult.invalid(
      'Reference externe requise pour ce paiement',
    );
  }
  if (input.loyaltyRewardId != null && input.loyaltyCustomerId == null) {
    return const CheckoutValidationResult.invalid(
      'Client fidelite requis pour appliquer une recompense',
    );
  }
  if (input.loyaltyRewardId != null && !input.loyaltyOralConfirmed) {
    return const CheckoutValidationResult.invalid(
      'Confirmation orale client requise pour appliquer la recompense',
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
