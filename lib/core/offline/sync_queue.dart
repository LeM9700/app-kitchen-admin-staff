import 'dart:convert';

import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
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

  /// Bumped whenever the on-disk shape or storage model of [QueuedAction]
  /// changes.
  ///
  /// - Version 1 (legacy): a single global blob, no tenant/user identity.
  /// - Version 2: single global blob, but each action tagged with its
  ///   tenant/user/session.
  /// - Version 3 (current): [SyncQueue] partitions storage physically, one
  ///   secure-storage key per `tenantSlug`+`userId` — a session's process
  ///   never even reads another identity's bytes off disk. Entries lacking
  ///   [tenantSlug]/[userId] (version 1) or found under the wrong partition
  ///   during the one-time migration are routed to a write-only quarantine
  ///   bucket that no session ever reads back (see [SyncQueue]).
  static const currentFormatVersion = 3;

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

  /// Session identifier captured at queue time, kept purely as audit
  /// metadata.
  ///
  /// [🔒 SÉCURITÉ] A refresh-token rotation issues a new backend session id
  /// for the *same* tenant/user without ever changing [SessionState] in
  /// memory (see `ApiClient._performRefresh`, which only rewrites the token
  /// store — it never touches [SessionController]'s state). So a queued
  /// action's [sessionId] can legitimately go stale relative to the current
  /// backend session while the app is still running as the very same
  /// person. It must never gate replay — only [tenantSlug] + [userId] do,
  /// see [matchesIdentity].
  final int? sessionId;

  final int formatVersion;
  final String? idempotencyKey;
  final int retryCount;
  final String? lastError;

  /// Diagnostic metadata only, set right before an action is moved into the
  /// write-only quarantine bucket during migration. Never rendered by any
  /// UI and never read back by the app — see [SyncQueue].
  final String? blockReason;

  bool get hasKnownIdentity => tenantSlug != null && userId != null;

  /// Whether this action was queued by the given tenant/user. Deliberately
  /// ignores [sessionId] — see its doc comment.
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
      blockReason: identical(blockReason, _unset)
          ? this.blockReason
          : blockReason as String?,
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

/// Minimal secure key/value contract [SyncQueue] depends on. Exists so
/// tests can substitute a deterministic in-memory backend — one that also
/// simulates several identities' partitions sharing the same "disk" — as a
/// thin fake, instead of having to mock `FlutterSecureStorage`'s platform
/// channel or guess at its exact method signatures.
abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production backend: wraps the real [FlutterSecureStorage].
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Offline action queue, physically partitioned by tenant + user on disk.
///
/// [🔒 SÉCURITÉ] There is no shared, cross-account storage bucket that this
/// class (or any provider built on top of it) ever loads into an app-visible
/// list. Each signed-in identity gets its own secure-storage key; a session
/// only ever reads and writes the key matching *its own* tenant + user, so
/// another account's queued labels, payloads, endpoints or order/HACCP data
/// are never even deserialized into memory for a different session — not
/// just filtered out of the UI. `state` on this notifier is therefore always
/// exactly "my own pending actions", nothing more.
///
/// Entries that cannot be attributed to the signed-in identity (pre-tenant-
/// tagging legacy actions, or actions found under the wrong identity during
/// the one-time migration off the old single global key) are moved to a
/// write-only quarantine bucket: the app appends to it but never reads it
/// back, for any session. They are effectively unrecoverable through the
/// app UI — a deliberate trade-off of recoverability for confidentiality.
class SyncQueue extends Notifier<List<QueuedAction>> {
  /// Storage backend. Overridable (`@protected`) so tests can substitute an
  /// in-memory fake — production always uses real secure storage.
  @protected
  SecureKeyValueStore get storage => const FlutterSecureKeyValueStore();

  /// Pre-partitioning global key (format versions 1 and 2). Read at most
  /// once per identity, to migrate any leftovers, then deleted for good.
  static const _legacyGlobalKey = 'admin_staff_sync_queue';

  /// Write-only: appended to during migration, never read back by the app.
  static const _quarantineKey = 'admin_staff_sync_queue_quarantine';

  String? _tenantSlug;
  int? _userId;
  int? _sessionId;
  int _loadGeneration = 0;
  bool _sessionListenerAttached = false;

  @override
  List<QueuedAction> build() {
    if (!_sessionListenerAttached) {
      _sessionListenerAttached = true;
      ref.listen<AsyncValue<SessionState>>(
        sessionControllerProvider,
        (_, next) => _activateSession(next.valueOrNull),
        fireImmediately: true,
      );
    }
    return const [];
  }

  String? get _partitionKey {
    final tenantSlug = _tenantSlug;
    final userId = _userId;
    if (tenantSlug == null || userId == null) {
      return null;
    }
    return 'admin_staff_sync_queue::$tenantSlug::$userId';
  }

