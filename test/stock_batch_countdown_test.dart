import 'package:app_admin_staff/core/widgets/live_countdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('batch row composes status text with a LiveCountdown',
      (tester) async {
    final target = DateTime.now().add(const Duration(minutes: 3));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListTile(
            title: const Text('2 kg'),
            subtitle: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('sealed - '),
                LiveCountdown(target: target),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('sealed'), findsOneWidget);
    expect(find.byType(LiveCountdown), findsOneWidget);
  });
}
