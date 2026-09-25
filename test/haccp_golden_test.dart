import 'package:app_admin_staff/app/theme/app_theme.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_check_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_cooling_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_nc_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_reception_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'haccp_test_support.dart';

/// Goldens HACCP uniquement (autres modules non concernes).
void main() {
  final cases = <(String, Widget, Size)>[
    ('haccp_check_390', const HaccpCheckPage(), const Size(390, 1500)),
    ('haccp_check_768', const HaccpCheckPage(), const Size(768, 1300)),
    ('haccp_check_1280', const HaccpCheckPage(), const Size(1280, 1000)),
    ('haccp_nc_390', const HaccpNonConformityPage(), const Size(390, 844)),
    ('haccp_nc_768', const HaccpNonConformityPage(), const Size(768, 1024)),
    ('haccp_reception_390', const HaccpReceptionPage(), const Size(390, 844)),
    ('haccp_cooling_768', const HaccpCoolingPage(), const Size(768, 1024)),
  ];

  for (final (name, page, size) in cases) {
    testWidgets('$name golden', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;

      await tester.pumpWidget(
        haccpTestApp(
          RepaintBoundary(key: const ValueKey('golden'), child: page),
          theme: AppTheme.light(),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const ValueKey('golden')),
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }
}
