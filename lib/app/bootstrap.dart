import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<ProviderContainer> bootstrap() async {
  final container = ProviderContainer();
  final session = await container.read(sessionControllerProvider.future);
  if (session.status == SessionStatus.authenticated) {
    try {
      await container.read(availableEstablishmentsProvider.future);
    } catch (_) {
      // The shell has an explicit unavailable state; startup should not hang on
      // a secondary context fetch when auth itself is valid.
    }
  }
  return container;
}
