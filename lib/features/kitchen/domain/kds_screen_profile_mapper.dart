import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';

KitchenScreenProfile profileFromKdsScreen(KdsScreen screen) {
  return KitchenScreenProfile(
    mode: _modeFromBackend(screen.mode),
    station: screen.station,
    ticketsPerPage: screen.ticketsPerPage,
    interactionMode: _interactionModeFromBackend(screen.interactionMode),
  );
}

KitchenScreenMode _modeFromBackend(String value) {
  return switch (value) {
    'kitchen' => KitchenScreenMode.kitchen,
    'counter' => KitchenScreenMode.counter,
    'service' => KitchenScreenMode.service,
    _ => throw FormatException('Unsupported KDS screen mode "$value"'),
  };
}

KitchenInteractionMode _interactionModeFromBackend(String value) {
  return switch (value) {
    'wall' => KitchenInteractionMode.wall,
    'touch' => KitchenInteractionMode.touch,
    _ => throw FormatException('Unsupported KDS interaction mode "$value"'),
  };
}
