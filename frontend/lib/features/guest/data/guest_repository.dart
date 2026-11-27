import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/guest_dio.dart';
import 'guest_models.dart';
import 'http_guest_repository.dart';
import 'mock_guest_repository.dart';

/// Every guest call (PLAN 2.3–2.5). Failures are thrown as `ApiError` with the
/// server `code` (`CODE_INVALID`, `CODE_LOCKED`, `TABLE_NOT_SEATED` ...).
abstract interface class GuestRepository {
  /// Guest bearer token used by every call after verify.
  set token(String? value);

  /// GET /guest/t/:qrToken (public)
  Future<GuestTableInfo> lookup(String qrToken);

  /// POST /guest/t/:qrToken/start (public)
  Future<GuestStart> start(
    String qrToken, {
    required String deviceKey,
    required String name,
    required String phone,
    required bool consent,
  });

  /// POST /guest/t/:qrToken/verify (public)
  Future<GuestJoin> verify(String qrToken, {required String verificationId, required String code});

  /// GET /guest/menu. Without a guest token (table not seated yet) the
  /// read-only preview at GET /guest/t/:qrToken/menu is used instead.
  Future<GuestMenu> menu({String? qrToken});

  /// POST /guest/rounds. Idempotent on [roundKey].
  Future<GuestRoundView> placeRound(String roundKey, List<GuestRoundItem> items);

  /// DELETE /guest/rounds/:id
  Future<void> cancelRound(String roundId);

  /// GET /guest/order
  Future<GuestOrderView> order();

  /// POST /guest/service-requests
  Future<GuestServiceRequest> serviceRequest(GuestServiceType type);

  /// POST /guest/checkout
  Future<GuestCheckout> checkout({String mode = 'WAITER'});

  /// POST /guest/age-confirm
  Future<void> confirmAge();

  /// `guest.order.updated` / `guest.session.closed` for the current token.
  Stream<GuestLiveEvent> live();

  /// True while realtime events arrive; the app polls while it is false.
  ValueListenable<bool> get liveConnected;

  void dispose();
}

/// `--dart-define=GUEST_MOCK=true` runs the guest app on the in-memory mock.
const bool kGuestMock = bool.fromEnvironment('GUEST_MOCK');

final guestRepositoryProvider = Provider<GuestRepository>((ref) {
  final GuestRepository repo = kGuestMock
      ? MockGuestRepository(simulate: true)
      : HttpGuestRepository(ref.watch(guestDioProvider), ref.watch(guestTokenHolderProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

/// How often the app polls GET /guest/order while the socket is down. Tests
/// override it with null to turn polling off.
final guestPollIntervalProvider = Provider<Duration?>((ref) => const Duration(seconds: 5));
