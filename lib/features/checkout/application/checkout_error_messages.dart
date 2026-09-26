import 'package:app_admin_staff/core/api/api_error.dart';

enum CheckoutFailureContext {
  checkout,
  loyaltySearch,
  loyaltyQr,
  loyaltyCustomer,
  loyaltyCreate,
}

String checkoutFailureMessage(
  Object error, {
  CheckoutFailureContext context = CheckoutFailureContext.checkout,
}) {
  if (error is NetworkException) {
    return 'Connexion serveur indisponible. La fidelite ne peut pas etre appliquee hors ligne.';
  }

  if (error is AppException) {
    final code = error.code;
    final field = error.field;
    final message = error.message;
    if (code == 'LOYALTY_QR_EXPIRED') {
      return 'QR fidelite expire. Demandez au client de generer un nouveau QR.';
    }
    if (code == 'INVALID_LOYALTY_QR') {
      return 'QR fidelite invalide. Scannez le QR depuis son espace fidelite.';
    }
    if (code == 'PHONE_NOT_VERIFIED') {
      return 'Telephone non verifie. Le client doit confirmer son numero dans son application avant utilisation.';
    }
    if (code == 'LOYALTY_USER_REQUIRED' || field == 'loyalty_customer_id') {
      return 'Client fidelite requis. Identifiez le client par telephone ou QR avant la recompense.';
    }
    if (code == 'REWARD_NOT_FOUND') {
      return 'Recompense indisponible. Rafraichissez la caisse puis choisissez une autre recompense.';
    }
    if (code == 'INVALID_REWARD') {
      return 'Recompense mal configuree. Choisissez une autre recompense et signalez-la a l admin.';
    }
    if (code == 'INSUFFICIENT_POINTS') {
      return 'Solde insuffisant pour cette recompense.';
    }
    if (code == 'REWARD_PRODUCT_REQUIRED') {
      return 'Produit requis absent du panier. Ajoutez le produit concerne ou choisissez une autre recompense.';
    }
    if (field == 'loyalty_identification_method') {
      return 'Methode identification fidelite manquante. Recommencez l identification du client.';
    }
    if (field == 'loyalty_oral_confirmed' ||
        message.toLowerCase().contains('confirmation orale')) {
      return 'Confirmation orale requise. Cochez la validation client avant d appliquer la recompense.';
    }
    if (message.trim().isNotEmpty) {
      return message;
    }
  }

  return switch (context) {
    CheckoutFailureContext.loyaltySearch =>
      'Recherche fidelite impossible. Verifiez le numero puis reessayez.',
    CheckoutFailureContext.loyaltyQr =>
      'Scan QR fidelite impossible. Demandez au client d afficher un nouveau QR.',
    CheckoutFailureContext.loyaltyCustomer =>
      'Chargement du client fidelite impossible. Reessayez l identification.',
    CheckoutFailureContext.loyaltyCreate =>
      'Creation du client fidelite impossible. Verifiez le telephone puis reessayez.',
    CheckoutFailureContext.checkout =>
      'Encaissement impossible. Verifiez puis reessayez.',
  };
}
