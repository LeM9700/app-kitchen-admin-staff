import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationBusProvider =
    NotifierProvider<NotificationBus, List<RealtimeNotification>>(
  NotificationBus.new,
);

class RealtimeNotification {
  const RealtimeNotification({
    required this.type,
    this.event,
    this.title,
    this.body,
    this.data = const {},
  });

  final String type;
  final String? event;
  final String? title;
  final String? body;
  final Map<String, dynamic> data;

  String? get notificationId => data['notification_id']?.toString();
  int? get orderId => _readInt(data['order_id'] ?? data['orderId']);

  factory RealtimeNotification.fromJson(Map<String, dynamic> json) {
    final event = json['event']?.toString();
    final isSecurityAlert = event == 'security_alert';
    return RealtimeNotification(
      type: json['type']?.toString() ?? 'notification',
      event: event,
      title: isSecurityAlert
          ? 'Alerte securite'
          : _redactSensitiveText(json['title']?.toString()),
      body: isSecurityAlert
          ? null
          : _redactSensitiveText(json['body']?.toString()),
      data: _sanitizeData(
        Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
      ),
    );
  }

  static final RegExp _sensitiveKeyPattern = RegExp(
    'token|secret|password|authorization|api[_-]?key',
    caseSensitive: false,
  );

  static Map<String, dynamic> _sanitizeData(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (_sensitiveKeyPattern.hasMatch(key)) {
        return MapEntry(key, '[redacted]');
      }
      if (value is Map) {
        return MapEntry(key, _sanitizeData(Map<String, dynamic>.from(value)));
      }
      if (value is List) {
        return MapEntry(
          key,
          value.map((item) {
            if (item is Map) {
              return _sanitizeData(Map<String, dynamic>.from(item));
            }
            return item;
          }).toList(),
        );
      }
      return MapEntry(key, value);
    });
  }

  static String? _redactSensitiveText(String? value) {
    if (value == null) {
      return null;
    }
    return value
        .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._-]+'), 'Bearer [redacted]')
        .replaceAll(
          RegExp(r'(token|secret|password)=\S+', caseSensitive: false),
          r'$1=[redacted]',
        );
  }
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

class RealtimeEventRouter {
  const RealtimeEventRouter();

  bool supports(Map<String, dynamic> payload) {
    final type = payload['type']?.toString();
    final event = payload['event']?.toString();
    if (type == 'notification' && (event == null || event.isEmpty)) {
      return true;
    }
    if (event == null) {
      return false;
    }
    return event.startsWith('order.') ||
        event == 'stock.low_alert' ||
        event.startsWith('hr.') ||
        event == 'loyalty.points_expiring' ||
        event == 'allergen_update' ||
        event == 'security_alert';
  }
}

class NotificationBus extends Notifier<List<RealtimeNotification>> {
  final RealtimeEventRouter _router = const RealtimeEventRouter();

  @override
  List<RealtimeNotification> build() => const [];

  void push(RealtimeNotification notification) {
    final notificationId = notification.notificationId;
    if (notificationId != null &&
        state.any((item) => item.notificationId == notificationId)) {
      return;
    }
    state = [notification, ...state.take(49)];
  }

  void route(Map<String, dynamic> payload) {
    if (!_router.supports(payload)) {
      if (kDebugMode) {
        debugPrint('[realtime] ignored event=${payload['event']}');
      }
      return;
    }
    push(RealtimeNotification.fromJson(payload));
  }
}
