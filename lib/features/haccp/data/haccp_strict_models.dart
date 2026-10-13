import 'package:app_admin_staff/core/utils/json.dart';

class HaccpStrictStatus {
  const HaccpStrictStatus({
    required this.establishmentId,
    required this.businessDate,
    required this.satisfied,
    required this.strictEnabled,
    required this.blockers,
  });

  final int establishmentId;
  final String businessDate;
  final bool satisfied;
  final bool strictEnabled;
  final List<HaccpStrictBlocker> blockers;

  factory HaccpStrictStatus.fromJson(Map<String, dynamic> json) {
    final raw = json['blockers'] as List? ?? const [];
    return HaccpStrictStatus(
      establishmentId: readInt(json['establishment_id']),
      businessDate: json['business_date']?.toString() ?? '',
      satisfied: readBool(json['daily_haccp_satisfied']),
      strictEnabled: readBool(json['strict_enabled']),
      blockers: raw
          .whereType<Map>()
          .map(
            (item) =>
                HaccpStrictBlocker.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}

class HaccpStrictBlocker {
  const HaccpStrictBlocker({required this.code, this.subject});

  final String code;
  final String? subject;

  factory HaccpStrictBlocker.fromJson(Map<String, dynamic> json) {
    return HaccpStrictBlocker(
      code: json['code']?.toString() ?? 'HACCP_BLOCKED',
      subject: json['subject']?.toString(),
    );
  }
}