  void _activateSession(SessionState? session) {
    _tenantSlug = session?.tenantSlug;
    _userId = session?.user?.id;
    _sessionId = session?.sessionId;
    _loadGeneration += 1;
    state = const [];
    load();
  }

  bool _isCurrentLoad(int generation, String key) {
    return generation == _loadGeneration && key == _partitionKey;
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
    final tenantSlug = _tenantSlug;
    final userId = _userId;
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
        sessionId: _sessionId,
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

  void remove(String id) {
    state = state.where((action) => action.id != id).toList();
    persist();
  }

  /// Loads this identity's own partition from secure storage. Exposed as
  /// `@protected` (rather than private) so tests can substitute an
  /// in-memory backend without having to re-implement the tenant/session
  /// stamping logic in [add].
  @protected
  Future<void> load() async {
    final key = _partitionKey;
    final tenantSlug = _tenantSlug;
    final userId = _userId;
    final generation = _loadGeneration;
    if (key == null || tenantSlug == null || userId == null) {
      // No signed-in identity: nothing can be safely loaded or shown.
      return;
    }
    final raw = await storage.read(key);
    if (!_isCurrentLoad(generation, key)) {
      return;
    }
    if (raw != null && raw.isNotEmpty) {
      state = _decode(raw);
      // Already on the partitioned layout: still sweep the legacy key once,
      // in case it holds *other* identities' leftovers to quarantine.
      await _migrateLegacyKey(
        mergeIntoOwnState: false,
        tenantSlug: tenantSlug,
        userId: userId,
        generation: generation,
        key: key,
      );
      return;
    }
    await _migrateLegacyKey(
      mergeIntoOwnState: true,
      tenantSlug: tenantSlug,
      userId: userId,
      generation: generation,
      key: key,
    );
  }

  /// One-time migration off the pre-partitioning single global key.
  ///
  /// Every entry that matches the signed-in identity is adopted into this
  /// partition (so a legitimate pending action survives the upgrade);
  /// everything else — another identity's actions, or entries with no
  /// identity at all — is moved to the write-only quarantine bucket. The
  /// global key is deleted once fully redistributed, so this only ever runs
  /// once across all identities that use this device.
  ///
  /// [⚠️ PROD] On a device whose legacy queue mixed several accounts, only
  /// the first identity to load after this migration ships recovers its own
  /// actions; the rest are quarantined (and therefore unrecoverable through
  /// the app). This is intentional: confidentiality wins over convenience.
  Future<void> _migrateLegacyKey({
    required bool mergeIntoOwnState,
    required String tenantSlug,
    required int userId,
    required int generation,
    required String key,
  }) async {
    final legacyRaw = await storage.read(_legacyGlobalKey);
    if (!_isCurrentLoad(generation, key)) {
      return;
    }
    if (legacyRaw == null || legacyRaw.isEmpty) {
      return;
    }
    final legacyActions = _decode(legacyRaw);
    final mine = <QueuedAction>[];
    final quarantined = <QueuedAction>[];
    for (final action in legacyActions) {
      if (action.matchesIdentity(tenantSlug: tenantSlug, userId: userId)) {
        mine.add(action);
      } else {
        quarantined.add(
          action.copyWith(
            blockReason: action.hasKnownIdentity
                ? 'migrated_foreign_identity'
                : 'migrated_unknown_origin',
          ),
        );
      }
    }
    if (mergeIntoOwnState && mine.isNotEmpty) {
      state = mine;
      await persist(keyOverride: key);
    }
    if (!_isCurrentLoad(generation, key)) {
      return;
    }
    if (quarantined.isNotEmpty) {
      await _appendToQuarantine(quarantined);
    }
    await storage.delete(_legacyGlobalKey);
  }

  Future<void> _appendToQuarantine(List<QueuedAction> actions) async {
    final raw = await storage.read(_quarantineKey);
    final existing =
        raw != null && raw.isNotEmpty ? _decode(raw) : const <QueuedAction>[];
    await storage.write(
      _quarantineKey,
      _encode([...existing, ...actions]),
    );
    // Nothing in the app ever reads _quarantineKey back: this bucket exists
    // purely as a non-destructive record, not a recovery path.
  }

  @protected
  Future<void> persist({String? keyOverride}) async {
    final key = keyOverride ?? _partitionKey;
    if (key == null) {
      return;
    }
    await storage.write(key, _encode(state));
  }

  static List<QueuedAction> _decode(String raw) {
    final decoded = json.decode(raw);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map>()
        .map((value) => QueuedAction.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  static String _encode(List<QueuedAction> actions) {
    return json.encode(actions.map((action) => action.toJson()).toList());
  }
}
