import 'package:app_admin_staff/app/app.dart';
import 'package:app_admin_staff/core/config/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const runRealDemo = bool.fromEnvironment('DEMO_E2E');

  testWidgets(
    'boots the real app shell for local demo validation',
    (tester) async {
      Env.validateStartupConfig();

      await tester.pumpWidget(
        const ProviderScope(child: StaffAdminApp()),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(MaterialApp), findsOneWidget);
    },
    // Set --dart-define=DEMO_E2E=true for the local real-backend demo.
    skip: !runRealDemo,
  );
}
