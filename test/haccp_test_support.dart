import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Support de test HACCP : depot factice + overrides (aucun reseau).
Widget haccpTestApp(Widget home, {ThemeData? theme}) {
  return ProviderScope(
    overrides: [
      haccpRepositoryProvider.overrideWithValue(_FakeHaccpRepository()),
      sessionControllerProvider.overrideWith(_AdminSession.new),
      onlineStatusProvider.overrideWith((ref) => Stream.value(true)),
      syncQueueProvider.overrideWith(_EmptyQueue.new),
      tenantConfigProvider.overrideWith(
        (ref) async => throw StateError('config indisponible en test'),
      ),
    ],
    child: MaterialApp(theme: theme, home: home),
  );
}

class _EmptyQueue extends SyncQueue {
  @override
  List<QueuedAction> build() => const [];
}

class _AdminSession extends SessionController {
  @override
  Future<SessionState> build() async {
    return const SessionState.authenticated(
      user: StaffUser(
        id: 1,
        email: 'admin@test.com',
        role: 'admin',
        tenantSlug: 'pizza',
        permissions: null,
        mustChangePassword: false,
      ),
      tenantSlug: 'pizza',
      sessionId: 1,
    );
  }
}

final _now = DateTime.now();
String get _iso => _now.toIso8601String();
String _day(int offset) =>
    _now.add(Duration(days: offset)).toIso8601String().substring(0, 10);

class _FakeHaccpRepository extends Fake implements HaccpRepository {
  @override
  Future<HaccpStatus> getStatusToday() async => HaccpStatus.fromJson({
        'today': _day(0),
        'opening': {
          'session_id': 7,
          'status': 'in_progress',
          'temperatures_done': 2,
          'temperatures_total': 3,
          'dlc_done': 1,
          'cleaning_done': 2,
          'cleaning_total': 3,
          'has_non_conformities': true,
        },
        'closing': {'status': 'not_started'},
        'can_open': false,
        'can_close': false,
        'open_non_conformities': 1,
      });

  @override
  Future<List<HaccpCheckSession>> getTodaySessions() async => const [];

  @override
  Future<List<HaccpEquipment>> listEquipment({bool activeOnly = true}) async =>
      [
        for (final e in [
          (1, 'Chambre froide positive', 'cold_room', 0.0, 4.0),
          (2, 'Congelateur', 'freezer', -22.0, -18.0),
          (3, 'Frigo bar', 'fridge', null, null),
        ])
          HaccpEquipment.fromJson({
            'id': e.$1,
            'name': e.$2,
            'type': e.$3,
            'location': 'Cuisine',
            'target_min_temp': e.$4,
            'target_max_temp': e.$5,
          }),
      ];

  @override
  Future<List<HaccpTemperatureLog>> listTemperatures(int sessionId) async => [
        HaccpTemperatureLog.fromJson({
          'id': 1,
          'session_id': sessionId,
          'equipment_id': 2,
          'measured_temp': -20.5,
          'is_compliant': true,
          'logged_at': _iso,
        }),
      ];

  @override
  Future<List<HaccpDlcCheck>> listDlcChecks(int sessionId) async => [
        HaccpDlcCheck.fromJson({
          'id': 1,
          'session_id': sessionId,
          'batch_id': 42,
          'ingredient_name': 'Mozzarella',
          'dlc_level': 1,
          'dlc_date': _day(3),
          'location': 'Chambre froide',
          'is_compliant': true,
          'logged_at': _iso,
        }),
      ];

  @override
  Future<List<HaccpCleaningTask>> listCleaningTasks({
    String? sessionType,
  }) async =>
      [
        for (final t in [
          (1, 'Plan de travail'),
          (2, 'Sol cuisine'),
          (3, 'Chambre froide'),
        ])
          HaccpCleaningTask.fromJson({
            'id': t.$1,
            'name': t.$2,
            'zone': 'Cuisine',
            'frequency': 'daily',
            'session_type': sessionType ?? 'closing',
            'product_used': 'Desinfectant',
          }),
      ];

  @override
  Future<List<HaccpCleaningLog>> listCleaningLogs(int sessionId) async => [
        HaccpCleaningLog.fromJson({
          'id': 1,
          'session_id': sessionId,
          'task_id': 2,
          'completed_at': _iso,
        }),
      ];

  @override
  Future<List<HaccpFryingOilLog>> listFryingOilLogs(int sessionId) async =>
      const [];

  @override
  Future<List<HaccpNonConformity>> listNonConformities({
    String? status,
  }) async =>
      [
        HaccpNonConformity.fromJson({
          'id': 501,
          'session_id': 7,
          'source_type': 'temperature',
          'source_id': 1,
          'description': 'Chambre froide #2 : mesure hors plage (8 °C)',
          'status': 'open',
          'created_at': _iso,
        }),
        HaccpNonConformity.fromJson({
          'id': 502,
          'source_type': 'dlc',
          'description': 'DLC depassee sur creme fraiche',
          'corrective_action': 'Produit retire et jete',
          'status': 'in_progress',
          'created_at': _iso,
        }),
      ];

  @override
  Future<List<HaccpReceptionControl>> listReceptionControls({
    DateTime? date,
  }) async =>
      [
        HaccpReceptionControl.fromJson({
          'id': 1,
          'supplier_name': 'Fournisseur Frais SARL',
          'product_name': 'Jambon blanc',
          'batch_ref': 'L2408',
          'delivery_temp': 3.2,
          'dlc_date': _day(6),
          'is_compliant': true,
          'controlled_at': _iso,
        }),
        HaccpReceptionControl.fromJson({
          'id': 2,
          'supplier_name': 'Fournisseur Frais SARL',
          'product_name': 'Creme fraiche',
          'delivery_temp': 9.0,
          'temp_ok': false,
          'is_compliant': false,
          'corrective_action': 'Refuse',
          'controlled_at': _iso,
        }),
      ];

  @override
  Future<List<HaccpCoolingLog>> listCoolingLogs({
    bool activeOnly = false,
  }) async =>
      [
        HaccpCoolingLog.fromJson({
          'id': 1,
          'product_name': 'Sauce tomate',
          'temp_initial': 63.0,
          'started_at':
              _now.subtract(const Duration(hours: 2)).toIso8601String(),
          'temp_final': 8.0,
          'ended_at': _iso,
          'is_compliant': true,
          'created_at': _iso,
        }),
        HaccpCoolingLog.fromJson({
          'id': 2,
          'product_name': 'Bechamel',
          'temp_initial': 70.0,
          'started_at':
              _now.subtract(const Duration(minutes: 20)).toIso8601String(),
          'created_at': _iso,
        }),
      ];

  @override
  Future<List<HaccpTrainingRecord>> listTrainingRecords({int? userId}) async =>
      [
        HaccpTrainingRecord.fromJson({
          'id': 1,
          'user_id': 3,
          'training_type': 'Hygiene alimentaire',
          'training_date': _day(-200),
          'expiry_date': _day(160),
          'created_at': _iso,
        }),
        HaccpTrainingRecord.fromJson({
          'id': 2,
          'user_id': 4,
          'training_type': 'HACCP niveau 2',
          'training_date': _day(-400),
          'expiry_date': _day(-10),
          'created_at': _iso,
        }),
      ];
}
