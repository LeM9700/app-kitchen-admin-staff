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
    this.actionErrorCode,
  });

  final List<KdsScreen> screens;
  final Set<int> busyScreenIds;
  final bool creating;

  /// French, user-facing message for the SnackBar. Never branch business
  /// logic on this text — use [actionErrorCode] instead.
  final String? actionError;

  /// Structured counterpart to [actionError] (e.g.
  /// `KDS_SCREEN_KEY_ALREADY_EXISTS`, `NETWORK_ERROR`, `UNKNOWN_ERROR`, or a
  /// raw `AppException.code`). This is what UI decision points (like
  /// whether the create form should reopen for a rename retry) must branch
  /// on — see `kdsErrorCode` below.
  final String? actionErrorCode;

  KdsScreenManagementState copyWith({
    List<KdsScreen>? screens,
    Set<int>? busyScreenIds,
    bool? creating,
    String? actionError,
    String? actionErrorCode,
    bool clearActionError = false,
  }) {
    return KdsScreenManagementState(
      screens: screens ?? this.screens,
      busyScreenIds: busyScreenIds ?? this.busyScreenIds,
      creating: creating ?? this.creating,
      actionError: clearActionError ? null : (actionError ?? this.actionError),
      actionErrorCode:
          clearActionError ? null : (actionErrorCode ?? this.actionErrorCode),
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

  /// Creates a screen, absorbing any exception into `actionError`/
  /// `actionErrorCode` on `state` exactly like the other mutations (never
  /// throws to the caller). Also returns the structured error code directly
  /// (`null` on success) instead of `void`, unlike `updateScreen`/
  /// `generatePairingCode`/`revokeScreenSessions` — see the comment on the
  /// call site in `kds_settings_section.dart`'s `_createDialog` for why:
  /// in short, the return value lets that caller make its reopen-vs-not
  /// decision without racing the section's own `ref.listen(actionError)`
  /// side effect, which clears `actionErrorCode` off `state` synchronously.
  Future<String?> createScreen({
    required String name,
    required String screenKey,
    required String mode,
    required String station,
    required String interactionMode,
    required int ticketsPerPage,
  }) async {
    final current = state.value;
    if (current == null) {
      return null;
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
      // Same reasoning as updateScreen below (LOT 11 Task 6 comment): the
      // board's selector list must reflect a newly created screen without
      // any extra realtime sync. Missing this call was a final review
      // finding — a created screen previously only became selectable after
      // an unrelated screen edit invalidated the provider, or app restart.
      ref.invalidate(kdsActiveScreensProvider);
      return null;
    } catch (error) {
      final code = kdsErrorCode(error);
      final base = state.value ?? current;
      state = AsyncValue.data(
        base.copyWith(
          creating: false,
          actionError: mapKdsError(error),
          actionErrorCode: code,
        ),
      );
      return code;
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
      state = AsyncValue.data(
        base.copyWith(
          actionError: mapKdsError(error),
          actionErrorCode: kdsErrorCode(error),
        ),
      );
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
      state = AsyncValue.data(
        base.copyWith(
          actionError: mapKdsError(error),
          actionErrorCode: kdsErrorCode(error),
        ),
      );
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
/// management UI (Task 4/5/6, plus the initial `listScreens` load error
/// branch in `kds_settings_section.dart`) must display. Public (not
/// underscore-prefixed) so `kds_settings_section.dart` can reuse the exact
/// same mapping for the initial-load error instead of maintaining a second,
/// less complete mapper — final whole-branch review finding: the load-error
/// branch must never surface raw `AppException.message` text. Not shared
/// with `kitchen_remote_controller.dart`'s own error mapper because the
/// label set is specific to the admin screen-management flows and does not
/// overlap with the kitchen remote pairing/session error vocabulary.
String mapKdsError(Object error) {
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

/// Structured counterpart to [mapKdsError]: derives the
/// [KdsScreenManagementState.actionErrorCode] paired with the French
/// message. Business logic must always branch on this code, never on the
/// French text `mapKdsError` returns.
///
/// - A [NetworkException] never carries a reliable business `code` from the
///   backend (there was no response), so it always maps to `NETWORK_ERROR`
///   regardless of whatever `error.code` happens to hold.
/// - Any other [AppException] uses its own `error.code` when present (e.g.
///   `KDS_SCREEN_KEY_ALREADY_EXISTS`), falling back to `UNKNOWN_ERROR` when
///   the exception carries no business code at all (e.g. a plain 403
///   `ForbiddenException` with no `code`) — deliberately treated the same
///   as a fully unrecognized error, since neither gives calling code a
///   structured signal to branch on.
/// - Anything that isn't an [AppException] is `UNKNOWN_ERROR`.
String kdsErrorCode(Object error) {
  if (error is NetworkException) {
    return 'NETWORK_ERROR';
  }
  if (error is AppException) {
    return error.code ?? 'UNKNOWN_ERROR';
  }
  return 'UNKNOWN_ERROR';
}
