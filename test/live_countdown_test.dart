// app-admin-staff/test/live_countdown_test.dart
import 'package:app_admin_staff/core/widgets/live_countdown.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatCountdown', () {
    test('formats days:hours:minutes:seconds', () {
      const remaining = Duration(
        days: 1,
        hours: 2,
        minutes: 3,
        seconds: 4,
      );
      expect(formatCountdown(remaining), '01:02:03:04');
    });

    test('returns "Expire" when negative', () {
      const remaining = Duration(seconds: -5);
      expect(formatCountdown(remaining), 'Expire');
    });
  });

  group('countdownColor', () {
    test('green above 10 minutes', () {
      expect(
        countdownColor(const Duration(minutes: 11)),
        AppColors.success,
      );
    });

    test('orange between 5 and 10 minutes inclusive', () {
      expect(countdownColor(const Duration(minutes: 10)), AppColors.warning);
      expect(countdownColor(const Duration(minutes: 5)), AppColors.warning);
    });

    test('red under 5 minutes', () {
      expect(countdownColor(const Duration(minutes: 4)), AppColors.danger);
    });

    test('red when expired', () {
      expect(countdownColor(const Duration(seconds: -1)), AppColors.danger);
    });
  });

  testWidgets('LiveCountdown renders "Pas de DLC" for null target',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LiveCountdown(target: null)),
    );
    expect(find.text('Pas de DLC'), findsOneWidget);
  });

  testWidgets('LiveCountdown renders and disposes its timer cleanly',
      (tester) async {
    final target = DateTime.now().add(const Duration(minutes: 20));
    await tester.pumpWidget(
      MaterialApp(home: LiveCountdown(target: target)),
    );
    expect(find.byType(Text), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
}
