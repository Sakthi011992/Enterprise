import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/auth/api_error.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/guest_dio.dart';
import '../../../core/realtime/realtime_client.dart' show realtimeUrl, reconnectDelay;
import '../../pos/data/pos_models.dart' show asMap;
import 'guest_models.dart';
import 'guest_repository.dart';

/// Guest realtime event names (PLAN 2.6).
abstract final class GuestEvents {
  static const orderUpdated = 'guest.order.updated';
  static const sessionClosed = 'guest.session.closed';
}

/// [GuestRepository] against the backend contracts in PLAN 2.3–2.5.
///
/// Realtime: the staff [RealtimeClient] reads the staff access token from the
/// session store, so it can't carry a guest token. This class opens its own
/// Socket.IO link on the same `/rt` namespace with `auth: { token: guestToken }`
/// (the server joins it only to `table:<id>`). Polling covers the gaps.
class HttpGuestRepository implements GuestRepository {
  HttpGuestRepository(this._dio, this._holder, {String? socketUrl})
      : _socketUrl = socketUrl ?? realtimeUrl(AppConfig.apiBaseUrl);

  final Dio _dio;
  final GuestTokenHolder _holder;
  final String _socketUrl;

  final _events = StreamController<GuestLiveEvent>.broadcast();
  final _connected = ValueNotifier<bool>(false);
  io.Socket? _socket;
  Timer? _reopen;
  int _attempt = 0;
  bool _disposed = false;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  @override
  set token(String? value) {
    if (_holder.token == value) return;
    _holder.token = value;
    _closeSocket();
    if (value != null && _events.hasListener) _openSocket();
  }

  @override
  Future<GuestTableInfo> lookup(String qrToken) => _guard(() async {
        final r = await _dio.get<dynamic>('/guest/t/$qrToken');
        return GuestTableInfo.fromJson(asMap(r.data));
      });

  @override
  Future<GuestStart> start(
    String qrToken, {
    required String deviceKey,
    required String name,
    required String phone,
    required bool consent,
  }) =>
      _guard(() async {
        final r = await _dio.post<dynamic>('/guest/t/$qrToken/start', data: {
          'deviceKey': deviceKey,
          'name': name,
          'phone': phone,
          'consent': consent,
        });
        return GuestStart.fromJson(asMap(r.data));
      });

  @override
  Future<GuestJoin> verify(String qrToken, {required String verificationId, required String code}) =>
      _guard(() async {
        final r = await _dio.post<dynamic>('/guest/t/$qrToken/verify',
            data: {'verificationId': verificationId, 'code': code});
        return GuestJoin.fromJson(asMap(r.data));
      });

  @override
  Future<GuestMenu> menu({String? qrToken}) => _guard(() async {
        final path = _holder.token == null && qrToken != null ? '/guest/t/$qrToken/menu' : '/guest/menu';
        final r = await _dio.get<dynamic>(path);
        return GuestMenu.fromJson(r.data);
      });

  @override
  Future<GuestRoundView> placeRound(String roundKey, List<GuestRoundItem> items) =>
      _guard(() async {
        final r = await _dio.post<dynamic>('/guest/rounds', data: {
          'roundKey': roundKey,
          'items': [for (final i in items) i.toJson()],
        });
        return GuestRound.fromJson(asMap(r.data));
      });

  @override
  Future<void> cancelRound(String roundId) => _guard(() async {
        await _dio.delete<dynamic>('/guest/rounds/$roundId');
      });

  @override
  Future<GuestOrderView> order() => _guard(() async {
        final r = await _dio.get<dynamic>('/guest/order');
        return GuestOrderView.fromJson(asMap(r.data));
      });

  @override
  Future<GuestServiceRequest> serviceRequest(GuestServiceType type) => _guard(() async {
        final r = await _dio.post<dynamic>('/guest/service-requests',
            data: {'type': serviceTypeWire(type)});
        return GuestServiceRequest.fromJson(asMap(r.data));
      });

  @override
  Future<GuestCheckout> checkout({String mode = 'WAITER'}) => _guard(() async {
        final r = await _dio.post<dynamic>('/guest/checkout', data: {'mode': mode});
        return GuestCheckout.fromJson(asMap(r.data));
      });

  @override
  Future<void> confirmAge() => _guard(() async {
        await _dio.post<dynamic>('/guest/age-confirm');
      });

  // --- realtime ---------------------------------------------------------------

  @override
  ValueListenable<bool> get liveConnected => _connected;

  @override
  Stream<GuestLiveEvent> live() {
    if (_socket == null && _holder.token != null) _openSocket();
    return _events.stream;
  }

  void _openSocket() {
    if (_disposed) return;
    final token = _holder.token;
    if (token == null) return;
    _reopen?.cancel();
    _reopen = null;
    final socket = io.io(
      _socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          .setAuth({'token': token})
          .build(),
    );
    socket.onConnect((_) {
      _attempt = 0;
      _connected.value = true;
    });
    socket.onDisconnect((_) => _connected.value = false);
    socket.onConnectError((_) {
      _connected.value = false;
      _scheduleReopen();
    });
    socket.on(GuestEvents.orderUpdated, (dynamic data) {
      final raw = data is List && data.isNotEmpty ? data.first : data;
      if (raw is Map && !_events.isClosed) {
        _events.add(GuestOrderUpdated(GuestOrderView.fromJson(asMap(raw))));
      }
    });
    socket.on(GuestEvents.sessionClosed, (_) {
      if (!_events.isClosed) _events.add(const GuestSessionClosed());
    });
    _socket = socket;
    socket.connect();
  }

  void _scheduleReopen() {
    if (_disposed || _reopen != null) return;
    _reopen = Timer(reconnectDelay(_attempt), () {
      _reopen = null;
      _attempt++;
      _closeSocket();
      _openSocket();
    });
  }

  void _closeSocket() {
    _socket?.dispose();
    _socket = null;
    if (!_disposed) _connected.value = false;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _reopen?.cancel();
    _closeSocket();
    _disposed = true;
    _events.close();
    _connected.dispose();
  }
}
