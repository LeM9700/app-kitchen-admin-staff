import 'package:app_admin_staff/core/api/paginated.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/features/admin_users/data/admin_users_repository.dart';
import 'package:app_admin_staff/features/hr/application/hr_realtime.dart';
import 'package:app_admin_staff/features/hr/data/hr_repository.dart';
import 'package:app_admin_staff/features/hr/presentation/hr_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('admin planning renders at compact 1280 width', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _hrOverrides(),
        child: const MaterialApp(home: Scaffold(body: HrAdminPage())),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Planning'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Semaine du'), findsOneWidget);
    expect(find.text('Nouveau shift'), findsOneWidget);

    // Compact width renders one day card per week day in a lazy ListView;
    // today's card (holding the 09:00 shift) may start outside the initial
    // viewport and must be scrolled into view before it is built.
    await tester.dragUntilVisible(
      find.textContaining('09:00'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    expect(find.textContaining('09:00'), findsWidgets);
  });

  testWidgets('staff activity renders clock action at 390 width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: _hrOverrides(),
        child: const MaterialApp(home: Scaffold(body: StaffHrPage())),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Activite'));
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('staff-clock-action')),
    );

    expect(find.text('Hors service'), findsOneWidget);
    expect(find.byKey(const ValueKey('staff-clock-action')), findsOneWidget);
  });

  testWidgets('HR realtime invalidation refetches alerts provider',
      (tester) async {
    var alertLoads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hrAlertsProvider.overrideWith((ref, query) async {
            alertLoads++;
            return const <HrAlert>[];
          }),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) {
              ref.watch(hrAlertsProvider(const HrAlertsQuery()));
              return Scaffold(
                body: FilledButton(
                  onPressed: () => invalidateHrProviders(ref),
                  child: const Text('invalidate'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(alertLoads, 1);

    await tester.tap(find.text('invalidate'));
    await tester.pump();

    expect(alertLoads, 2);
  });
}

Future<void> _pumpUntilVisible(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

List<Override> _hrOverrides() {
  return [
    employeesProvider.overrideWith((ref) async => [_employee()]),
    myEmployeeProfileProvider.overrideWith((ref) async {
      return const EmployeeProfileSelf(
        id: 1,
        userId: 2,
        establishmentId: 1,
        weeklyHoursContract: 35,
        isActive: true,
      );
    }),
    shiftsProvider.overrideWith((ref, query) async => [_shift()]),
    myShiftsProvider.overrideWith((ref, query) async => [_shift()]),
    timeClockEntriesProvider.overrideWith((ref, query) async => const []),
    myTimeClockEntriesProvider.overrideWith((ref, query) async => const []),
    hrAlertsProvider.overrideWith((ref, query) async => const []),
    adminUsersProvider.overrideWith((ref, query) async {
      return PaginatedResult<AdminUser>(
        items: [
          AdminUser(
            id: 2,
            email: 'staff@test.com',
            fullName: 'Staff Test',
            role: 'staff',
            permissions: const ['orders:read'],
            isActive: true,
            emailVerified: true,
            createdAt: DateTime(2026, 8, 10),
            mustChangePassword: false,
          ),
        ],
        total: 1,
        page: 1,
        pageSize: 100,
      );
    }),
    onlineStatusProvider.overrideWith((ref) => Stream.value(true)),
  ];
}

EmployeeProfile _employee() {
  return EmployeeProfile(
    id: 1,
    userId: 2,
    establishmentId: 1,
    hourlyRateCents: 1500,
    weeklyHoursContract: 35,
    isActive: true,
    createdAt: DateTime(2026, 8, 10),
  );
}

HrShift _shift() {
  return HrShift(
    id: 1,
    employeeId: 1,
    establishmentId: 1,
    startsAt: DateTime.now().copyWith(hour: 9, minute: 0),
    endsAt: DateTime.now().copyWith(hour: 13, minute: 0),
    breakMinutes: 15,
    status: 'scheduled',
  );
}
