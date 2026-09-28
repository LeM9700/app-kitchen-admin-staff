import 'package:flutter_riverpod/flutter_riverpod.dart';

final operationalFullscreenProvider =
    StateProvider<bool>((ref) => false);

bool isOperationalFullscreenRoute(String location) {
  return location == '/orders' ||
      location == '/kitchen' ||
      location == '/counter';
}
