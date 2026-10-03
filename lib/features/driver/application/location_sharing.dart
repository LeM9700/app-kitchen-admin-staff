import 'dart:async';

import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Une position mesuree sur le telephone.
class LocationSample {
  const LocationSample({
    required this.lat,
    required this.lng,
    required this.recordedAt,
    this.accuracyM,
    this.speedMps,
    this.heading,
  });

  final double lat;
  final double lng;
  final DateTime recordedAt;
  final double? accuracyM;
  final double? speedMps;
  final double? heading;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'recorded_at': recordedAt.toUtc().toIso8601String(),
        if (accuracyM != null) 'accuracy_m': accuracyM,
        if (speedMps != null && speedMps! >= 0) 'speed_mps': speedMps,
        if (heading != null && heading! >= 0 && heading! <= 360) 'heading': heading,
      };
}

enum PositionPermission { granted, denied, deniedForever, serviceDisabled }

/// Source des positions : le GPS du telephone, remplacable dans les tests.
abstract class PositionSource {
  Future<PositionPermission> requestPermission();
  Stream<LocationSample> watch();
}

/// Reglages GPS par plateforme, pour que le partage **continue application en arriere-plan ou ecran
/// verrouille** pendant une livraison :
/// - Android : service de premier plan avec une notification permanente et un wake lock ;
/// - iPhone : mises a jour en arriere-plan avec l'indicateur de localisation visible, sans pause automatique ;
/// - ailleurs : reglages simples.
/// Le flux n'est ouvert que pendant une livraison en route (voir `DriverLocationSharer`).
LocationSettings buildLocationSettings(TargetPlatform platform, {bool isWeb = false}) {
  const distanceFilter = 10;
  if (isWeb) {
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: distanceFilter);
  }
  switch (platform) {
    case TargetPlatform.android:
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Livraison en cours',
          notificationText:
              'Votre position est partagee avec le restaurant et le client pendant la livraison.',
          notificationChannelName: 'Livraison en cours',
          notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: distanceFilter);
  }
}

class GeolocatorPositionSource implements PositionSource {
  const GeolocatorPositionSource();

  @override
  Future<PositionPermission> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return PositionPermission.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse =>
        PositionPermission.granted,
      LocationPermission.deniedForever => PositionPermission.deniedForever,
      _ => PositionPermission.denied,
    };
  }

  @override
  Stream<LocationSample> watch() {
    return Geolocator.getPositionStream(
      locationSettings: buildLocationSettings(defaultTargetPlatform, isWeb: kIsWeb),
    ).map(
      (p) => LocationSample(
        lat: p.latitude,
        lng: p.longitude,
        recordedAt: p.timestamp,
        accuracyM: p.accuracy,
        speedMps: p.speed,
        heading: p.heading,
      ),
    );
  }
}

final positionSourceProvider =
    Provider<PositionSource>((ref) => const GeolocatorPositionSource());

enum SharingStatus {
  /// Rien a partager (pas de livraison en route) : aucune position n'est lue.
  idle,

  /// Position lue et envoyee.
  sharing,

  /// Autorisation de localisation refusee ou service coupe : rien n'est envoye.
  permissionDenied,

  /// L'accord du livreur manque (ou a ete retire) : rien n'est envoye.
  consentRequired,
}

class SharingState {
  const SharingState({
    this.status = SharingStatus.idle,
    this.pending = 0,
    this.lastSentAt,
    this.lastError,
  });

  final SharingStatus status;

  /// Positions gardees en memoire faute de reseau (renvoyees des que possible).
  final int pending;
  final DateTime? lastSentAt;
  final String? lastError;

  bool get isSharing => status == SharingStatus.sharing;
}

/// Partage la position du livreur **uniquement pendant une livraison en route** et avec son accord.
///
/// - `setActive(true)` ouvre le flux GPS ; `setActive(false)` le ferme sur-le-champ (rien n'est lu hors livraison) ;
/// - les positions sont envoyees par lots toutes les [flushInterval] ; sans reseau elles s'accumulent
///   (au plus [maxBuffer], les plus anciennes sont abandonnees) puis sont renvoyees ;
/// - le serveur est l'autorite : `LOCATION_NOT_ACTIVE` ou `LOCATION_CONSENT_REQUIRED` arretent le partage.
///
/// Arriere-plan : voir [buildLocationSettings] (service de premier plan Android avec notification
/// permanente, mode d'arriere-plan iPhone avec indicateur). Limite connue : application **fermee**
/// (balayee des applications recentes), le partage s'arrete ; la configuration n'a pas ete verifiee
/// sur appareil reel dans cet environnement.
class DriverLocationSharer extends StateNotifier<SharingState> {
  DriverLocationSharer(
    this._repository,
    this._source, {
    this.flushInterval = const Duration(seconds: 8),
    this.maxBuffer = 30,
  }) : super(const SharingState());

