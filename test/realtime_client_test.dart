import 'dart:async';
import 'dart:convert';

import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/core/realtime/notification_bus.dart';
import 'package:app_admin_staff/core/realtime/websocket_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('auth_required sends auth payload and ping sends pong', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final channel = _FakeWebSocketChannel();
    final client = RealtimeClient(
      _MemoryTokenStore(),
      container.read(notificationBusProvider.notifier),
      channelFactory: (_) => channel,
    );
    addTearDown(client.disconnect);

    await client.connect();
    channel.receive({'type': 'auth_required'});
    channel.receive({'type': 'ping'});
    await Future<void>.delayed(Duration.zero);

    expect(channel.sink.sent.first, contains('"type":"auth"'));
    expect(channel.sink.sent.first, contains('"token":"access"'));
    expect(channel.sink.sent.last, contains('"type":"pong"'));
  });

  test('unknown event is ignored and known event is routed', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final channel = _FakeWebSocketChannel();
    final client = RealtimeClient(
      _MemoryTokenStore(),
      container.read(notificationBusProvider.notifier),
      channelFactory: (_) => channel,
    );
    addTearDown(client.disconnect);

    await client.connect();
    channel.receive({'event': 'mystery.event', 'type': 'notification'});
    channel.receive({'event': 'order.created', 'type': 'notification'});
    await Future<void>.delayed(Duration.zero);

    final notifications = container.read(notificationBusProvider);
    expect(notifications, hasLength(1));
    expect(notifications.first.event, 'order.created');
  });

  test('closed socket schedules reconnect', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final channels = <_FakeWebSocketChannel>[];
    final client = RealtimeClient(
      _MemoryTokenStore(),
      container.read(notificationBusProvider.notifier),
      reconnectBaseDelay: const Duration(milliseconds: 100),
      channelFactory: (_) {
        final channel = _FakeWebSocketChannel();
        channels.add(channel);
        return channel;
      },
    );
    addTearDown(client.disconnect);

    await client.connect();
    await channels.first.closeFromServer();
    await _waitFor(() => channels.length == 2);

    expect(channels, hasLength(2));
  });

  test('disconnect closes socket', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final channel = _FakeWebSocketChannel();
    final client = RealtimeClient(
      _MemoryTokenStore(),
      container.read(notificationBusProvider.notifier),
      channelFactory: (_) => channel,
    );

    await client.connect();
    await client.disconnect();

    expect(channel.sink.closed, isTrue);
  });
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _FakeWebSocketChannel implements WebSocketChannel {
  // The tests close this controller either from the server side or through
  // tearDown after disconnecting the fake socket.
  // ignore: close_sinks
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  // ignore: close_sinks
  final _FakeWebSocketSink _sink = _FakeWebSocketSink();

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  _FakeWebSocketSink get sink => _sink;

  void receive(Map<String, dynamic> payload) {
    _incoming.add(jsonEncode(payload));
  }

  Future<void> closeFromServer() {
    return _incoming.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWebSocketSink implements WebSocketSink {
  final sent = <String>[];
  final Completer<void> _done = Completer<void>();
  bool closed = false;

  @override
  Future<void> get done => _done.future;

  @override
  void add(Object? data) {
    sent.add(data.toString());
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final item in stream) {
      add(item);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}

class _MemoryTokenStore extends TokenStore {
  _MemoryTokenStore() : super(const FlutterSecureStorage());

  @override
  Future<String?> readAccessToken() async => 'access';

  @override
  Future<String?> readTenantSlug() async => 'pizza';
}
