import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile width routes through Breakpoints.isMobile',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
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
}
