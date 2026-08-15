import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('narrow width is classified as mobile by Breakpoints',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late bool isMobile;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            isMobile = Breakpoints.isMobile(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(isMobile, isTrue);
  });

  testWidgets('wide width is classified as desktop by Breakpoints',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late bool isDesktop;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            isDesktop = Breakpoints.isDesktop(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(isDesktop, isTrue);
  });
}
