import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/features/checkout/application/checkout_error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explique un QR fidelite expire', () {
    final message = checkoutFailureMessage(
      const BusinessException(
        message: 'QR fidelite expire',
        code: 'LOYALTY_QR_EXPIRED',
      ),
      context: CheckoutFailureContext.loyaltyQr,
    );

    expect(message, contains('QR fidelite expire'));
    expect(message, contains('nouveau'));
  });

  test('explique un QR fidelite invalide', () {
    final message = checkoutFailureMessage(
      const BusinessException(
        message: 'QR fidelite invalide',
        code: 'INVALID_LOYALTY_QR',
      ),
      context: CheckoutFailureContext.loyaltyQr,
    );

    expect(message, contains('QR fidelite invalide'));
    expect(message, contains('espace fidelite'));
  });

  test('explique un telephone non verifie', () {
    final message = checkoutFailureMessage(
      const ForbiddenException(
        message: 'Telephone client non verifie',
        code: 'PHONE_NOT_VERIFIED',
        field: 'phone',
      ),
    );

    expect(message, contains('Telephone non verifie'));
    expect(message, contains('confirmer son numero'));
  });

  test('explique une methode identification manquante', () {
    final message = checkoutFailureMessage(
      const ValidationException(
        message: 'loyalty_identification_method est requis',
        field: 'loyalty_identification_method',
      ),
    );

    expect(message, contains('Methode identification'));
    expect(message, contains('Recommencez'));
  });

  test('explique une confirmation orale manquante', () {
    final message = checkoutFailureMessage(
      const ValidationException(
        message: 'Confirmation orale client requise',
        field: 'loyalty_oral_confirmed',
      ),
    );

    expect(message, contains('Confirmation orale requise'));
    expect(message, contains('Cochez'));
  });

  test('explique une recompense impossible', () {
    final message = checkoutFailureMessage(
      const BusinessException(
        message: 'Le produit offert doit etre present',
        code: 'REWARD_PRODUCT_REQUIRED',
      ),
    );

    expect(message, contains('Produit requis absent'));
    expect(message, contains('autre recompense'));
  });

  test('explique une connexion absente', () {
    final message = checkoutFailureMessage(
      const NetworkException(message: 'Failed host lookup'),
    );

    expect(message, contains('Connexion serveur indisponible'));
    expect(message, contains('hors ligne'));
  });
}
