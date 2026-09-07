import 'dart:convert';

import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final syncQueueProvider = NotifierProvider<SyncQueue, List<QueuedAction>>(
  SyncQueue.new,
);

int pendingSyncCountForFeature(
  Iterable<QueuedAction> actions,
  String feature,
) {
  return actions.where((action) => action.feature == feature).length;
}

/// Queued actions that belong to whoever is signed in right now. Every
/// badge/count/list shown in the UI should read from this provider (not
/// [syncQueueProvider] directly) so another tenant's or user's leftover
/// queue never bleeds into the current session's view.
final currentSessionQueuedActionsProvider =
    Provider<List<QueuedAction>>((ref) {
  final session = ref.watch(sessionControllerProvider).valueOrNull;
  final tenantSlug = session?.tenantSlug;
  final userId = session?.user?.id;
  final actions = ref.watch(syncQueueProvider);
  if (tenantSlug == null || userId == null) {
    return const [];
  }
  return actionsForSession(actions, tenantSlug: tenantSlug, userId: userId)
      .toList();
});

/// Queued actions left behind by another tenant/user, or whose origin
/// cannot be verified. Never flushed automatically — surfaced so the user
/// can explicitly discard them.
final foreignSessionQueuedActionsProvider =
    Provider<List<QueuedAction>>((ref) {
  final session = ref.watch(sessionControllerProvider).valueOrNull;
  final tenantSlug = session?.tenantSlug;
  final userId = session?.user?.id;
  final actions = ref.watch(syncQueueProvider);
  if (tenantSlug == null || userId == null) {
    return actions;
  }
  return actionsForeignToSession(actions, tenantSlug: tenantSlug, userId: userId)
      .toList();
});

/// Actions belonging to the tenant/user currently signed in.
///
/// [⚠️ PROD] Only this subset is safe to render or flush: an action left
/// behind by another tenant or user on this device must never be mixed
/// into the current session's queue or UI.
Iterable<QueuedAction> actionsForSession(
  Iterable<QueuedAction> actions, {
  required String tenantSlug,
  required int userId,
}) {
  return actions.where(
    (action) => action.matchesIdentity(tenantSlug: tenantSlug, userId: userId),
  );
}

/// Actions that were queued by a different tenant and/or user than the one
/// currently signed in on this device, or whose origin cannot be verified
/// (actions persisted before this format existed). These must never be
/// replayed automatically — they are surfaced so the user can discard them.
Iterable<QueuedAction> actionsForeignToSession(
  Iterable<QueuedAction> actions, {
  required String tenantSlug,
  required int userId,
}) {
  return actions.where(
    (action) => !action.matchesIdentity(tenantSlug: tenantSlug, userId: userId),
  );
}

class QueuedAction {
  const QueuedAction({
    required this.id,
    required this.feature,
    required this.label,
    required this.endpoint,
    required this.method,
    required this.payload,
    required this.createdAt,
    this.tenantSlug,
    this.userId,
    this.sessionId,
    this.formatVersion = currentFormatVersion,
    this.idempotencyKey,
    this.retryCount = 0,
    this.lastError,
    this.blockReason,
  });

  /// Bumped whenever the on-disk shape of [QueuedAction] changes.
  ///
  /// Version 1 (legacy) had no tenant/user/session identity at all — those
  /// entries decode with [tenantSlug]/[userId]/[sessionId] left `null` and
  /// are treated as unverifiable origin (see [hasKnownIdentity]).
  static const currentFormatVersion = 2;

  final String id;
  final String feature;
  final String label;
  final String endpoint;
  final String method;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  /// Tenant the action was queued under. `null` only for actions persisted
  /// by a version of the app that predates tenant/user tagging.
  final String? tenantSlug;

  /// Staff user that initiated the action.
  final int? userId;

  /// Non-sensitive session identifier (not a token) captured at queue time,
  /// kept for audit/debugging — never used on its own to authorize replay.
  final int? sessionId;

  final int formatVersion;
  final String? idempotencyKey;
  final int retryCount;
  final String? lastError;

  /// Set by [SyncWorker] when a replay attempt was blocked because the
  /// action's tenant/user did not match the currently signed-in session.
  /// Kept until the user explicitly discards the action.
  final String? blockReason;

  bool get hasKnownIdentity => tenantSlug != null && userId != null;

  bool matchesIdentity({required String tenantSlug, required int userId}) {
    return hasKnownIdentity &&
        this.tenantSlug == tenantSlug &&
        this.userId == userId;
  }

