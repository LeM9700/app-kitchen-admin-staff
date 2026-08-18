import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/features/kitchen/application/kds_active_screens_provider.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final kdsScreenManagementProvider = AsyncNotifierProvider<
    KdsScreenManagementController, KdsScreenManagementState>(
  KdsScreenManagementController.new,
);

class KdsScreenManagementState {
  const KdsScreenManagementState({
    required this.screens,
    this.busyScreenIds = const {},
    this.creating = false,
    this.actionError,
  });

  final List<KdsScreen> screens;
  final Set<int> busyScreenIds;
  final bool creating;
  final String? actionError;

  KdsScreenManagementState copyWith({
    List<KdsScreen>? screens,
    Set<int>? busyScreenIds,
    bool? creating,
    String? actionError,
    bool clearActionError = false,
  }) {
    return KdsScreenManagementState(
      screens: screens ?? this.screens,
      busyScreenIds: busyScreenIds ?? this.busyScreenIds,
      creating: creating ?? this.creating,
      actionError: clearActionError ? null : (actionError ?? this.actionError),
    );
  }
}

class KdsScreenManagementController
    extends AsyncNotifier<KdsScreenManagementState> {
  @override
  Future<KdsScreenManagementState> build() async {
    final repository = ref.watch(kdsRepositoryProvider);
    final screens = await repository.listScreens(includeInactive: true);
    return KdsScreenManagementState(screens: screens);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> createScreen({
    required String name,
    required String screenKey,
    required String mode,
    required String station,
    required String interactionMode,
    required int ticketsPerPage,
  }) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncValue.data(
      current.copyWith(creating: true, clearActionError: true),
    );
    try {
      final created = await ref.read(kdsRepositoryProvider).createScreen(
            name: name,
            screenKey: screenKey,
            mode: mode,
            station: station,
            interactionMode: interactionMode,
            ticketsPerPage: ticketsPerPage,
          );
      final base = state.value ?? current;
      state = AsyncValue.data(
        base.copyWith(
          screens: [...base.screens, created],
          creating: false,
        ),
      );
    } catch (error) {
      final base = state.value ?? current;
      state = AsyncValue.data(
        base.copyWith(creating: false, actionError: _mapKdsError(error)),
      );
    }
  }

  Future<void> updateScreen({
    required int screenId,
    String? name,
    String? screenKey,
    String? mode,
    String? station,
    String? interactionMode,
    int? ticketsPerPage,
    bool? isActive,
  }) async {
    await _runBusy(screenId, () async {
      final updated = await ref.read(kdsRepositoryProvider).updateScreen(
            screenId: screenId,
            name: name,
            screenKey: screenKey,
            mode: mode,
            station: station,
            interactionMode: interactionMode,
            ticketsPerPage: ticketsPerPage,
            isActive: isActive,
          );
      _replaceScreen(updated);
      // Point 29 de la spec: le board's selector list must reflect a config
      // change (name/mode/station/activation) made here without any extra
      // realtime sync — invalidating on success means the next time the
      // selector's bottom sheet is opened, it refetches and shows the new
      // data. updateScreen is the single funnel for all screen mutations
      // (including activation/deactivation), so one invalidation here is
      // sufficient (LOT 11 Task 6).
      ref.invalidate(kdsActiveScreensProvider);
    });
  }

  Future<KdsPairingCode?> generatePairingCode({required int screenId}) {
    return _runBusyValue<KdsPairingCode>(screenId, () {
      return ref.read(kdsRepositoryProvider).generatePairingCode(
            screenId: screenId,
          );
    });
  }

  Future<int?> revokeScreenSessions({required int screenId}) {
    return _runBusyValue<int>(screenId, () {
      return ref.read(kdsRepositoryProvider).revokeScreenSessions(
            screenId: screenId,
          );
    });
  }

  void clearActionError() {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncValue.data(current.copyWith(clearActionError: true));
  }

  /// Runs [action] while marking [screenId] busy, absorbing any exception
  /// into `actionError` instead of letting it propagate. Never leaves the
  /// state as `AsyncError` — see task brief "Comportement exact attendu".
  Future<void> _runBusy(
    int screenId,
    Future<void> Function() action,
  ) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncValue.data(
      current.copyWith(
        busyScreenIds: {...current.busyScreenIds, screenId},
        clearActionError: true,
      ),
    );
    try {
      await action();
    } catch (error) {
      final base = state.value ?? current;
      state = AsyncValue.data(base.copyWith(actionError: _mapKdsError(error)));
    } finally {
      final base = state.value;
      if (base != null) {
        final busy = {...base.busyScreenIds}..remove(screenId);
        state = AsyncValue.data(base.copyWith(busyScreenIds: busy));
      }
    }
  }

  /// Same contract as [_runBusy] but for mutations that return a value to
  /// the caller on success and `null` on failure.
  Future<T?> _runBusyValue<T>(
    int screenId,
    Future<T> Function() action,
  ) async {
    final current = state.value;
    if (current == null) {
      return null;
    }
    state = AsyncValue.data(
      current.copyWith(
        busyScreenIds: {...current.busyScreenIds, screenId},
        clearActionError: true,
      ),
    );
    T? result;
    try {
      result = await action();
    } catch (error) {
      final base = state.value ?? current;
      state = AsyncValue.data(base.copyWith(actionError: _mapKdsError(error)));
    } finally {
      final base = state.value;
      if (base != null) {
        final busy = {...base.busyScreenIds}..remove(screenId);
        state = AsyncValue.data(base.copyWith(busyScreenIds: busy));
      }
    }
    return result;
  }

  void _replaceScreen(KdsScreen updated) {
    final current = state.value;
    if (current == null) {
      return;
    }
    final screens = [
      for (final screen in current.screens)
        if (screen.id == updated.id) updated else screen,
    ];
    state = AsyncValue.data(current.copyWith(screens: screens));
  }
}

/// Maps a repository exception to the exact French label the KDS screen
/// management UI (Task 4/5) must display. Kept private to this file (not
/// shared with `kitchen_remote_controller.dart`'s own error mapper) because
/// the label set is specific to the admin screen-management flows and does
/// not overlap with the kitchen remote pairing/session error vocabulary.
String _mapKdsError(Object error) {
  if (error is! AppException) {
    return 'UNE ERREUR EST SURVENUE';
  }
  final businessMessage = switch (error.code) {
    'KDS_SCREEN_KEY_ALREADY_EXISTS' =>
      'UN ÉCRAN AVEC CET IDENTIFIANT EXISTE DÉJÀ',
    'KDS_SCREEN_NOT_FOUND' => 'ÉCRAN INTROUVABLE',
    'KDS_SCREEN_INACTIVE' => 'ÉCRAN INACTIF',
    _ => null,
  };
  if (businessMessage != null) {
    return businessMessage;
  }
  if (error is ForbiddenException || error.statusCode == 403) {
    return 'ACTION NON AUTORISÉE';
  }
  if (error is NetworkException) {
    return 'CONNEXION IMPOSSIBLE';
  }
  return error.message;
}
