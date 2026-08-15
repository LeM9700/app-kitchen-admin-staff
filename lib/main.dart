import 'package:app_admin_staff/app/app.dart';
import 'package:app_admin_staff/app/bootstrap.dart';
import 'package:app_admin_staff/core/config/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Env.validateStartupConfig();
  final container = await bootstrap();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const StaffAdminApp(),
    ),
  );
}