  QueuedAction copyWith({
    int? retryCount,
    String? lastError,
    Object? blockReason = _unset,
  }) {
    return QueuedAction(
      id: id,
      feature: feature,
      label: label,
      endpoint: endpoint,
      method: method,
      payload: payload,
      createdAt: createdAt,
      tenantSlug: tenantSlug,
      userId: userId,
      sessionId: sessionId,
      formatVersion: formatVersion,
      idempotencyKey: idempotencyKey,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      blockReason:
          identical(blockReason, _unset) ? this.blockReason : blockReason as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'feature': feature,
      'label': label,
      'endpoint': endpoint,
      'method': method,
      'payload': payload,
      'created_at': createdAt.toIso8601String(),
      if (tenantSlug != null) 'tenant_slug': tenantSlug,
      if (userId != null) 'user_id': userId,
      if (sessionId != null) 'session_id': sessionId,
      'format_version': formatVersion,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      'retry_count': retryCount,
      if (lastError != null) 'last_error': lastError,
      if (blockReason != null) 'block_reason': blockReason,
    };
  }

  factory QueuedAction.fromJson(Map<String, dynamic> json) {
    return QueuedAction(
      id: json['id']?.toString() ?? '',
      feature: json['feature']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      endpoint: json['endpoint']?.toString() ?? '',
      method: json['method']?.toString() ?? 'PATCH',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      tenantSlug: json['tenant_slug']?.toString(),
      userId: int.tryParse(json['user_id']?.toString() ?? ''),
      sessionId: int.tryParse(json['session_id']?.toString() ?? ''),
      formatVersion:
          int.tryParse(json['format_version']?.toString() ?? '') ?? 1,
      idempotencyKey: json['idempotency_key']?.toString(),
      retryCount: int.tryParse(json['retry_count']?.toString() ?? '') ?? 0,
      lastError: json['last_error']?.toString(),
      blockReason: json['block_reason']?.toString(),
    );
  }
}

const _unset = Object();

class SyncQueue extends Notifier<List<QueuedAction>> {
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'admin_staff_sync_queue';

  @override
  List<QueuedAction> build() {
    load();
    return const [];
  }

  /// Queues [payload] for later replay, stamped with the tenant, user and
  /// session of whoever is signed in right now.
  ///
  /// [🔒 SÉCURITÉ] An action can only ever be queued while a session is
  /// active: without a known tenant/user we cannot later prove who it
  /// belongs to, so it would be unsafe to allow blind replay of it.
  void add({
    required String feature,
    required String label,
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
    String? lastError,
  }) {
    final session = ref.read(sessionControllerProvider).valueOrNull;
    final tenantSlug = session?.tenantSlug;
    final userId = session?.user?.id;
    final sessionId = session?.sessionId;
    if (tenantSlug == null || userId == null) {
      throw StateError(
        'Cannot queue an offline action without an authenticated session.',
      );
    }
    state = [
      QueuedAction(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        feature: feature,
        label: label,
        endpoint: endpoint,
        method: method,
        payload: payload,
        createdAt: DateTime.now(),
        tenantSlug: tenantSlug,
        userId: userId,
        sessionId: sessionId,
        lastError: lastError,
      ),
      ...state,
    ];
    persist();
  }

  void markFailed(String id, String error) {
    state = [
      for (final action in state)
        if (action.id == id)
          action.copyWith(
            retryCount: action.retryCount + 1,
            lastError: error,
          )
        else
          action,
    ];
    persist();
  }

  /// Marks [id] as blocked from replay because it does not belong to the
  /// currently signed-in tenant/user. The action is kept (never sent, never
  /// silently dropped) until the user explicitly discards it.
  void markBlocked(String id, String reason) {
    state = [
      for (final action in state)
        if (action.id == id)
          action.copyWith(blockReason: reason)
        else
          action,
    ];
    persist();
  }

  void remove(String id) {
    state = state.where((action) => action.id != id).toList();
    persist();
  }

  /// Discards every action foreign to [tenantSlug]/[userId]. Used when the
  /// user explicitly chooses to abandon another session's leftover queue
  /// (e.g. from the "blocked actions" panel in Settings).
  void removeForeignTo({required String tenantSlug, required int userId}) {
    state = state
        .where((action) => action.matchesIdentity(
              tenantSlug: tenantSlug,
              userId: userId,
            ))
        .toList();
    persist();
  }

  /// Loads the persisted queue from secure storage. Exposed as `@protected`
  /// (rather than private) so tests can substitute an in-memory backend
  /// without having to re-implement the tenant/session stamping logic in
  /// [add].
  @protected
  Future<void> load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    final decoded = json.decode(raw);
    if (decoded is! List) {
      return;
    }
    state = decoded
        .whereType<Map>()
        .map((value) => QueuedAction.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  @protected
  Future<void> persist() async {
    await _storage.write(
      key: _storageKey,
      value: json.encode(state.map((action) => action.toJson()).toList()),
    );
  }
}
