import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Active KDS screens available for selection from the kitchen board's
/// screen selector (`KitchenScreenSelector`).
///
/// Calls `listScreens()` with no `includeInactive` argument, so only
/// `isActive == true` screens are returned — this is the exact behavior the
/// board selector needs (LOT 11 Task 6). Kept in its own file (application
/// layer) rather than inside `kitchen_screen_selector.dart` (presentation
/// layer) so that `KdsScreenManagementController.updateScreen` (also
/// application layer) can invalidate it without a presentation->application
/// import direction violation.
final kdsActiveScreensProvider = FutureProvider<List<KdsScreen>>((ref) async {
  final repository = ref.watch(kdsRepositoryProvider);
  return repository.listScreens();
});
