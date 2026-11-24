import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/storage/session_store.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider), ref.watch(sessionStoreProvider));
});

class AuthRepository {
  AuthRepository(this._dio, this._session);
  final Dio _dio;
  final SessionStore _session;

  Future<Map> login(String username, String password) async {
    final res = await _dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
    final data = res.data as Map;
    final user = Map<String, dynamic>.from(data['user'] as Map);
    // Normalise features to List<String> so Hive round-trips it cleanly.
    user['features'] = ((user['features'] as List?) ?? []).map((e) => e.toString()).toList();
    await _session.save(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      user: user,
    );
    return user;
  }

  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {}
    await _session.clear();
  }
}
