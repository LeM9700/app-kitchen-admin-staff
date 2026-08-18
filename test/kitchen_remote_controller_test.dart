import 'package:app_admin_staff/features/kitchen/application/kitchen_remote_controller.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_remote_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aucune session par defaut', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(kitchenRemoteSessionProvider), isNull);
    expect(
      container.read(kitchenRemoteSessionProvider.notifier).isConnected,
      isFalse,
    );
    expect(
      container.read(kitchenRemoteSessionProvider.notifier).actionsAllowed,
      isFalse,
    );
  });

  test('connectToScreen kitchen active la session avec le profil kitchen', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(kitchenRemoteSessionProvider.notifier)
        .connectToScreen(_screen('kitchen-main'));

    final session = container.read(kitchenRemoteSessionProvider)!;
    expect(session.screenId, 'kitchen-main');
    expect(session.screenName, 'Cuisine principale');
    expect(session.profile.mode, KitchenScreenMode.kitchen);
    expect(session.status, KitchenRemoteSessionStatus.connected);
    expect(
      container.read(kitchenRemoteSessionProvider.notifier).actionsAllowed,
      isTrue,
    );
  });

  test('une seule session active remplace explicitement la precedente', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(kitchenRemoteSessionProvider.notifier);

    controller.connectToScreen(_screen('kitchen-main'));
    final firstSessionId =
        container.read(kitchenRemoteSessionProvider)!.sessionId;
    controller.connectToScreen(_screen('counter-main'));

    final session = container.read(kitchenRemoteSessionProvider)!;
    expect(session.screenId, 'counter-main');
    expect(session.profile.mode, KitchenScreenMode.counter);
    expect(session.sessionId, isNot(firstSessionId));
  });

  test('disconnect supprime la session active', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(kitchenRemoteSessionProvider.notifier);

    controller.connectToScreen(_screen('kitchen-main'));
    controller.disconnect();

    expect(container.read(kitchenRemoteSessionProvider), isNull);
    expect(controller.hasSession, isFalse);
  });

  test('session Service expose le mode service', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(kitchenRemoteSessionProvider.notifier)
        .connectToScreen(_screen('service-main'));

    final session = container.read(kitchenRemoteSessionProvider)!;
    expect(session.screenName, 'Service');
    expect(session.profile.mode, KitchenScreenMode.service);
    expect(session.profile.station, 'service');
  });

  test('session unavailable interdit les actions', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(kitchenRemoteSessionProvider.notifier);

    controller.connectToScreen(_screen('kitchen-main'));
    controller.markUnavailable();

    expect(
      container.read(kitchenRemoteSessionProvider)!.status,
      KitchenRemoteSessionStatus.unavailable,
    );
    expect(controller.isConnected, isFalse);
    expect(controller.actionsAllowed, isFalse);
  });
}

DemoKitchenScreen _screen(String id) {
  return demoKitchenScreens.firstWhere((screen) => screen.id == id);
}
