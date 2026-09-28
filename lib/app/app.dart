import 'package:app_admin_staff/app/router/app_router.dart';
import 'package:app_admin_staff/app/operational_fullscreen.dart';
import 'package:app_admin_staff/app/service_mode.dart';
import 'package:app_admin_staff/app/theme/app_theme.dart';
import 'package:app_admin_staff/app/theme/app_theme_mode.dart';
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
    final operationalFullscreen = ref.watch(operationalFullscreenProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    ref.listen<bool>(serviceModeProvider, (previous, next) {
      _applySystemUi(next || ref.read(operationalFullscreenProvider));
    });
    ref.listen<bool>(operationalFullscreenProvider, (previous, next) {
      _applySystemUi(next || ref.read(serviceModeProvider));
    });

    _applySystemUi(serviceMode || operationalFullscreen);

    return MaterialApp.router(
      title: "O'Pizza Staff",
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: serviceMode ? ThemeMode.dark : themeMode,
      routerConfig: router,
      builder: (context, child) {
        return RealtimeConnector(child: child ?? const SizedBox.shrink());
      },
      debugShowCheckedModeBanner: false,
    );
  }

  void _applySystemUi(bool immersive) {
    if (immersive) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      return;
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}
