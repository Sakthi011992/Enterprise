import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/session.dart';
import '../../../core/providers.dart';
import '../../../core/storage/session_store.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider), ref.watch(sessionStoreProvider));
});

/// Result of a password login: either a signed-in session or an outlet choice.
class AuthOutcome {
  const AuthOutcome.signedIn(Session this.session) : choice = null;
  const AuthOutcome.needsOutlet(OutletChoice this.choice) : session = null;

  final Session? session;
  final OutletChoice? choice;
}

class PinStaffMember {
  const PinStaffMember({required this.userId, required this.displayName, required this.personaName});

  final String userId;
  final String displayName;
  final String personaName;

  factory PinStaffMember.fromJson(Map<String, dynamic> json) => PinStaffMember(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String,
        personaName: json['personaName'] as String,
      );
}

class PinStaffList {
  const PinStaffList({required this.outletName, required this.staff});

  final String outletName;
  final List<PinStaffMember> staff;
}

/// Calls every endpoint in PLAN 1.5 and persists sessions to [SessionStore].
/// Dio errors are rethrown as [ApiError].
class AuthRepository {
  AuthRepository(this._dio, this._store);

  final Dio _dio;
  final SessionStore _store;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  Future<Session> _persist(Map<String, dynamic> data) async {
    await _store.saveSession(data);
    return Session.fromJson(data);
  }

  Future<AuthOutcome> login(String username, String password) => _guard(() async {
        final res = await _dio.post('/auth/login', data: {
          'username': username,
          'password': password,
        });
        final data = Map<String, dynamic>.from(res.data as Map);
        if (data['needsOutlet'] == true) {
          return AuthOutcome.needsOutlet(_choice(data));
        }
        return AuthOutcome.signedIn(await _persist(data));
      });

  Future<Session> selectOutlet(String selectionToken, String outletId) => _guard(() async {
        final res = await _dio.post('/auth/select-outlet', data: {
          'selectionToken': selectionToken,
          'outletId': outletId,
        });
        return _persist(Map<String, dynamic>.from(res.data as Map));
      });

  Future<Session> switchOutlet(String outletId) => _guard(() async {
        final res = await _dio.post('/auth/switch-outlet', data: {'outletId': outletId});
        return _persist(Map<String, dynamic>.from(res.data as Map));
      });

  /// Returns the new access token. The DioClient interceptor normally does this.
  Future<String> refreshAccessToken(String refreshToken) => _guard(() async {
        final res = await _dio.post('/auth/refresh', data: {'refreshToken': refreshToken});
        return res.data['accessToken'] as String;
      });

  /// Clears local state even when the server call fails.
  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {/* local sign-out still happens */}
    await _store.clear();
  }

  Future<Session> me() => _guard(() async {
        final res = await _dio.get('/auth/me');
        return _persist(Map<String, dynamic>.from(res.data as Map));
      });

  Future<void> forgotPassword(String usernameOrEmail) => _guard(() async {
        await _dio.post('/auth/forgot-password', data: {'usernameOrEmail': usernameOrEmail});
      });

  Future<void> resetPassword(String token, String newPassword) => _guard(() async {
        await _dio.post('/auth/reset-password', data: {
          'token': token,
          'newPassword': newPassword,
        });
      });

  Future<PinStaffList> pinStaff() => _guard(() async {
        final res = await _dio.get('/auth/pin/staff');
        final data = Map<String, dynamic>.from(res.data as Map);
        final outlet = Map<String, dynamic>.from(data['outlet'] as Map);
        final staff = (data['staff'] as List)
            .map((e) => PinStaffMember.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        return PinStaffList(outletName: outlet['name'] as String, staff: staff);
      });

  Future<Session> pinLogin(String userId, String pin) => _guard(() async {
        final res = await _dio.post('/auth/pin/login', data: {'userId': userId, 'pin': pin});
        return _persist(Map<String, dynamic>.from(res.data as Map));
      });

  OutletChoice _choice(Map<String, dynamic> data) => OutletChoice(
        selectionToken: data['selectionToken'] as String,
        outlets: [
          for (final o in (data['outlets'] as List))
            OutletAccess.fromJson(Map<String, dynamic>.from(o as Map)),
        ],
      );
}
