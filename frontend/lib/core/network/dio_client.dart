import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../storage/session_store.dart';

/// Bumped whenever the refresh token is rejected and the session is cleared.
/// The session controller listens and drops back to the sign-in screens.
final ValueNotifier<int> sessionExpiredSignal = ValueNotifier<int>(0);

/// Configured Dio instance with auth, refresh and device-key headers.
class DioClient {
  DioClient(this._session) {
    dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    dio.interceptors.add(_authInterceptor());
  }

  final SessionStore _session;
  late final Dio dio;

  Future<bool>? _inflightRefresh;

  /// Endpoints where a 401 means "wrong credentials", not "token expired".
  /// /auth/me and /auth/switch-outlet are not listed, so they refresh.
  static const _noRefreshPaths = [
    '/auth/login',
    '/auth/select-outlet',
    '/auth/refresh',
    '/auth/pin/',
    '/auth/forgot-password',
    '/auth/reset-password',
  ];

  InterceptorsWrapper _authInterceptor() => InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _session.accessToken;
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          if (options.path.contains('/auth/pin/')) {
            final deviceKey = _session.deviceKey;
            if (deviceKey != null) options.headers['X-Device-Key'] = deviceKey;
          }
          handler.next(options);
        },
        onError: (err, handler) async {
          final path = err.requestOptions.path;
          final isAuthCall = _noRefreshPaths.any((p) => path.contains(p));
          if (err.response?.statusCode == 401 && !isAuthCall) {
            final refreshed = await (_inflightRefresh ??= _tryRefresh());
            _inflightRefresh = null;
            if (refreshed) {
              final req = err.requestOptions;
              req.headers['Authorization'] = 'Bearer ${_session.accessToken}';
              try {
                final clone = await dio.fetch(req);
                return handler.resolve(clone);
              } catch (_) {/* fall through */}
            }
          }
          handler.next(err);
        },
      );

  /// Returns true when a new access token was stored. A 400/401/403 from the
  /// refresh endpoint ends the session. A network failure keeps it.
  Future<bool> _tryRefresh() async {
    final refresh = _session.refreshToken;
    if (refresh == null) {
      await _expireSession();
      return false;
    }
    try {
      final res = await Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl))
          .post('/auth/refresh', data: {'refreshToken': refresh});
      final token = res.data['accessToken'] as String?;
      if (token != null) {
        await _session.setAccessToken(token);
        return true;
      }
      await _expireSession();
      return false;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == null) return false; // offline: keep the session
      await _expireSession();
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _expireSession() async {
    await _session.clear();
    sessionExpiredSignal.value++;
  }
}
