import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

/// Lightweight persistent session storage backed by Hive.
///
/// The session JSON (PLAN 1.5) is stored as a string so nested maps come back
/// with the right types. Tokens are stored separately. The device key and the
/// pinned nav items survive logout; [clear] only removes the signed-in state.
class SessionStore {
  static const _box = 'session';
  static const _kAccess = 'accessToken';
  static const _kRefresh = 'refreshToken';
  static const _kUser = 'user';
  static const _kSession = 'sessionJson';
  static const _kDeviceKey = 'deviceKey';
  static const _kPinnedNav = 'pinnedNavIds';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_box);
  }

  Box get _b => Hive.box(_box);

  String? get accessToken => _b.get(_kAccess) as String?;
  String? get refreshToken => _b.get(_kRefresh) as String?;
  Map? get user => _b.get(_kUser) as Map?;
  String? get role => user?['role'] as String?;
  bool get isLoggedIn => accessToken != null;

  /// Session JSON from the last login or /auth/me (no tokens), or null.
  Map<String, dynamic>? get session {
    final raw = _b.get(_kSession) as String?;
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Saves a session payload. Tokens are written only when the payload carries
  /// them, so GET /auth/me can refresh the session info without wiping tokens.
  Future<void> saveSession(Map<String, dynamic> json) async {
    final body = Map<String, dynamic>.from(json)
      ..remove('accessToken')
      ..remove('refreshToken');
    final updates = <String, dynamic>{_kSession: jsonEncode(body)};
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    if (access is String) updates[_kAccess] = access;
    if (refresh is String) updates[_kRefresh] = refresh;
    await _b.putAll(updates);
  }

  /// Legacy writer kept for old callers.
  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required Map user,
  }) async {
    await _b.putAll({_kAccess: accessToken, _kRefresh: refreshToken, _kUser: user});
  }

  Future<void> setAccessToken(String token) => _b.put(_kAccess, token);

  /// Shared-tablet key from POST /devices (shown once on the admin side).
  String? get deviceKey => _b.get(_kDeviceKey) as String?;

  Future<void> setDeviceKey(String? key) async {
    if (key == null || key.trim().isEmpty) {
      await _b.delete(_kDeviceKey);
    } else {
      await _b.put(_kDeviceKey, key.trim());
    }
  }

  List<String> get pinnedNavIds =>
      ((_b.get(_kPinnedNav) as List?) ?? const []).map((e) => e.toString()).toList();

  Future<void> setPinnedNavIds(List<String> ids) => _b.put(_kPinnedNav, ids);

  /// Removes the signed-in state (tokens, session, legacy user). Keeps the
  /// device key and pinned items.
  Future<void> clear() async {
    await _b.deleteAll([_kAccess, _kRefresh, _kUser, _kSession]);
  }
}
