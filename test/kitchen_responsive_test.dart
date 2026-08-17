import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_layout_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_board_test_support.dart';

void main() {
  test('KitchenLayoutPolicy retient les pages attendues', () {
    expect(
      KitchenLayoutPolicy.forSize(const Size(390, 844)).ticketsPerPage,
      1,
    );
    expect(
      KitchenLayoutPolicy.forSize(const Size(768, 1024)).ticketsPerPage,
      2,
    );
    expect(
      KitchenLayoutPolicy.forSize(const Size(1024, 768)).ticketsPerPage,
      4,
    );
    expect(
      KitchenLayoutPolicy.forSize(const Size(1920, 1080)).ticketsPerPage,
      4,
    );
  });

  testWidgets('390px affiche 1 ticket sans overflow', (tester) async {
    await _expectResponsiveTickets(
      tester,
      size: const Size(390, 844),
      visibleIds: [101],
      ticketsPerPage: 1,
    );
  });

  testWidgets('768px portrait affiche 2 tickets sans overflow', (tester) async {
    await _expectResponsiveTickets(
      tester,
      size: const Size(768, 1024),
      visibleIds: [101, 102],
      ticketsPerPage: 2,
    );
  });

  testWidgets('1024px paysage affiche 4 tickets sans overflow', (tester) async {
    await _expectResponsiveTickets(
      tester,
      size: const Size(1024, 768),
      visibleIds: [101, 102, 103, 104],
      ticketsPerPage: 4,
    );
  });

  testWidgets('1920x1080 affiche 4 tickets sans overflow', (tester) async {
    await _expectResponsiveTickets(
      tester,
      size: const Size(1920, 1080),
      visibleIds: [101, 102, 103, 104],
      ticketsPerPage: 4,
    );
  });
}

Future<void> _expectResponsiveTickets(
  WidgetTester tester, {
  required Size size,
  required List<int> visibleIds,
  required int ticketsPerPage,
}) async {
  addTearDown(tester.view.reset);
  final repository = TestKitchenRepository()..setOrders(kitchenIds(101, 105));
  final container = createKitchenContainer(repository);
  addTearDown(container.dispose);

  await pumpKitchenPage(tester, container, size: size);

  final state = container.read(kitchenQueueProvider).valueOrNull!;
  expect(state.profile.ticketsPerPage, ticketsPerPage);
  expect(
    state.currentPageTickets.map((ticket) => ticket.order.id),
    visibleIds,
  );
  for (final id in visibleIds) {
    expect(find.text('#$id'), findsOneWidget);
  }
  expect(tester.takeException(), isNull);
}
