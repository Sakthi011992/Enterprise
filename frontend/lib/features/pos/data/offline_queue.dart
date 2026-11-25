import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../core/auth/api_error.dart';
import 'pos_models.dart';
import 'pos_repository.dart';

/// UUID v4 built from 16 bytes of `Random.secure()`, with no extra package.
String generateOfflineId([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// One stored request in the queue.
class OfflineQueueEntry {
  const OfflineQueueEntry({
    required this.request,
    required this.queuedAt,
    this.attempts = 0,
    this.lastError,
  });

  final CreateOrder request;
  final DateTime queuedAt;
  final int attempts;

  /// Message from the last server rejection. Null while the request is waiting
  /// to be sent. Network failures do not set it.
  final String? lastError;

  String get offlineId => request.offlineId ?? '';
  bool get isRejected => lastError != null;

  OfflineQueueEntry copyWith({int? attempts, String? lastError}) => OfflineQueueEntry(
        request: request,
        queuedAt: queuedAt,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
      );

  Map<String, dynamic> toJson() => {
        'request': request.toJson(),
        'queuedAt': queuedAt.toIso8601String(),
        'attempts': attempts,
        if (lastError != null) 'lastError': lastError,
      };

  factory OfflineQueueEntry.fromJson(Map<String, dynamic> j) => OfflineQueueEntry(
        request: CreateOrder.fromJson(asMap(j['request'])),
        queuedAt: DateTime.tryParse(readString(j, 'queuedAt')) ?? DateTime.fromMillisecondsSinceEpoch(0),
        attempts: readInt(j, 'attempts'),
        lastError: readStringOrNull(j, 'lastError'),
      );
}

/// Outcome of one [OfflineOrderQueue.flush].
class FlushResult {
  const FlushResult({this.synced = const [], this.rejected = 0, this.stillPending = 0});

  /// Orders the server created from queued requests, in send order.
  final List<OrderView> synced;

  /// Requests the server refused (for example, the table was taken). They stay
  /// in the queue with `lastError` until the user discards them.
  final int rejected;

  /// Requests left waiting because the connection is still down.
  final int stillPending;
}

/// Store-and-forward for `POST /orders` while the tablet is offline.
///
/// Each request gets an `offlineId`, so a retry after a lost response returns
/// the order the server already made (idempotent on `offlineId`). Payments are
/// never queued (PLAN 1.7).
class OfflineOrderQueue {
  OfflineOrderQueue({
    required OrderCreationGateway gateway,
    required Box<String> box,
    DateTime Function()? clock,
  })  : _gateway = gateway,
        _box = box,
        _clock = clock ?? DateTime.now;

  static const boxName = 'offline_orders';
  static const defaultFlushInterval = Duration(seconds: 30);

  final OrderCreationGateway _gateway;
  final Box<String> _box;
  final DateTime Function() _clock;
  final _changes = StreamController<int>.broadcast();
  final _synced = StreamController<(String, OrderView)>.broadcast();
  Timer? _timer;
  Future<FlushResult>? _flushing;

  /// Emits the pending count after every enqueue, sync and discard.
  Stream<int> get changes => _changes.stream;

  /// Emits `(offlineId, order)` each time a queued request becomes an order.
  Stream<(String, OrderView)> get synced => _synced.stream;

  /// Number of requests stored, including rejected ones.
  int get pendingCount => _box.length;

  /// Requests the server has refused.
  int get rejectedCount => entries.where((e) => e.isRejected).length;

  /// All stored entries, oldest first. Malformed rows are skipped.
  List<OfflineQueueEntry> get entries {
    final out = <OfflineQueueEntry>[];
    for (final raw in _box.values) {
      try {
        out.add(OfflineQueueEntry.fromJson(asMap(jsonDecode(raw))));
      } catch (_) {
        // Skip a row that cannot be read. It is not worth blocking the queue.
      }
    }
    out.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return out;
  }

  /// Stores [order] and returns its `offlineId`.
  Future<String> enqueue(CreateOrder order) async {
    final id = order.offlineId ?? generateOfflineId();
    final entry = OfflineQueueEntry(request: order.withOfflineId(id), queuedAt: _clock());
    await _box.put(id, jsonEncode(entry.toJson()));
    _emit();
    return id;
  }

  /// Drops a rejected request the user has decided not to send.
  Future<void> discard(String offlineId) async {
    await _box.delete(offlineId);
    _emit();
  }

  /// Sends queued requests in order. Only one flush runs at a time; a second
  /// call while one is running gets the same future.
  Future<FlushResult> flush() {
    final running = _flushing;
    if (running != null) return running;
    final future = _runFlush().whenComplete(() => _flushing = null);
    _flushing = future;
    return future;
  }

  Future<FlushResult> _runFlush() async {
    final synced = <OrderView>[];
    var rejected = 0;
    var waiting = 0;
    final queue = entries;
    for (var i = 0; i < queue.length; i++) {
      final entry = queue[i];
      try {
        final order = await _gateway.createOrder(entry.request);
        await _box.delete(entry.offlineId);
        synced.add(order);
        _synced.add((entry.offlineId, order));
        _emit();
      } on ApiError catch (e) {
        if (e.isNetwork) {
          // Still offline. Keep this and everything after it for the next try.
          waiting = queue.length - i;
          break;
        }
        rejected++;
        await _box.put(
          entry.offlineId,
          jsonEncode(entry.copyWith(attempts: entry.attempts + 1, lastError: e.message).toJson()),
        );
      } catch (_) {
        waiting = queue.length - i;
        break;
      }
    }
    _emit();
    return FlushResult(synced: synced, rejected: rejected, stillPending: waiting);
  }

  /// Starts a periodic [flush]. Replaces any timer already running.
  void startAutoFlush({Duration every = defaultFlushInterval}) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) {
      if (pendingCount > 0) flush();
    });
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(pendingCount);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _changes.close();
    _synced.close();
  }
}

/// Opens the Hive box once and keeps the queue alive for the session. The
/// queue flushes every 30 s. Open the box after `SessionStore.init()` has run.
final offlineOrderQueueProvider = FutureProvider<OfflineOrderQueue>((ref) async {
  final box = Hive.isBoxOpen(OfflineOrderQueue.boxName)
      ? Hive.box<String>(OfflineOrderQueue.boxName)
      : await Hive.openBox<String>(OfflineOrderQueue.boxName);
  final queue = OfflineOrderQueue(gateway: ref.watch(posRepositoryProvider), box: box);
  queue.startAutoFlush();
  ref.onDispose(queue.dispose);
  return queue;
});

/// Stored request count, for "Offline — 2 orders will sync".
final offlinePendingCountProvider = StreamProvider<int>((ref) async* {
  final queue = await ref.watch(offlineOrderQueueProvider.future);
  yield queue.pendingCount;
  yield* queue.changes;
});
