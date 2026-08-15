import 'package:app_admin_staff/app/router/app_router.dart';
import 'package:app_admin_staff/app/service_mode.dart';
import 'package:app_admin_staff/app/theme/app_theme.dart';
import 'package:app_admin_staff/core/realtime/realtime_connector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StaffAdminApp extends ConsumerWidget {
  const StaffAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final serviceMode = ref.watch(serviceModeProvider);
    ref.listen<bool>(serviceModeProvider, (previous, next) {
      if (next) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });

    return MaterialApp.router(
      title: "O'Pizza Staff",
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: serviceMode ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      builder: (context, child) {
        return RealtimeConnector(child: child ?? const SizedBox.shrink());
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
