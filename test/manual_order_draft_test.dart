import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pickup manual order clears delivery-only fields', () {
    const draft = ManualOrderDraft(
      idempotencyKey: 'key-1',
      orderType: 'pickup',
      paymentMethod: 'cash',
      amountReceived: 20,
      promoCode: ' pizza10 ',
      loyaltyCustomerId: 42,
      loyaltyRewardId: 7,
      loyaltyIdentificationMethod: 'phone',
      loyaltyOralConfirmed: true,
      items: [ManualOrderLine(productId: 10, quantity: 2)],
    );

    final json = draft.toJson();

    expect(json['order_type'], 'pickup');
    expect(json['delivery_fee'], 0);
    expect(json.containsKey('delivery_zone_id'), isFalse);
    expect(json.containsKey('delivery_address'), isFalse);
    expect(json['promo_code'], 'pizza10');
    expect(json['loyalty_customer_id'], 42);
    expect(json['loyalty_reward_id'], 7);
    expect(json['loyalty_identification_method'], 'phone');
    expect(json['loyalty_oral_confirmed'], isTrue);
    expect(json.containsKey('loyalty_user_id'), isFalse);
    expect(json.containsKey('loyalty_points_to_use'), isFalse);
    expect((json['payment'] as Map<String, dynamic>)['method'], 'cash');
  });

  test('dine in manual order carries the table number', () {
    const draft = ManualOrderDraft(
      idempotencyKey: 'key-2',
      orderType: 'dine_in',
      tableNumber: '12',
      paymentMethod: 'cash_register',
      externalReference: 'REG-99',
      establishmentId: 7,
      items: [ManualOrderLine(productId: 11, quantity: 1)],
    );

    final json = draft.toJson();

    expect(json['order_type'], 'dine_in');
    expect(json['table_number'], '12');
    expect(json['establishment_id'], 7);
    expect(json['delivery_fee'], 0);
    expect(json.containsKey('delivery_zone_id'), isFalse);
    expect(
      (json['payment'] as Map<String, dynamic>)['external_reference'],
      'REG-99',
    );
  });

  test('delivery manual order keeps the required address', () {
    const draft = ManualOrderDraft(
      idempotencyKey: 'key-3',
      orderType: 'delivery',
      deliveryAddress: '1 rue de la Pizza',
      paymentMethod: 'external_terminal',
      externalReference: 'TPE-123',
      items: [ManualOrderLine(productId: 12, quantity: 1)],
    );

    final json = draft.toJson();

    expect(json['order_type'], 'delivery');
    expect(json['delivery_address'], '1 rue de la Pizza');
    expect(json.containsKey('delivery_fee'), isFalse);
    expect(json.containsKey('loyalty_identification_method'), isFalse);
    expect(json.containsKey('loyalty_oral_confirmed'), isFalse);
    expect((json['items'] as List).single['product_id'], 12);
  });

  test('identified customer sends loyalty lookup method without reward', () {
    const draft = ManualOrderDraft(
      idempotencyKey: 'key-4',
      orderType: 'pickup',
      paymentMethod: 'cash',
      loyaltyCustomerId: 42,
      loyaltyIdentificationMethod: 'qr',
      items: [ManualOrderLine(productId: 13, quantity: 1)],
    );

    final json = draft.toJson();

    expect(json['loyalty_customer_id'], 42);
    expect(json['loyalty_identification_method'], 'qr');
    expect(json.containsKey('loyalty_oral_confirmed'), isFalse);
  });
}
