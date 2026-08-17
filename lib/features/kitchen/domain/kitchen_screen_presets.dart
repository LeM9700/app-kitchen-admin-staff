import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';

const kitchenWallPreset = KitchenScreenProfile(
  mode: KitchenScreenMode.kitchen,
  station: 'kitchen',
  interactionMode: KitchenInteractionMode.wall,
);

const kitchenTouchPreset = KitchenScreenProfile(
  mode: KitchenScreenMode.kitchen,
  station: 'kitchen',
  interactionMode: KitchenInteractionMode.touch,
);

const counterWallPreset = KitchenScreenProfile(
  mode: KitchenScreenMode.counter,
  station: 'counter',
  interactionMode: KitchenInteractionMode.wall,
);

const counterTouchPreset = KitchenScreenProfile(
  mode: KitchenScreenMode.counter,
  station: 'counter',
  interactionMode: KitchenInteractionMode.touch,
);

const serviceWallPreset = KitchenScreenProfile(
  mode: KitchenScreenMode.service,
  station: 'service',
  interactionMode: KitchenInteractionMode.wall,
);

const serviceTouchPreset = KitchenScreenProfile(
  mode: KitchenScreenMode.service,
  station: 'service',
  interactionMode: KitchenInteractionMode.touch,
);

KitchenScreenProfile kitchenScreenPresetFor({
  required KitchenScreenMode mode,
  required KitchenInteractionMode interactionMode,
  int ticketsPerPage = 4,
}) {
  final preset = switch ((mode, interactionMode)) {
    (KitchenScreenMode.kitchen, KitchenInteractionMode.touch) =>
      kitchenTouchPreset,
    (KitchenScreenMode.counter, KitchenInteractionMode.wall) =>
      counterWallPreset,
    (KitchenScreenMode.counter, KitchenInteractionMode.touch) =>
      counterTouchPreset,
    (KitchenScreenMode.service, KitchenInteractionMode.wall) =>
      serviceWallPreset,
    (KitchenScreenMode.service, KitchenInteractionMode.touch) =>
      serviceTouchPreset,
    (KitchenScreenMode.kitchen, _) => kitchenWallPreset,
    (KitchenScreenMode.counter, _) => counterWallPreset,
    (KitchenScreenMode.service, _) => serviceWallPreset,
  };

  return preset.copyWith(ticketsPerPage: ticketsPerPage);
}

String kitchenScreenModeLabel(KitchenScreenMode mode) {
  return switch (mode) {
    KitchenScreenMode.kitchen => 'CUISINE',
    KitchenScreenMode.counter => 'COMPTOIR',
    KitchenScreenMode.service => 'SERVICE',
  };
}

String kitchenStationLabel(String station) {
  return switch (station.trim().toLowerCase()) {
    'kitchen' => 'CUISINE',
    'counter' => 'COMPTOIR',
    'service' => 'SERVICE',
    _ => station.trim().isEmpty ? 'POSTE' : station.trim().toUpperCase(),
  };
}
