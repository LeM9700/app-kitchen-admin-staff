import 'package:app_admin_staff/core/config/stripe_connect_callbacks.dart';

class Env {
  static const appEnvironment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );

  static const appPublicUrl = String.fromEnvironment(
    'APP_PUBLIC_URL',
    defaultValue: '',
  );

  /// Jeton Mapbox PUBLIC (`pk.*`) pour afficher les tuiles des cartes de livraison. Fait pour
  /// etre embarque (restreignez-le a votre domaine / identifiant d'app dans Mapbox). Le jeton
  /// SECRET du geocodage reste cote serveur. Vide = tuiles OpenStreetMap, a reserver au
  /// developpement (conditions d'usage OSM).
  static const mapboxPublicToken = String.fromEnvironment(
    'MAPBOX_PUBLIC_TOKEN',
    defaultValue: '',
  );

  static const defaultTenantSlug = String.fromEnvironment(
    'DEFAULT_TENANT_SLUG',
    defaultValue: 'pizza_test',
  );

  static const kdsInteractionMode = String.fromEnvironment(
    'KDS_INTERACTION_MODE',
    defaultValue: 'wall',
  );

  static void validateStartupConfig({
    StripeConnectCallbackConfig? stripeConnectCallbacks,
  }) {
    (stripeConnectCallbacks ?? StripeConnectCallbackConfig.fromEnvironment())
        .validated();
  }
}
