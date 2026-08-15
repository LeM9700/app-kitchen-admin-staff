// app-admin-staff/test/live_elapsed_test.dart
import 'package:app_admin_staff/core/widgets/live_elapsed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatElapsedSince', () {
    test('returns minutes and seconds under 1 minute', () {
      final since = DateTime.now().subtract(const Duration(seconds: 10));
      expect(formatElapsedSince(since), '00:10');
    });

    test('returns minutes and seconds format under 1 hour', () {
      final since = DateTime.now().subtract(
        const Duration(minutes: 12, seconds: 3),
      );
      expect(formatElapsedSince(since), '12:03');
    });

    test('returns hours minutes and seconds format at or above 1 hour', () {
      final since = DateTime.now().subtract(
        const Duration(hours: 1, minutes: 5, seconds: 2),
      );
      expect(formatElapsedSince(since), '1:05:02');
    });
  });

  testWidgets('LiveElapsed renders and disposes its timer cleanly',
      (tester) async {
    final since = DateTime.now().subtract(const Duration(minutes: 3));
    await tester.pumpWidget(
      MaterialApp(home: LiveElapsed(since: since)),
    );
    expect(find.text('03:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
}
