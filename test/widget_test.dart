import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty state renders title and subtitle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EmptyState(
          icon: Icons.info_outline,
          title: 'Aucun element',
          subtitle: 'Reessayez plus tard',
        ),
      ),
    );

    expect(find.text('Aucun element'), findsOneWidget);
    expect(find.text('Reessayez plus tard'), findsOneWidget);
  });
}
