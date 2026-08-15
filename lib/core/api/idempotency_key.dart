class IdempotencyKey {
  IdempotencyKey._();

  static int _counter = 0;

  static String generate(String scope) {
    final normalizedScope = scope.trim().isEmpty ? 'action' : scope.trim();
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    _counter = (_counter + 1) % 1000000;
    return '$normalizedScope-$timestamp-$_counter';
  }
}
