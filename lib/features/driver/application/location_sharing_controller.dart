import 'dart:async';

import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/driver/application/location_sharing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Intervalle de verification des livraisons du livreur, independant de l'onglet affiche et de l'etat
/// de l'application : c'est lui qui arrete le partage peu apres la fin de la derniere livraison.
const driverLocationWatchInterval = Duration(seconds: 15);

/// Decide, pour tout le temps que le livreur est connecte, si sa position doit etre partagee :
/// **uniquement** quand il a donne son accord ET a au moins une livraison en route.
///
/// - vit tant que la coque livreur est affichee (quel que soit l'onglet), donc aussi application en
///   arriere-plan ou ecran verrouille ;
/// - interroge lui-meme les livraisons toutes les [driverLocationWatchInterval] ;
/// - ferme le GPS des qu'il est supprime : deconnexion, fin de session, retrait de l'accord, plus de
///   livraison en route (le serveur confirme avec `LOCATION_NOT_ACTIVE`).
final driverLocationControllerProvider = Provider.autoDispose<void>((ref) {
  final sharer = ref.read(driverLocationSharerProvider.notifier);

  void evaluate() {
    final consent = ref.read(driverMeProvider).valueOrNull?.locationConsent ?? false;
    final ongoing =
        ref.read(driverDeliveriesProvider).valueOrNull?.any((d) => d.isOngoing) ?? false;
    unawaited(sharer.setActive(consent && ongoing));
  }

  ref.listen(driverMeProvider, (_, __) => evaluate(), fireImmediately: true);
  ref.listen(driverDeliveriesProvider, (_, __) => evaluate(), fireImmediately: true);

  final timer = Timer.periodic(driverLocationWatchInterval, (_) {
    ref.invalidate(driverDeliveriesProvider);
  });
  ref.onDispose(() {
    timer.cancel();
    unawaited(sharer.setActive(false));
  });
});
