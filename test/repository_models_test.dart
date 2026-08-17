import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/dashboard/data/dashboard_repository.dart';
import 'package:app_admin_staff/features/delivery/data/delivery_repository.dart';
import 'package:app_admin_staff/features/loyalty/data/loyalty_repository.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/promotions/data/promotions_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delivery zone parses API response', () {
    final zone = DeliveryZone.fromJson({
      'id': 1,
      'name': 'Centre',
      'fee': 3.5,
      'min_order_amount': 15,
      'estimated_minutes': 25,
      'is_active': true,
    });

    expect(zone.name, 'Centre');
    expect(zone.fee, 3.5);
    expect(zone.isActive, isTrue);
  });

  test('order detail parses status history', () {
    final detail = OrderDetail.fromJson({
      'id': 42,
      'order_type': 'delivery',
      'status': 'preparing',
      'payment_status': 'paid',
      'source': 'customer',
      'total': '18.50',
      'delivery_fee': 2,
      'items': [],
      'station_summary': [],
      'status_history': [
        {
          'status': 'confirmed',
          'note': 'Validated by staff',
          'authority': 'staff',
          'created_at': '2026-08-17T09:15:30Z',
        },
      ],
    });

    final history = detail.statusHistory.single;

    expect(history.status, 'confirmed');
    expect(history.note, 'Validated by staff');
    expect(history.authority, 'staff');
    expect(history.createdAt, DateTime.utc(2026, 8, 17, 9, 15, 30));
  });

  test('order detail returns empty status history when absent', () {
    final detail = OrderDetail.fromJson({
      'id': 43,
      'order_type': 'delivery',
      'status': 'pending',
      'payment_status': 'pending',
      'source': 'customer',
      'total': 12,
      'delivery_fee': 0,
      'items': [],
      'station_summary': [],
    });

    expect(detail.statusHistory, isEmpty);
  });

  test('loyalty config parses decimal strings', () {
    final config = LoyaltyConfig.fromJson({
      'id': 1,
      'base_ratio': '1.5',
      'points_expiry_days': 365,
      'points_to_euro_rate': '0.02',
      'max_cumulative_multiplier': '3.0',
      'is_active': true,
    });

    expect(config.baseRatio, 1.5);
    expect(config.pointsToEuroRate, 0.02);
  });

  test('promotion admin item tolerates public response shape', () {
    final promo = PromotionAdminItem.fromJson({
      'id': 7,
      'code': 'PIZZA10',
      'discount_type': 'percent',
      'discount_value': 10,
      'min_order_amount': 20,
      'is_active': true,
      'is_public': true,
    });

    expect(promo.code, 'PIZZA10');
    expect(promo.usageCount, 0);
  });

  test('catalog admin helpers parse completeness and csv dry-run', () {
    final completeness = CatalogCompleteness.fromJson({
      'total_products': 10,
      'complete_products': 7,
      'completion_percent': 70,
    });
    final dryRun = CatalogCsvDryRun.fromJson({
      'token': 'abc',
      'valid': true,
      'total_rows': 1,
      'previews': [
        {
          'row': 2,
          'action': 'create',
          'entity_type': 'product',
          'key': 'Margherita',
        },
      ],
      'errors': [],
    });

    expect(completeness.incompleteProducts, 3);
    expect(dryRun.valid, isTrue);
    expect(dryRun.previews.single.key, 'Margherita');
  });

  test('tenant config parses preparation settings', () {
    final config = TenantConfig.fromJson({
      'id': 1,
      'is_temporarily_closed': false,
      'default_closure_message': 'Ferme',
      'prep_time_normal_minutes': 25,
      'prep_time_peak_minutes': 45,
      'peak_orders_threshold': 8,
      'auto_calc_prep_time': true,
      'overhead_per_order_minutes': 3,
      'timezone': 'Europe/Paris',
      'large_stock_adjustment_threshold': '25.5',
      'print_enabled': true,
      'print_config': {'kitchen_printer': 'k1'},
    });

    expect(config.prepTimePeakMinutes, 45);
    expect(config.largeStockAdjustmentThreshold, 25.5);
    expect(config.printConfig['kitchen_printer'], 'k1');
  });

  test('catalog media and allergen models parse API responses', () {
    final image = CatalogMediaImage.fromJson({
      'id': 1,
      'entity_type': 'products',
      'entity_id': 10,
      'url': 'https://cdn/full.jpg',
      'url_thumbnail': 'https://cdn/thumb.jpg',
      'url_medium': 'https://cdn/medium.jpg',
      'format': 'jpg',
      'size_bytes': 1200,
      'width': 800,
      'height': 600,
      'is_primary': true,
      'display_order': 0,
    });
    final summary = ProductAllergenSummary.fromJson({
      'regulatory_complete': true,
      'allergens': [
        {
          'allergen_id': 1,
          'allergen_name': 'Gluten',
          'allergen_slug': 'gluten',
          'level': 'present',
          'source': 'manual',
          'is_regulatory': true,
        },
      ],
      'dietary_tags': [
        {'id': 2, 'name': 'Vegetarien', 'slug': 'vegetarien'},
      ],
    });

    expect(image.isPrimary, isTrue);
    expect(summary.allergens.single.level, 'present');
    expect(summary.dietaryTags.single.slug, 'vegetarien');
  });

  test('dashboard top product parses API response', () {
    final product = TopProductStats.fromJson({
      'product_id': 9,
      'product_name': 'Margherita',
      'quantity': 14,
      'revenue': '126.50',
    });

    expect(product.productName, 'Margherita');
    expect(product.quantity, 14);
    expect(product.revenue, 126.5);
  });
}
