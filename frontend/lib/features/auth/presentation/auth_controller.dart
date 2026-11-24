import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/features/app_feature.dart';
import '../../../core/providers.dart';
import '../data/auth_repository.dart';

class AuthState {
  const AuthState({
    this.loading = false,
    this.error,
    this.role,
    this.username,
    this.features = const {},
  });
  final bool loading;
  final String? error;
  final String? role;
  final String? username;
  final Set<AppFeature> features;

  bool get isLoggedIn => role != null;
  bool get isAdmin => role == 'ADMIN';

  AuthState copyWith({
    bool? loading,
    String? error,
    String? role,
    String? username,
    Set<AppFeature>? features,
  }) =>
      AuthState(
        loading: loading ?? this.loading,
        error: error,
        role: role ?? this.role,
        username: username ?? this.username,
        features: features ?? this.features,
      );
}

Set<AppFeature> _parseFeatures(dynamic raw) {
  if (raw is! List) return const {};
  return raw
      .map((e) => AppFeature.fromWire(e as String))
      .whereType<AppFeature>()
      .toSet();
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(const AuthState()) {
    final user = _ref.read(sessionStoreProvider).user;
    if (user != null) {
      state = state.copyWith(
        role: user['role'] as String?,
        username: user['username'] as String?,
        features: _parseFeatures(user['features']),
      );
    }
  }
  final Ref _ref;

  Future<bool> login(String username, String password) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final user = await _ref.read(authRepositoryProvider).login(username, password);
      state = AuthState(
        role: user['role'] as String?,
        username: user['username'] as String?,
        features: _parseFeatures(user['features']),
      );
      return true;
    } catch (e) {
      state = state.copyWith(loading: false, error: _message(e));
      return false;
    }
  }

  Future<void> logout() async {
    await _ref.read(authRepositoryProvider).logout();
    state = const AuthState();
  }

  String _message(Object e) {
    final s = e.toString();
    return s.contains('401') ? 'Invalid username or password' : 'Login failed. Check your connection.';
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) => AuthController(ref));
