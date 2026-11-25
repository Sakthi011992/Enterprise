import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../network/dio_client.dart';
import '../providers.dart';
import '../storage/session_store.dart';
import 'api_error.dart';
import 'session.dart';

/// Error codes set by the controller (not from the API).
abstract class SessionErrorCode {
  static const network = 'NETWORK';
  static const sessionExpired = 'SESSION_EXPIRED';
  static const deviceInvalid = 'DEVICE_INVALID';
}

class SessionState {
  const SessionState({
    this.session,
    this.loading = false,
    this.error,
    this.errorCode,
    this.errorDetails,
    this.pendingOutletChoice,
  });

  final Session? session;
  final bool loading;

  /// Message from the last failed call. Screens map [errorCode] to friendly text.
  final String? error;

  /// API `code`, [SessionErrorCode.network], or null.
  final String? errorCode;
  final Map<String, dynamic>? errorDetails;

  /// Set after a password login that needs an outlet choice.
  final OutletChoice? pendingOutletChoice;

  bool get isLoggedIn => session != null;
}

/// Owns the signed-in session and every auth call that changes it.
class SessionController extends StateNotifier<SessionState> {
  SessionController(this._ref) : super(const SessionState()) {
    _restore();
    sessionExpiredSignal.addListener(_onExpired);
  }

  final Ref _ref;

  AuthRepository get _repo => _ref.read(authRepositoryProvider);
  SessionStore get _store => _ref.read(sessionStoreProvider);

  void _restore() {
    final json = _store.session;
    if (json == null || _store.accessToken == null) return;
    try {
      state = SessionState(session: Session.fromJson(json));
    } catch (_) {
      // Unreadable stored session: stay signed out and let the user log in again.
    }
  }

  void _onExpired() {
    state = const SessionState(
      error: 'Your session has ended. Sign in again.',
      errorCode: SessionErrorCode.sessionExpired,
    );
  }

  void _failed(Object e, {Session? keepSession, OutletChoice? keepChoice}) {
    final err = ApiError.from(e);
    state = SessionState(
      session: keepSession,
      pendingOutletChoice: keepChoice,
      error: err.message,
      errorCode: err.isNetwork ? SessionErrorCode.network : err.code,
      errorDetails: err.details,
    );
  }

  Future<void> loginWithPassword(String username, String password) async {
    state = const SessionState(loading: true);
    try {
      final outcome = await _repo.login(username, password);
      final session = outcome.session;
      state = session != null
          ? SessionState(session: session)
          : SessionState(pendingOutletChoice: outcome.choice);
    } catch (e) {
      _failed(e);
    }
  }

  /// Completes the outlet choice from a password login.
  Future<void> selectOutlet(String outletId) async {
    final choice = state.pendingOutletChoice;
    if (choice == null) return;
    state = SessionState(pendingOutletChoice: choice, loading: true);
    try {
      final session = await _repo.selectOutlet(choice.selectionToken, outletId);
      state = SessionState(session: session);
    } catch (e) {
      _failed(e, keepChoice: choice);
    }
  }

  /// Moves a signed-in user to another outlet. Returns true on success.
  Future<bool> switchOutlet(String outletId) async {
    final current = state.session;
    state = SessionState(session: current, loading: true);
    try {
      final session = await _repo.switchOutlet(outletId);
      state = SessionState(session: session);
      return true;
    } catch (e) {
      _failed(e, keepSession: current);
      return false;
    }
  }

  /// Staff PIN login on a registered tablet. Returns true on success.
  Future<bool> loginWithPin(String userId, String pin) async {
    if (_store.deviceKey == null) {
      state = const SessionState(
        error: "This tablet isn't set up yet.",
        errorCode: SessionErrorCode.deviceInvalid,
      );
      return false;
    }
    state = const SessionState(loading: true);
    try {
      final session = await _repo.pinLogin(userId, pin);
      state = SessionState(session: session);
      return true;
    } catch (e) {
      _failed(e);
      return false;
    }
  }

  /// Always resolves to true when the server was reached: the reset link is
  /// sent silently and the screen shows the same message either way.
  Future<bool> forgotPassword(String usernameOrEmail) async {
    try {
      await _repo.forgotPassword(usernameOrEmail);
      return true;
    } catch (e) {
      _failed(e, keepSession: state.session);
      return false;
    }
  }

  Future<bool> resetPassword(String token, String newPassword) async {
    state = const SessionState();
    try {
      await _repo.resetPassword(token, newPassword);
      return true;
    } catch (e) {
      _failed(e);
      return false;
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const SessionState();
  }

  /// Drops a pending outlet choice so the user can go back to sign-in.
  void cancelOutletChoice() {
    state = const SessionState();
  }

  /// Clears the last error (keeps the session and any pending choice).
  void clearError() {
    state = SessionState(
      session: state.session,
      pendingOutletChoice: state.pendingOutletChoice,
    );
  }

  /// Reloads the session from GET /auth/me. A 401 ends the session.
  Future<void> refreshMe() async {
    try {
      final session = await _repo.me();
      state = SessionState(session: session);
    } catch (e) {
      final err = ApiError.from(e);
      if (err.isUnauthorized) {
        await _store.clear();
        state = const SessionState();
      } else {
        _failed(e, keepSession: state.session);
      }
    }
  }

  @override
  void dispose() {
    sessionExpiredSignal.removeListener(_onExpired);
    super.dispose();
  }
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(ref),
);
