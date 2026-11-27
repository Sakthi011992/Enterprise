import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/offline_poller.dart';
import '../../../core/realtime/realtime_client.dart';
import 'guest_models.dart';
import 'guest_requests_repository.dart';

/// Staff realtime events for guest ordering (PLAN 2.6).
abstract final class GuestRealtimeEvents {
  static const requestNew = 'guest.request.new';
  static const requestDecided = 'guest.request.decided';
  static const serviceNew = 'service.request.new';
  static const serviceUpdated = 'service.request.updated';

  static const all = [requestNew, requestDecided, serviceNew, serviceUpdated];
}

/// Pending rounds for the outlet, oldest first.
final pendingGuestRequestsProvider = FutureProvider<List<GuestRequest>>((ref) async {
  final list = await ref.watch(guestRequestsRepositoryProvider).pendingRequests();
  return [...list]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
});

/// Open and acknowledged service requests (bill, call waiter).
final serviceRequestsProvider = FutureProvider<List<ServiceRequest>>(
  (ref) => ref.watch(guestRequestsRepositoryProvider).openServiceRequests(),
);

/// Count shown on the Guest orders nav item and footer tab: pending rounds
/// plus service requests nobody has acknowledged yet.
final guestBadgeCountProvider = Provider<int>((ref) {
  final rounds = ref.watch(pendingGuestRequestsProvider).valueOrNull ?? const [];
  final service = ref.watch(serviceRequestsProvider).valueOrNull ?? const [];
  return rounds.length + service.where((s) => !s.isAcknowledged).length;
});

/// Keeps the guest lists fresh: refetches on any guest realtime event and
/// polls every 5 s while the socket is down. Watch it from any widget that
/// shows guest data (screen, footer badge, floor badges).
final guestLiveProvider = Provider<void>((ref) {
  final client = ref.watch(realtimeClientProvider);
  void refresh() {
    ref.invalidate(pendingGuestRequestsProvider);
    ref.invalidate(serviceRequestsProvider);
  }

  final subs = <StreamSubscription<RealtimeEvent>>[
    for (final e in GuestRealtimeEvents.all) client.on(e).listen((_) => refresh()),
  ];
  final poller = OfflinePoller(
    connected: client.connected,
    interval: const Duration(seconds: 5),
    refresh: () async => refresh(),
  )..start();
  ref.onDispose(() {
    poller.stop();
    for (final s in subs) {
      s.cancel();
    }
  });
});

/// App-level guest configuration (admin only).
final guestConfigProvider = FutureProvider.autoDispose<GuestConfig>(
  (ref) => ref.watch(guestRequestsRepositoryProvider).config(),
);

/// A seated table's guest PIN, or null (no PIN, not TABLE_PIN mode, or no access).
final guestPinProvider = FutureProvider.autoDispose.family<String?, String>((ref, tableId) async {
  try {
    return await ref.watch(guestRequestsRepositoryProvider).guestPin(tableId);
  } catch (_) {
    return null;
  }
});

/// What the floor plan shows on one table card.
class TableGuestInfo {
  const TableGuestInfo({this.newRounds = 0, this.billAsked = false});

  final int newRounds;
  final bool billAsked;
}

final tableGuestInfoProvider = Provider.family<TableGuestInfo, String>((ref, tableId) {
  final rounds = ref.watch(pendingGuestRequestsProvider).valueOrNull ?? const [];
  final service = ref.watch(serviceRequestsProvider).valueOrNull ?? const [];
  return TableGuestInfo(
    newRounds: rounds.where((r) => r.tableId == tableId).length,
    billAsked: service.any((s) => s.tableId == tableId && s.isBill),
  );
});
