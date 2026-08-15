import 'dart:async';
import 'dart:convert';

import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/core/config/env.dart';
import 'package:app_admin_staff/core/realtime/notification_bus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final client = RealtimeClient(
    ref.watch(tokenStoreProvider),
    ref.read(notificationBusProvider.notifier),
  );
  ref.onDispose(client.disconnect);
  return client;
});

enum RealtimeConnectionStatus {
  disconnected,
  connecting,
  connected,
}

class RealtimeClient {
  RealtimeClient(
    this._tokenStore,
    this._bus, {
    WebSocketChannelFactory? channelFactory,
    Duration reconnectBaseDelay = const Duration(seconds: 2),
  })  : _channelFactory = channelFactory ?? WebSocketChannel.connect,
        _reconnectBaseDelay = reconnectBaseDelay;

  final TokenStore _tokenStore;
  final NotificationBus _bus;
  final WebSocketChannelFactory _channelFactory;
  final Duration _reconnectBaseDelay;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  String? _token;
  String? _tenant;
  bool _intentionalDisconnect = true;
  int _reconnectAttempts = 0;
  RealtimeConnectionStatus _status = RealtimeConnectionStatus.disconnected;

  RealtimeConnectionStatus get status => _status;

  Future<void> connect() async {
    final token = await _tokenStore.readAccessToken();
    final tenant = await _tokenStore.readTenantSlug();
    if (token == null || tenant == null) {
      await disconnect();
      return;
    }
    if (_status != RealtimeConnectionStatus.disconnected &&
        _token == token &&
        _tenant == tenant) {
      return;
    }
    await disconnect();
    _intentionalDisconnect = false;
    _token = token;
    _tenant = tenant;
    _status = RealtimeConnectionStatus.connecting;
    _logDev('connect tenant=$tenant');

    final channel = _channelFactory(_wsUri(tenant));
    _channel = channel;
    _subscription = channel.stream.listen(
      (message) {
        _handleMessage(message, token);
      },
      onError: (error) {
        _logDev('socket error');
        _scheduleReconnect();
      },
      onDone: () {
        _logDev('socket closed');
        _scheduleReconnect();
      },
      cancelOnError: true,
    );
    _status = RealtimeConnectionStatus.connected;
    _reconnectAttempts = 0;
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _status = RealtimeConnectionStatus.disconnected;
    _logDev('disconnect');
  }

  void _handleMessage(Object? message, String token) {
    final decoded = _decode(message);
    if (decoded == null) {
      return;
    }
    final type = decoded['type']?.toString();
    if (type == 'auth_required') {
      _channel?.sink.add(json.encode({'type': 'auth', 'token': token}));
      return;
    }
    if (type == 'auth_ok') {
      _logDev('auth_ok');
      return;
    }
    if (type == 'ping') {
      _channel?.sink.add(json.encode({'type': 'pong'}));
      return;
    }
    _bus.route(decoded);
  }

  Map<String, dynamic>? _decode(Object? message) {
    try {
      final decoded = json.decode(message.toString());
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      _logDev('invalid message ignored');
    }
    return null;
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect) {
      return;
    }
    _status = RealtimeConnectionStatus.disconnected;
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final milliseconds =
        (_reconnectBaseDelay.inMilliseconds * _reconnectAttempts).clamp(
      100,
      30000,
    );
    _reconnectTimer = Timer(Duration(milliseconds: milliseconds), connect);
    _logDev('reconnect scheduled ${milliseconds}ms');
  }

  Uri _wsUri(String tenantSlug) {
    final base = Uri.parse(Env.apiBaseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final path = '$basePath${ApiEndpoints.notificationsWs}';
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: path,
      queryParameters: {'tenant_slug': tenantSlug},
    );
  }

  void _logDev(String message) {
    if (kDebugMode) {
      debugPrint('[realtime] $message');
    }
  }
}
