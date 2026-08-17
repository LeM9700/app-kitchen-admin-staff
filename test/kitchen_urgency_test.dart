import 'package:app_admin_staff/features/kitchen/application/kitchen_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('confirmed 10:00 with threshold 15 is normal at 10:14:59', () {
    expect(
      resolveKitchenUrgency(
        confirmedAt: DateTime.utc(2026, 8, 17, 10),
        now: DateTime.utc(2026, 8, 17, 10, 14, 59),
        prepTimeNormalMinutes: 15,
      ),
      KitchenUrgency.normal,
    );
  });

  test('confirmed 10:00 with threshold 15 is late at 10:15', () {
    expect(
      resolveKitchenUrgency(
        confirmedAt: DateTime.utc(2026, 8, 17, 10),
        now: DateTime.utc(2026, 8, 17, 10, 15),
        prepTimeNormalMinutes: 15,
      ),
      KitchenUrgency.late,
    );
  });

  test('confirmed null is normal', () {
    expect(
      resolveKitchenUrgency(
        confirmedAt: null,
        now: DateTime.utc(2026, 8, 17, 10, 15),
        prepTimeNormalMinutes: 15,
      ),
      KitchenUrgency.normal,
    );
  });

  test('now before confirmed is normal', () {
    expect(
      resolveKitchenUrgency(
        confirmedAt: DateTime.utc(2026, 8, 17, 10),
        now: DateTime.utc(2026, 8, 17, 9, 59, 59),
        prepTimeNormalMinutes: 15,
      ),
      KitchenUrgency.normal,
    );
  });
}
