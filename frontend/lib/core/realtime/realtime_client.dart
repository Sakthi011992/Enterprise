import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../auth/session_controller.dart';
import '../config/app_config.dart';
import '../providers.dart';
import '../storage/session_store.dart';

/// Event names from the backend realtime gateway (PLAN 1.7 "Realtime").
abstract final class RealtimeEvents {
  static const kdsTicketCreated = 'kds.ticket.created';
  static const kdsTicketUpdated = 'kds.ticket.updated';
  static const kdsReady = 'kds.ready';
  static const menuItem86 = 'menu.item86';
  static const stockLow = 'stock.low';
  static const tabNearLimit = 'tab.nearLimit';
  static const orderUpdated = 'order.updated';
}

/// One message from the gateway. [payload] is the JSON object the server sent.
class RealtimeEvent {
  const RealtimeEvent({required this.event, required this.payload});

  final String event;
  final Map<String, dynamic> payload;
}

/// `<origin of the API base>/rt`, the Socket.IO namespace of the gateway.
/// `http://localhost:3000/api/v1` becomes `http://localhost:3000/rt`.
String realtimeUrl(String apiBaseUrl) {
  final uri = Uri.parse(apiBaseUrl);
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port/rt';
}

/// Delay before reconnect attempt [attempt] (0-based): 1, 2, 4 ... 30 seconds.
Duration reconnectDelay(int attempt) {
  final seconds = 1 << attempt.clamp(0, 5);
  return Duration(seconds: seconds > 30 ? 30 : seconds);
}

/// Socket.IO client for the `/rt` namespace. Authenticates with the stored
/// access token. Socket.IO reconnects dropped links on its own; when the
/// handshake itself is refused (for example an expired token) the client
/// rebuilds the socket with a back-off so the next attempt reads a fresh token.
class RealtimeClient {
  RealtimeClient({required SessionStore store, String? url})
      : _store = store,
        _url = url ?? realtimeUrl(AppConfig.apiBaseUrl);

  final SessionStore _store;
  final String _url;

  final ValueNotifier<bool> _connected = ValueNotifier<bool>(false);
  final Map<String, StreamController<RealtimeEvent>> _controllers = {};
  final Set<String> _bound = {};

  io.Socket? _socket;
  Timer? _reopen;
  List<String> _stations = const [];
  int _attempt = 0;
  bool _started = false;
  bool _disposed = false;

  /// True while the socket is connected. Screens poll while this is false.
  ValueListenable<bool> get connected => _connected;

  /// Broadcast stream of one event name. Subscribing before [connect] is fine.
  Stream<RealtimeEvent> on(String event) {
    final controller = _controllers.putIfAbsent(
      event,
      () => StreamController<RealtimeEvent>.broadcast(),
    );
    final socket = _socket;
    if (socket != null && _bound.add(event)) _bind(socket, event);
    return controller.stream;
  }

  /// Opens the socket once. [stations] are joined as `outlet:<id>:station:<s>`
  /// by the server. Safe to call again; later calls do nothing.
  void connect({List<String> stations = const []}) {
    if (_started || _disposed) return;
    _started = true;
    _stations = stations;
    _open();
  }

  void _open() {
    if (_disposed) return;
    _reopen?.cancel();
    _reopen = null;
    final old = _socket;
    _socket = null;
    _bound.clear();
    old?.dispose();

    final token = _store.accessToken;
    if (token == null) {
      _connected.value = false;
      return;
    }
    final socket = io.io(
      _url,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          // A fresh manager each time: the package caches managers per URL, and a
          // disposed one can't be reused after a token change or a reopen.
          .enableForceNew()
          .setAuth({'token': token, 'stations': _stations})
          .build(),
    );
    socket.onConnect((_) {
      _attempt = 0;
      _connected.value = true;
    });
    socket.onDisconnect((_) {
      _connected.value = false;
    });
    socket.onConnectError((_) {
      _connected.value = false;
      _scheduleReopen();
    });
    _socket = socket;
    for (final event in _controllers.keys) {
      if (_bound.add(event)) _bind(socket, event);
    }
    socket.connect();
  }

  void _scheduleReopen() {
    if (_disposed || _reopen != null) return;
    _reopen = Timer(reconnectDelay(_attempt), () {
      _reopen = null;
      _attempt++;
      _open();
    });
  }

  void _bind(io.Socket socket, String event) {
    socket.on(event, (dynamic data) {
      final controller = _controllers[event];
      if (controller == null || controller.isClosed) return;
      controller.add(RealtimeEvent(event: event, payload: _payloadOf(data)));
    });
  }

  static Map<String, dynamic> _payloadOf(dynamic data) {
    final raw = data is List && data.isNotEmpty ? data.first : data;
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  /// Closes the socket and every stream. Called when the provider is disposed.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _reopen?.cancel();
    _socket?.dispose();
    _socket = null;
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
    _connected.value = false;
    _connected.dispose();
  }
}

/// One client per signed-in session. It connects when a session exists and is
/// rebuilt on login or logout.
final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final store = ref.watch(sessionStoreProvider);
  final loggedIn = ref.watch(sessionProvider.select((s) => s.session != null));
  final client = RealtimeClient(store: store);
  ref.onDispose(client.dispose);
  if (loggedIn) client.connect();
  return client;
});

/// Events of one name, for `ref.listen` in screens.
final realtimeEventProvider =
    StreamProvider.autoDispose.family<RealtimeEvent, String>(
  (ref, event) => ref.watch(realtimeClientProvider).on(event),
);
