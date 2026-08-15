import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final syncQueueProvider = NotifierProvider<SyncQueue, List<QueuedAction>>(
  SyncQueue.new,
);

class QueuedAction {
  const QueuedAction({
    required this.id,
    required this.feature,
    required this.label,
    required this.endpoint,
    required this.method,
    required this.payload,
    required this.createdAt,
    this.idempotencyKey,
    this.retryCount = 0,
    this.lastError,
  });

  final String id;
  final String feature;
  final String label;
  final String endpoint;
  final String method;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String? idempotencyKey;
  final int retryCount;
  final String? lastError;

  QueuedAction copyWith({
    int? retryCount,
    String? lastError,
  }) {
    return QueuedAction(
      id: id,
      feature: feature,
      label: label,
      endpoint: endpoint,
      method: method,
      payload: payload,
      createdAt: createdAt,
      idempotencyKey: idempotencyKey,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
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
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      'retry_count': retryCount,
      if (lastError != null) 'last_error': lastError,
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
      idempotencyKey: json['idempotency_key']?.toString(),
      retryCount: int.tryParse(json['retry_count']?.toString() ?? '') ?? 0,
      lastError: json['last_error']?.toString(),
    );
  }
}

class SyncQueue extends Notifier<List<QueuedAction>> {
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'admin_staff_sync_queue';

  @override
  List<QueuedAction> build() {
    _load();
    return const [];
  }

  void add({
    required String feature,
    required String label,
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
    String? lastError,
  }) {
    state = [
      QueuedAction(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        feature: feature,
        label: label,
        endpoint: endpoint,
        method: method,
        payload: payload,
        createdAt: DateTime.now(),
        idempotencyKey: idempotencyKey,
        lastError: lastError,
      ),
      ...state,
    ];
    _persist();
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
    _persist();
  }

  void remove(String id) {
    state = state.where((action) => action.id != id).toList();
    _persist();
  }

  Future<void> _load() async {
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

  Future<void> _persist() async {
    await _storage.write(
      key: _storageKey,
      value: json.encode(state.map((action) => action.toJson()).toList()),
    );
  }
}
