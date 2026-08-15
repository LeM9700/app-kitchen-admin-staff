class StripeConnectCallbackConfig {
  const StripeConnectCallbackConfig({
    required this.environment,
    required this.returnUrl,
    required this.refreshUrl,
  });

  factory StripeConnectCallbackConfig.fromEnvironment() {
    return const StripeConnectCallbackConfig(
      environment: String.fromEnvironment(
        'APP_ENV',
        defaultValue: 'development',
      ),
      returnUrl: String.fromEnvironment(
        'STRIPE_CONNECT_RETURN_URL',
        defaultValue: 'http://localhost:8080/stripe/connect/return',
      ),
      refreshUrl: String.fromEnvironment(
        'STRIPE_CONNECT_REFRESH_URL',
        defaultValue: 'http://localhost:8080/stripe/connect/refresh',
      ),
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
