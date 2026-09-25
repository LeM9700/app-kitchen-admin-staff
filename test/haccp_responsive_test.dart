import 'package:app_admin_staff/features/haccp/presentation/haccp_check_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_cleaning_tasks_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_cooling_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_equipment_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_nc_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_reception_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_training_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'haccp_test_support.dart';

/// Sweep responsive HACCP : chaque ecran est rendu de 390 a 1920 px sans
/// overflow ni exception de layout. Donnees 100 % locales (aucun reseau).
const _sizes = <Size>[
  Size(390, 844),
  Size(768, 1024),
  Size(1024, 768),
  Size(1280, 900),
  Size(1440, 1024),
  Size(1920, 1080),
];

void main() {
  final screens = <String, Widget>{
    'session check': const HaccpCheckPage(),
    'non-conformites': const HaccpNonConformityPage(),
    'reception': const HaccpReceptionPage(),
    'refroidissement': const HaccpCoolingPage(),
    'equipements': const HaccpEquipmentPage(),
    'formation': const HaccpTrainingPage(),
    'nettoyage': const HaccpCleaningTasksPage(),
  };

  for (final entry in screens.entries) {
    for (final size in _sizes) {
      testWidgets('${entry.key} @ ${size.width.toInt()}px sans overflow',
          (tester) async {
        addTearDown(tester.view.reset);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;

        await tester.pumpWidget(haccpTestApp(entry.value));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(Scaffold), findsWidgets);
      });
    }
  }

  testWidgets('session check: DLC (produit, lot, echeance, temps restant)',
      (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(768, 3000);

    await tester.pumpWidget(haccpTestApp(const HaccpCheckPage()));
    await tester.pumpAndSettle();

    expect(find.text('Mozzarella'), findsOneWidget);
    expect(find.textContaining('Lot 42'), findsOneWidget);
    expect(find.textContaining('Temps restant'), findsOneWidget);
    expect(find.textContaining('4 / 6'), findsOneWidget);
    expect(find.text('Synchronisé'), findsOneWidget);
  });
}
