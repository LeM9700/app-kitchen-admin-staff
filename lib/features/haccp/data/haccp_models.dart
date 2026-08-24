/// Modèles de données HACCP — sécurité alimentaire.
///
/// Conventions de nommage : camelCase pour les champs Dart,
/// snake_case pour les clés JSON (via fromJson).
library haccp_models;

// ─── Equipment ───────────────────────────────────────────────────────────────

class HaccpEquipment {
  const HaccpEquipment({
    required this.id,
    required this.name,
    required this.type,
    this.location,
    this.targetMinTemp,
    this.targetMaxTemp,
    required this.checkAtOpening,
    required this.checkAtClosing,
    required this.isActive,
  });

  final int id;
  final String name;
  final String type;
  final String? location;
  final double? targetMinTemp;
  final double? targetMaxTemp;
  final bool checkAtOpening;
  final bool checkAtClosing;
  final bool isActive;

  factory HaccpEquipment.fromJson(Map<String, dynamic> json) {
    return HaccpEquipment(
      id: json['id'] as int,
      name: json['name'] as String,
      type: json['type'] as String,
      location: json['location'] as String?,
      targetMinTemp: (json['target_min_temp'] as num?)?.toDouble(),
      targetMaxTemp: (json['target_max_temp'] as num?)?.toDouble(),
      checkAtOpening: json['check_at_opening'] as bool? ?? true,
      checkAtClosing: json['check_at_closing'] as bool? ?? true,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  /// Libellé de la plage de température cible.
  String get tempRangeLabel {
    if (targetMinTemp == null || targetMaxTemp == null) return 'Non défini';
    return '${targetMinTemp!.toStringAsFixed(0)}°C – ${targetMaxTemp!.toStringAsFixed(0)}°C';
  }
}

// ─── Check Sessions ───────────────────────────────────────────────────────────

enum HaccpSessionType { opening, closing }

enum HaccpSessionStatus { notStarted, inProgress, complete, incompleteValidated }

class HaccpCheckSession {
  const HaccpCheckSession({
    required this.id,
    required this.sessionType,
    required this.date,
    required this.status,
    this.startedBy,
    this.completedBy,
    this.completedAt,
    this.notes,
  });

  final int id;
  final String sessionType;
  final DateTime date;
  final String status;
  final int? startedBy;
  final int? completedBy;
  final DateTime? completedAt;
  final String? notes;

  bool get isComplete =>
      status == 'complete' || status == 'incomplete_validated';

  factory HaccpCheckSession.fromJson(Map<String, dynamic> json) {
    return HaccpCheckSession(
      id: json['id'] as int,
      sessionType: json['session_type'] as String,
      date: DateTime.parse(json['date'] as String),
      status: json['status'] as String,
      startedBy: json['started_by'] as int?,
      completedBy: json['completed_by'] as int?,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      notes: json['notes'] as String?,
    );
  }
}

// ─── HACCP Status (gate bloquant) ─────────────────────────────────────────────

class HaccpSessionSummary {
  const HaccpSessionSummary({
    this.sessionId,
    required this.status,
    required this.temperaturesDone,
    required this.temperaturesTotal,
    required this.dlcDone,
    required this.cleaningDone,
    required this.cleaningTotal,
    required this.hasNonConformities,
  });

  final int? sessionId;
  final String status; // not_started | in_progress | complete | incomplete_validated
  final int temperaturesDone;
  final int temperaturesTotal;
  final int dlcDone;
  final int cleaningDone;
  final int cleaningTotal;
  final bool hasNonConformities;

  bool get isComplete =>
      status == 'complete' || status == 'incomplete_validated';

  double get progress {
    final total = temperaturesTotal + cleaningTotal;
    if (total == 0) return 1.0;
    final done = temperaturesDone + cleaningDone;
    return (done / total).clamp(0.0, 1.0);
  }

  factory HaccpSessionSummary.fromJson(Map<String, dynamic> json) {
    return HaccpSessionSummary(
      sessionId: json['session_id'] as int?,
      status: json['status'] as String,
      temperaturesDone: json['temperatures_done'] as int? ?? 0,
      temperaturesTotal: json['temperatures_total'] as int? ?? 0,
      dlcDone: json['dlc_done'] as int? ?? 0,
      cleaningDone: json['cleaning_done'] as int? ?? 0,
      cleaningTotal: json['cleaning_total'] as int? ?? 0,
      hasNonConformities: json['has_non_conformities'] as bool? ?? false,
    );
  }
}

class HaccpStatus {
  const HaccpStatus({
    required this.today,
    required this.opening,
    required this.closing,
    required this.canOpen,
    required this.canClose,
    required this.openNonConformities,
  });

  final DateTime today;
  final HaccpSessionSummary opening;
  final HaccpSessionSummary closing;
  final bool canOpen;
  final bool canClose;
  final int openNonConformities;

  factory HaccpStatus.fromJson(Map<String, dynamic> json) {
    return HaccpStatus(
      today: DateTime.parse(json['today'] as String),
      opening: HaccpSessionSummary.fromJson(
          json['opening'] as Map<String, dynamic>),
      closing: HaccpSessionSummary.fromJson(
          json['closing'] as Map<String, dynamic>),
      canOpen: json['can_open'] as bool,
      canClose: json['can_close'] as bool,
      openNonConformities: json['open_non_conformities'] as int? ?? 0,
    );
  }
}

// ─── Temperature Logs ─────────────────────────────────────────────────────────

class HaccpTemperatureLog {
  const HaccpTemperatureLog({
    required this.id,
    required this.sessionId,
    required this.equipmentId,
    required this.measuredTemp,
    required this.isCompliant,
    this.correctiveAction,
    this.loggedBy,
    required this.loggedAt,
  });

  final int id;
  final int sessionId;
  final int equipmentId;
  final double measuredTemp;
  final bool isCompliant;
  final String? correctiveAction;
  final int? loggedBy;
  final DateTime loggedAt;

  factory HaccpTemperatureLog.fromJson(Map<String, dynamic> json) {
    return HaccpTemperatureLog(
      id: json['id'] as int,
      sessionId: json['session_id'] as int,
      equipmentId: json['equipment_id'] as int,
      measuredTemp: (json['measured_temp'] as num).toDouble(),
      isCompliant: json['is_compliant'] as bool,
      correctiveAction: json['corrective_action'] as String?,
      loggedBy: json['logged_by'] as int?,
      loggedAt: DateTime.parse(json['logged_at'] as String),
    );
  }
}

// ─── DLC Checks ───────────────────────────────────────────────────────────────

class HaccpDlcCheck {
  const HaccpDlcCheck({
    required this.id,
    required this.sessionId,
    this.ingredientId,
    this.batchId,
    required this.ingredientName,
    required this.dlcLevel,
    required this.dlcDate,
    this.location,
    required this.isCompliant,
    this.correctiveAction,
    this.loggedBy,
    required this.loggedAt,
  });

  final int id;
  final int sessionId;
  final int? ingredientId;
  final int? batchId;
  final String ingredientName;
  final int dlcLevel;
  final DateTime dlcDate;
  final String? location;
  final bool isCompliant;
  final String? correctiveAction;
  final int? loggedBy;
  final DateTime loggedAt;

  /// Libellé niveau DLC pour affichage.
  String get levelLabel {
    switch (dlcLevel) {
      case 1:
        return 'DLC emballage';
      case 2:
        return 'DLC conservation';
      case 3:
        return 'DLC utilisation';
      default:
        return 'DLC';
    }
  }

  factory HaccpDlcCheck.fromJson(Map<String, dynamic> json) {
    return HaccpDlcCheck(
      id: json['id'] as int,
      sessionId: json['session_id'] as int,
      ingredientId: json['ingredient_id'] as int?,
      batchId: json['batch_id'] as int?,
      ingredientName: json['ingredient_name'] as String,
      dlcLevel: json['dlc_level'] as int,
      dlcDate: DateTime.parse(json['dlc_date'] as String),
      location: json['location'] as String?,
      isCompliant: json['is_compliant'] as bool,
      correctiveAction: json['corrective_action'] as String?,
      loggedBy: json['logged_by'] as int?,
      loggedAt: DateTime.parse(json['logged_at'] as String),
    );
  }
}

// ─── Cleaning Tasks & Logs ────────────────────────────────────────────────────

class HaccpCleaningTask {
  const HaccpCleaningTask({
    required this.id,
    required this.name,
    required this.zone,
    required this.frequency,
    required this.sessionType,
    this.productUsed,
    required this.requiredRole,
    required this.isActive,
  });

  final int id;
  final String name;
  final String zone;
  final String frequency;
  final String sessionType;
  final String? productUsed;
  final String requiredRole;
  final bool isActive;

  factory HaccpCleaningTask.fromJson(Map<String, dynamic> json) {
    return HaccpCleaningTask(
      id: json['id'] as int,
      name: json['name'] as String,
      zone: json['zone'] as String,
      frequency: json['frequency'] as String,
      sessionType: json['session_type'] as String,
      productUsed: json['product_used'] as String?,
      requiredRole: json['required_role'] as String? ?? 'staff',
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class HaccpCleaningLog {
  const HaccpCleaningLog({
    required this.id,
    required this.sessionId,
    required this.taskId,
    this.completedBy,
    required this.completedAt,
    this.notes,
    required this.isCompliant,
  });

  final int id;
  final int sessionId;
  final int taskId;
  final int? completedBy;
  final DateTime completedAt;
  final String? notes;
  final bool isCompliant;

  factory HaccpCleaningLog.fromJson(Map<String, dynamic> json) {
    return HaccpCleaningLog(
      id: json['id'] as int,
      sessionId: json['session_id'] as int,
      taskId: json['task_id'] as int,
      completedBy: json['completed_by'] as int?,
      completedAt: DateTime.parse(json['completed_at'] as String),
      notes: json['notes'] as String?,
      isCompliant: json['is_compliant'] as bool? ?? true,
    );
  }
}

// ─── Frying Oil Logs ──────────────────────────────────────────────────────────

class HaccpFryingOilLog {
  const HaccpFryingOilLog({
    required this.id,
    required this.sessionId,
    required this.polarityPercent,
    required this.isCompliant,
    this.color,
    this.odor,
    this.correctiveAction,
    this.loggedBy,
    required this.loggedAt,
  });

  final int id;
  final int sessionId;
  final double polarityPercent;
  final bool isCompliant;
  final String? color;
  final String? odor;
  final String? correctiveAction;
  final int? loggedBy;
  final DateTime loggedAt;

  factory HaccpFryingOilLog.fromJson(Map<String, dynamic> json) {
    return HaccpFryingOilLog(
      id: json['id'] as int,
      sessionId: json['session_id'] as int,
      polarityPercent: (json['polarity_percent'] as num).toDouble(),
      isCompliant: json['is_compliant'] as bool,
      color: json['color'] as String?,
      odor: json['odor'] as String?,
      correctiveAction: json['corrective_action'] as String?,
      loggedBy: json['logged_by'] as int?,
      loggedAt: DateTime.parse(json['logged_at'] as String),
    );
  }
}

// ─── Reception Controls ───────────────────────────────────────────────────────

class HaccpReceptionControl {
  const HaccpReceptionControl({
    required this.id,
    this.sessionId,
    required this.supplierName,
    required this.productName,
    this.batchRef,
    this.deliveryTemp,
    this.dlcDate,
    required this.packagingOk,
    required this.labelingOk,
    required this.tempOk,
    required this.isCompliant,
    this.correctiveAction,
    this.controlledBy,
    required this.controlledAt,
  });

  final int id;
  final int? sessionId;
  final String supplierName;
  final String productName;
  final String? batchRef;
  final double? deliveryTemp;
  final DateTime? dlcDate;
  final bool packagingOk;
  final bool labelingOk;
  final bool tempOk;
  final bool isCompliant;
  final String? correctiveAction;
  final int? controlledBy;
  final DateTime controlledAt;

  factory HaccpReceptionControl.fromJson(Map<String, dynamic> json) {
    return HaccpReceptionControl(
      id: json['id'] as int,
      sessionId: json['session_id'] as int?,
      supplierName: json['supplier_name'] as String,
      productName: json['product_name'] as String,
      batchRef: json['batch_ref'] as String?,
      deliveryTemp: (json['delivery_temp'] as num?)?.toDouble(),
      dlcDate: json['dlc_date'] != null
          ? DateTime.parse(json['dlc_date'] as String)
          : null,
      packagingOk: json['packaging_ok'] as bool? ?? true,
      labelingOk: json['labeling_ok'] as bool? ?? true,
      tempOk: json['temp_ok'] as bool? ?? true,
      isCompliant: json['is_compliant'] as bool,
      correctiveAction: json['corrective_action'] as String?,
      controlledBy: json['controlled_by'] as int?,
      controlledAt: DateTime.parse(json['controlled_at'] as String),
    );
  }
}

// ─── Cooling Logs ─────────────────────────────────────────────────────────────

class HaccpCoolingLog {
  const HaccpCoolingLog({
    required this.id,
    this.sessionId,
    required this.productName,
    required this.tempInitial,
    required this.startedAt,
    this.tempFinal,
    this.endedAt,
    required this.isCompliant,
    this.correctiveAction,
    this.loggedBy,
    required this.createdAt,
  });

  final int id;
  final int? sessionId;
  final String productName;
  final double tempInitial;
  final DateTime startedAt;
  final double? tempFinal;
  final DateTime? endedAt;
  final bool isCompliant;
  final String? correctiveAction;
  final int? loggedBy;
  final DateTime createdAt;

  bool get isInProgress => tempFinal == null;

  /// Durée de refroidissement en minutes (null si en cours).
  int? get durationMinutes {
    if (endedAt == null) return null;
    return endedAt!.difference(startedAt).inMinutes;
  }

  factory HaccpCoolingLog.fromJson(Map<String, dynamic> json) {
    return HaccpCoolingLog(
      id: json['id'] as int,
      sessionId: json['session_id'] as int?,
      productName: json['product_name'] as String,
      tempInitial: (json['temp_initial'] as num).toDouble(),
      startedAt: DateTime.parse(json['started_at'] as String),
      tempFinal: (json['temp_final'] as num?)?.toDouble(),
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      isCompliant: json['is_compliant'] as bool? ?? true,
      correctiveAction: json['corrective_action'] as String?,
      loggedBy: json['logged_by'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

// ─── Training Records ─────────────────────────────────────────────────────────

class HaccpTrainingRecord {
  const HaccpTrainingRecord({
    required this.id,
    required this.userId,
    required this.trainingType,
    required this.trainingDate,
    this.expiryDate,
    this.certificateRef,
    this.trainerName,
    this.notes,
    required this.createdAt,
  });

  final int id;
  final int userId;
  final String trainingType;
  final DateTime trainingDate;
  final DateTime? expiryDate;
  final String? certificateRef;
  final String? trainerName;
  final String? notes;
  final DateTime createdAt;

  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());

  bool get expiresWithin30Days {
    if (expiryDate == null) return false;
    final daysLeft = expiryDate!.difference(DateTime.now()).inDays;
    return daysLeft >= 0 && daysLeft <= 30;
  }

  String get trainingTypeLabel {
    switch (trainingType) {
      case 'hygiene_initial':
        return 'Hygiène alimentaire (initiale)';
      case 'hygiene_refresher':
        return 'Hygiène alimentaire (recyclage)';
      case 'haccp':
        return 'HACCP / PMS';
      case 'allergens':
        return 'Gestion des allergènes';
      case 'fire_safety':
        return 'Sécurité incendie';
      default:
        return trainingType;
    }
  }

  factory HaccpTrainingRecord.fromJson(Map<String, dynamic> json) {
    return HaccpTrainingRecord(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      trainingType: json['training_type'] as String,
      trainingDate: DateTime.parse(json['training_date'] as String),
      expiryDate: json['expiry_date'] != null
          ? DateTime.parse(json['expiry_date'] as String)
          : null,
      certificateRef: json['certificate_ref'] as String?,
      trainerName: json['trainer_name'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

// ─── Non-Conformities ─────────────────────────────────────────────────────────

class HaccpNonConformity {
  const HaccpNonConformity({
    required this.id,
    this.sessionId,
    required this.sourceType,
    this.sourceId,
    required this.description,
    this.correctiveAction,
    this.validatedBy,
    this.validatedAt,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final int? sessionId;
  final String sourceType;
  final int? sourceId;
  final String description;
  final String? correctiveAction;
  final int? validatedBy;
  final DateTime? validatedAt;
  final String status;
  final DateTime createdAt;

  bool get isOpen => status == 'open' || status == 'in_progress';

  factory HaccpNonConformity.fromJson(Map<String, dynamic> json) {
    return HaccpNonConformity(
      id: json['id'] as int,
      sessionId: json['session_id'] as int?,
      sourceType: json['source_type'] as String,
      sourceId: json['source_id'] as int?,
      description: json['description'] as String,
      correctiveAction: json['corrective_action'] as String?,
      validatedBy: json['validated_by'] as int?,
      validatedAt: json['validated_at'] != null
          ? DateTime.parse(json['validated_at'] as String)
          : null,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

// ─── Stats (scorecard hebdomadaire) ──────────────────────────────────────────

/// Statistiques de conformité pour une catégorie HACCP.
class HaccpStatSection {
  const HaccpStatSection({
    required this.compliant,
    required this.total,
    required this.complianceRate,
  });

  final int compliant;
  final int total;

  /// Taux de conformité 0–100. Retourne 100 si aucune donnée (période vide).
  final double complianceRate;

  factory HaccpStatSection.fromJson(Map<String, dynamic> json) {
    return HaccpStatSection(
      compliant: (json['compliant'] as num).toInt(),
      total: (json['total'] as num).toInt(),
      complianceRate: (json['compliance_rate'] as num).toDouble(),
    );
  }
}

class HaccpSessionStats {
  const HaccpSessionStats({
    required this.openingCompleted,
    required this.openingTotal,
    required this.closingCompleted,
    required this.closingTotal,
    required this.completionRate,
  });

  final int openingCompleted;
  final int openingTotal;
  final int closingCompleted;
  final int closingTotal;
  final double completionRate;

  factory HaccpSessionStats.fromJson(Map<String, dynamic> json) {
    return HaccpSessionStats(
      openingCompleted: (json['opening_completed'] as num).toInt(),
      openingTotal: (json['opening_total'] as num).toInt(),
      closingCompleted: (json['closing_completed'] as num).toInt(),
      closingTotal: (json['closing_total'] as num).toInt(),
      completionRate: (json['completion_rate'] as num).toDouble(),
    );
  }
}

class HaccpNcStats {
  const HaccpNcStats({
    required this.open,
    required this.inProgress,
    required this.closed,
    required this.total,
    required this.resolutionRate,
  });

  final int open;
  final int inProgress;
  final int closed;
  final int total;

  /// Taux de résolution = closed / total.
  final double resolutionRate;

  factory HaccpNcStats.fromJson(Map<String, dynamic> json) {
    return HaccpNcStats(
      open: (json['open'] as num).toInt(),
      inProgress: (json['in_progress'] as num).toInt(),
      closed: (json['closed'] as num).toInt(),
      total: (json['total'] as num).toInt(),
      resolutionRate: (json['resolution_rate'] as num).toDouble(),
    );
  }
}

class HaccpCoolingStats {
  const HaccpCoolingStats({
    required this.compliant,
    required this.nonCompliant,
    required this.inProgress,
    required this.total,
    required this.complianceRate,
  });

  final int compliant;
  final int nonCompliant;
  final int inProgress;
  final int total;
  final double complianceRate;

  factory HaccpCoolingStats.fromJson(Map<String, dynamic> json) {
    return HaccpCoolingStats(
      compliant: (json['compliant'] as num).toInt(),
      nonCompliant: (json['non_compliant'] as num).toInt(),
      inProgress: (json['in_progress'] as num).toInt(),
      total: (json['total'] as num).toInt(),
      complianceRate: (json['compliance_rate'] as num).toDouble(),
    );
  }
}

/// Scorecard HACCP hebdomadaire — retourné par GET /haccp/stats.
class HaccpStatsData {
  const HaccpStatsData({
    required this.fromDate,
    required this.toDate,
    required this.sessions,
    required this.temperature,
    required this.dlc,
    required this.cleaning,
    required this.nonConformities,
    required this.reception,
    required this.cooling,
    required this.overallScore,
  });

  final String fromDate;
  final String toDate;
  final HaccpSessionStats sessions;
  final HaccpStatSection temperature;
  final HaccpStatSection dlc;
  final HaccpStatSection cleaning;
  final HaccpNcStats nonConformities;
  final HaccpStatSection reception;
  final HaccpCoolingStats cooling;

  /// Score global pondéré 0–100 (calculé côté serveur).
  final double overallScore;

  /// Niveau de score : good (≥80), warning (60–79), poor (<60).
  String get scoreLevel {
    if (overallScore >= 80) return 'good';
    if (overallScore >= 60) return 'warning';
    return 'poor';
  }

  factory HaccpStatsData.fromJson(Map<String, dynamic> json) {
    return HaccpStatsData(
      fromDate: json['from_date'] as String,
      toDate: json['to_date'] as String,
      sessions: HaccpSessionStats.fromJson(
          json['sessions'] as Map<String, dynamic>),
      temperature: HaccpStatSection.fromJson(
          json['temperature'] as Map<String, dynamic>),
      dlc: HaccpStatSection.fromJson(json['dlc'] as Map<String, dynamic>),
      cleaning:
          HaccpStatSection.fromJson(json['cleaning'] as Map<String, dynamic>),
      nonConformities: HaccpNcStats.fromJson(
          json['non_conformities'] as Map<String, dynamic>),
      reception:
          HaccpStatSection.fromJson(json['reception'] as Map<String, dynamic>),
      cooling: HaccpCoolingStats.fromJson(
          json['cooling'] as Map<String, dynamic>),
      overallScore: (json['overall_score'] as num).toDouble(),
    );
  }
}
