import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_screen_presets.dart';

enum KitchenRemoteSessionStatus {
  disconnected,
  connected,
  unavailable,
}

class KitchenRemoteSession {
  const KitchenRemoteSession({
    required this.sessionId,
    required this.screenId,
    required this.screenName,
    required this.profile,
    required this.status,
    required this.connectedAt,
  });

  final String sessionId;
  final String screenId;
  final String screenName;
  final KitchenScreenProfile profile;
  final KitchenRemoteSessionStatus status;
  final DateTime connectedAt;

  KitchenRemoteSession copyWith({
    String? sessionId,
    String? screenId,
    String? screenName,
    KitchenScreenProfile? profile,
    KitchenRemoteSessionStatus? status,
    DateTime? connectedAt,
  }) {
    return KitchenRemoteSession(
      sessionId: sessionId ?? this.sessionId,
      screenId: screenId ?? this.screenId,
      screenName: screenName ?? this.screenName,
      profile: profile ?? this.profile,
      status: status ?? this.status,
      connectedAt: connectedAt ?? this.connectedAt,
    );
  }
}

class DemoKitchenScreen {
  const DemoKitchenScreen({
    required this.id,
    required this.name,
    required this.profile,
  });

  final String id;
  final String name;
  final KitchenScreenProfile profile;
}

const demoKitchenScreens = [
  DemoKitchenScreen(
    id: 'kitchen-main',
    name: 'Cuisine principale',
    profile: kitchenWallPreset,
  ),
  DemoKitchenScreen(
    id: 'counter-main',
    name: 'Comptoir',
    profile: counterWallPreset,
  ),
  DemoKitchenScreen(
    id: 'service-main',
    name: 'Service',
    profile: serviceWallPreset,
  ),
];
