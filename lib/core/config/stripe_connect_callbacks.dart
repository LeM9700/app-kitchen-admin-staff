class StripeConnectCallbackConfig {
  const StripeConnectCallbackConfig({
    required this.environment,
    required this.returnUrl,
    required this.refreshUrl,
  });

  factory StripeConnectCallbackConfig.fromEnvironment() {
    const environment = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    const returnUrl = String.fromEnvironment('STRIPE_CONNECT_RETURN_URL');
    const refreshUrl = String.fromEnvironment('STRIPE_CONNECT_REFRESH_URL');

    final fallbackBaseUrl = environment.toLowerCase() == 'production'
        ? Uri.base.origin
        : 'http://localhost:8080';

    return StripeConnectCallbackConfig(
      environment: environment,
      returnUrl: returnUrl.isEmpty
          ? '$fallbackBaseUrl/stripe/connect/return'
          : returnUrl,
      refreshUrl: refreshUrl.isEmpty
          ? '$fallbackBaseUrl/stripe/connect/refresh'
          : refreshUrl,
    );
  }

  final String environment;
  final String returnUrl;
  final String refreshUrl;

  bool get isProduction => environment.toLowerCase() == 'production';

  StripeConnectCallbackConfig validated() {
    _validateUrl(returnUrl, 'STRIPE_CONNECT_RETURN_URL');
    _validateUrl(refreshUrl, 'STRIPE_CONNECT_REFRESH_URL');
    if (isProduction &&
        (_containsExampleHost(returnUrl) || _containsExampleHost(refreshUrl))) {
      throw StateError(
        'Stripe Connect callbacks must not use example.com in production.',
      );
    }
    return this;
  }

  static void _validateUrl(String value, String name) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw StateError('$name must be an absolute URL.');
    }
  }

  static bool _containsExampleHost(String value) {
    final host = Uri.tryParse(value)?.host.toLowerCase() ?? '';
    return host == 'example.com' || host.endsWith('.example.com');
  }
}
