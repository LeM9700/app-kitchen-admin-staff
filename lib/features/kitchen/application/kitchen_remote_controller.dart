import 'package:app_admin_staff/features/kitchen/domain/kitchen_remote_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final kitchenRemoteSessionProvider =
    NotifierProvider<KitchenRemoteController, KitchenRemoteSession?>(
  KitchenRemoteController.new,
);

class KitchenRemoteController extends Notifier<KitchenRemoteSession?> {
  int _sessionSequence = 0;

  @override
  KitchenRemoteSession? build() {
    return null;
  }

  bool get isConnected {
    return state?.status == KitchenRemoteSessionStatus.connected;
  }

  bool get hasSession {
    return state != null;
  }

  bool get actionsAllowed {
    return state?.status == KitchenRemoteSessionStatus.connected;
  }

  void connectToScreen(DemoKitchenScreen screen) {
    _sessionSequence += 1;
    state = KitchenRemoteSession(
      sessionId: 'lot8-${screen.id}-$_sessionSequence',
      screenId: screen.id,
      screenName: screen.name,
      profile: screen.profile,
      status: KitchenRemoteSessionStatus.connected,
      connectedAt: DateTime.now(),
    );
  }

  void disconnect() {
    state = null;
  }

  void markUnavailable() {
    final current = state;
    if (current == null) {
      return;
    }

    state = current.copyWith(status: KitchenRemoteSessionStatus.unavailable);
  }

  void retry() {
    final current = state;
    if (current == null) {
      return;
    }

    state = current.copyWith(status: KitchenRemoteSessionStatus.connected);
  }
}