  final DispatchRepository _repository;
  final PositionSource _source;
  final Duration flushInterval;
  final int maxBuffer;

  final List<LocationSample> _buffer = [];
  StreamSubscription<LocationSample>? _subscription;
  Timer? _timer;
  bool _active = false;
  bool _starting = false;
  bool _flushing = false;

  /// Reverifie l'autorisation (au retour au premier plan) : le livreur a pu la retirer dans les reglages
  /// du telephone pendant que l'application tournait en arriere-plan. Si elle manque, le flux est ferme
  /// et l'etat l'indique ; sinon rien ne change.
  Future<void> recheckPermission() async {
    if (!mounted || !_active) return;
    final permission = await _source.requestPermission();
    if (!mounted || !_active || permission == PositionPermission.granted) return;
    _stop();
    state = const SharingState(
      status: SharingStatus.permissionDenied,
      lastError: 'Autorisation de localisation retiree : la position n\'est plus partagee.',
    );
  }

  Future<void> setActive(bool active) async {
    if (!mounted) return;
    if (!active) {
      if (_active || state.status != SharingStatus.idle) {
        _stop();
        state = const SharingState();
      }
      return;
    }
    if (_active || _starting) return;
    _starting = true;
    try {
      final permission = await _source.requestPermission();
      if (!mounted) return;
      if (permission != PositionPermission.granted) {
        state = SharingState(
          status: SharingStatus.permissionDenied,
          lastError: switch (permission) {
            PositionPermission.serviceDisabled => 'Localisation desactivee sur le telephone.',
            PositionPermission.deniedForever =>
              'Autorisation refusee : activez-la dans les reglages du telephone.',
            _ => 'Autorisation de localisation refusee.',
          },
        );
        return;
      }
      _active = true;
      _subscription = _source.watch().listen(
        _onSample,
        onError: (Object error) {
          if (mounted) {
            state = SharingState(
              status: SharingStatus.sharing,
              pending: _buffer.length,
              lastSentAt: state.lastSentAt,
              lastError: 'GPS indisponible',
            );
          }
        },
      );
      _timer = Timer.periodic(flushInterval, (_) => flush());
      state = const SharingState(status: SharingStatus.sharing);
    } finally {
      _starting = false;
    }
  }

  void _onSample(LocationSample sample) {
    _buffer.add(sample);
    while (_buffer.length > maxBuffer) {
      _buffer.removeAt(0);
    }
    if (mounted) {
      state = SharingState(
        status: SharingStatus.sharing,
        pending: _buffer.length,
        lastSentAt: state.lastSentAt,
        lastError: state.lastError,
      );
    }
  }

  /// Envoie le tampon. Public pour les tests ; appele par la minuterie.
  Future<void> flush() async {
    if (_flushing || _buffer.isEmpty || !_active) return;
    _flushing = true;
    final batch = List<LocationSample>.of(_buffer);
    try {
      await _repository.sendLocation(batch);
      _buffer.removeRange(0, batch.length.clamp(0, _buffer.length));
      if (mounted) {
        state = SharingState(
          status: SharingStatus.sharing,
          pending: _buffer.length,
          lastSentAt: DateTime.now(),
        );
      }
    } on ApiError catch (error) {
      if (error.code == 'LOCATION_NOT_ACTIVE') {
        // Plus de livraison en route cote serveur : on s'arrete et on oublie ce qui reste.
        _stop();
        if (mounted) state = const SharingState();
      } else if (error.code == 'LOCATION_CONSENT_REQUIRED') {
        _stop();
        if (mounted) state = const SharingState(status: SharingStatus.consentRequired);
      } else if (mounted) {
        state = SharingState(
          status: SharingStatus.sharing,
          pending: _buffer.length,
          lastSentAt: state.lastSentAt,
          lastError: error.message,
        );
      }
    } catch (_) {
      // Pas de reseau : on garde le tampon, on reessaie au prochain tour.
      if (mounted) {
        state = SharingState(
          status: SharingStatus.sharing,
          pending: _buffer.length,
          lastSentAt: state.lastSentAt,
          lastError: 'Hors reseau : positions gardees',
        );
      }
    } finally {
      _flushing = false;
    }
  }

  void _stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _subscription?.cancel();
    _subscription = null;
    _buffer.clear();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}

final driverLocationSharerProvider =
    StateNotifierProvider<DriverLocationSharer, SharingState>((ref) {
  return DriverLocationSharer(
    ref.watch(dispatchRepositoryProvider),
    ref.watch(positionSourceProvider),
  );
});
