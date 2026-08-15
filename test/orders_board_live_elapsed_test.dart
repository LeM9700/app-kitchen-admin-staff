import 'package:app_admin_staff/core/widgets/live_elapsed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('order card shows a LiveElapsed chip for createdAt',
      (tester) async {
    final since = DateTime.now().subtract(const Duration(minutes: 4));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Chip(label: LiveElapsed(since: since)),
        ),
      ),
    );
    expect(find.text('04:00'), findsOneWidget);
  });
}
