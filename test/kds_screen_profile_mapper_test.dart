import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/domain/kds_screen_profile_mapper.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mappe kitchen wall', () {
    final profile = profileFromKdsScreen(
      _screen(mode: 'kitchen', interactionMode: 'wall'),
    );

    expect(profile.mode, KitchenScreenMode.kitchen);
    expect(profile.interactionMode, KitchenInteractionMode.wall);
  });

  test('mappe counter touch', () {
    final profile = profileFromKdsScreen(
      _screen(mode: 'counter', interactionMode: 'touch'),
    );

    expect(profile.mode, KitchenScreenMode.counter);
    expect(profile.interactionMode, KitchenInteractionMode.touch);
  });

  test('mappe service wall', () {
    final profile = profileFromKdsScreen(
      _screen(mode: 'service', interactionMode: 'wall'),
    );

    expect(profile.mode, KitchenScreenMode.service);
    expect(profile.interactionMode, KitchenInteractionMode.wall);
  });

  test('conserve station custom et ticketsPerPage backend', () {
    final profile = profileFromKdsScreen(
      _screen(station: 'dessert', ticketsPerPage: 7),
    );

    expect(profile.station, 'dessert');
    expect(profile.ticketsPerPage, 7);
  });

  test('mode backend inconnu leve une erreur explicite', () {
    expect(
      () => profileFromKdsScreen(_screen(mode: 'unknown')),
      throwsA(isA<FormatException>()),
    );
  });
}

KdsScreen _screen({
  String mode = 'kitchen',
  String station = 'kitchen',
  String interactionMode = 'wall',
  int ticketsPerPage = 4,
}) {
  return KdsScreen(
    id: 12,
    name: 'Cuisine principale',
    screenKey: 'kitchen-main',
    mode: mode,
    station: station,
    interactionMode: interactionMode,
    ticketsPerPage: ticketsPerPage,
    isActive: true,
  );
}
