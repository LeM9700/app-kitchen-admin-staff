import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';

enum KitchenRemoteSessionStatus {
  disconnected,
  connected,
  unavailable,
}

class KitchenRemoteSession {
  const KitchenRemoteSession({
    required this.sessionToken,
    required this.screenId,
    required this.screenName,
    required this.screenKey,
    required this.profile,
    required this.status,
    required this.connectedAt,
    required this.expiresAt,
    this.remoteSessionId,
  });

  final String sessionToken;
  final int? remoteSessionId;
  final int screenId;
  final String screenName;
  final String screenKey;
  final KitchenScreenProfile profile;
  final KitchenRemoteSessionStatus status;
  final DateTime connectedAt;
  final DateTime expiresAt;

  String get providerScopeKey {
    final id = remoteSessionId;
    if (id != null) {
      return 'remote-$id';
    }
    return 'screen-$screenId-${connectedAt.microsecondsSinceEpoch}';
  }

  KitchenRemoteSession copyWith({
    String? sessionToken,
    int? remoteSessionId,
    int? screenId,
    String? screenName,
    String? screenKey,
    KitchenScreenProfile? profile,
    KitchenRemoteSessionStatus? status,
    DateTime? connectedAt,
    DateTime? expiresAt,
  }) {
    return KitchenRemoteSession(
      sessionToken: sessionToken ?? this.sessionToken,
      remoteSessionId: remoteSessionId ?? this.remoteSessionId,
      screenId: screenId ?? this.screenId,
      screenName: screenName ?? this.screenName,
      screenKey: screenKey ?? this.screenKey,
      profile: profile ?? this.profile,
      status: status ?? this.status,
      connectedAt: connectedAt ?? this.connectedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
