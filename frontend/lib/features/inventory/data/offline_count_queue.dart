import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../core/auth/api_error.dart';
import 'inventory_models.dart';
import 'inventory_repository.dart';
import 'json_read.dart';

/// The one call the count queue needs: `PUT /stock/counts/:id/lines`.
/// [InventoryRepository] implements it; tests use a fake.
abstract interface class CountLineGateway {
  Future<Object?> saveCountLines(String countId, List<CountLineInput> lines);
}

/// One saved count line on this phone, waiting to reach the server.
class PendingCountLine {
  const PendingCountLine({
    required this.countId,
    required this.stockItemId,
    this.countedQty,
    this.note,
    this.confirmedOutlier = false,
    required this.countedAt,
  });

  final String countId;
  final String stockItemId;

  /// Wire quantity (3 dp), or null when the line was cleared.
  final String? countedQty;
  final String? note;
  final bool confirmedOutlier;
  final DateTime countedAt;

  String get key => OfflineCountQueue.keyFor(countId, stockItemId);

  CountLineInput toInput() => CountLineInput(
        stockItemId: stockItemId,
        countedQty: countedQty,
        note: note,
        confirmedOutlier: confirmedOutlier,
        countedAt: countedAt,
      );

  Map<String, dynamic> toJson() => {
        'countId': countId,
        'stockItemId': stockItemId,
        'countedQty': countedQty,
        'note': note,
        'confirmedOutlier': confirmedOutlier,
        'countedAt': countedAt.toIso8601String(),
      };

  factory PendingCountLine.fromJson(Map<String, dynamic> j) => PendingCountLine(
        countId: jsonStr(j, 'countId'),
        stockItemId: jsonStr(j, 'stockItemId'),
        countedQty: jsonStrOrNull(j, 'countedQty'),
        note: jsonStrOrNull(j, 'note'),
        confirmedOutlier: jsonBool(j, 'confirmedOutlier'),
        countedAt: DateTime.tryParse(jsonStr(j, 'countedAt')) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Outcome of one [OfflineCountQueue.flush].
class CountFlushResult {
  const CountFlushResult({this.synced = 0, this.failed = 0, this.offline = false});

  /// Lines the server accepted and that were removed from the phone.
  final int synced;

  /// Lines the server refused (for example, the count was already posted).
  /// They stay on the phone.
  final int failed;

  /// True when the connection was down; the rest waits for the next flush.
  final bool offline;
}

/// Store-and-forward for stock count lines (PLAN 1.9, "offline count queue").
///
/// Every typed line is written to the Hive box `offline_stock_counts` first,
/// keyed by count and item, so a newer value replaces an older one. [flush]
/// sends one `PUT /stock/counts/:id/lines` per count, on screen open, every 30 s
/// and on reconnect. A line is removed only after the server accepts it, and
/// only if the phone has not saved a newer value for it in the meantime.
class OfflineCountQueue {
  OfflineCountQueue({
    required CountLineGateway gateway,
    required Box<String> box,
    DateTime Function()? clock,
  })  : _gateway = gateway,
        _box = box,
        _clock = clock ?? DateTime.now;

  static const boxName = 'offline_stock_counts';
  static const defaultFlushInterval = Duration(seconds: 30);

  static String keyFor(String countId, String stockItemId) => '$countId::$stockItemId';

  final CountLineGateway _gateway;
  final Box<String> _box;
  final DateTime Function() _clock;
  final _changes = StreamController<int>.broadcast();
  Timer? _timer;
  Future<CountFlushResult>? _flushing;

  /// Emits the pending line count after every save and sync.
  Stream<int> get changes => _changes.stream;

  /// Number of lines stored on this phone.
  int get pendingCount => _box.length;

  /// Stored lines for one count, oldest first. Malformed rows are skipped.
  List<PendingCountLine> linesFor(String countId) {
    final out = [
      for (final e in _entries()) if (e.$2.countId == countId) e.$2,
    ];
    out.sort((a, b) => a.countedAt.compareTo(b.countedAt));
    return out;
  }

  /// Stores one line, replacing any earlier value for the same item.
  Future<void> save({
    required String countId,
    required String stockItemId,
    String? countedQty,
    String? note,
    bool confirmedOutlier = false,
  }) async {
    final line = PendingCountLine(
      countId: countId,
      stockItemId: stockItemId,
      countedQty: countedQty,
      note: note,
      confirmedOutlier: confirmedOutlier,
      countedAt: _clock(),
    );
    await _box.put(line.key, jsonEncode(line.toJson()));
    _emit();
  }

  /// Sends stored lines. One flush runs at a time; a second call while one is
  /// running gets the same future. Pass [countId] to flush a single count.
  Future<CountFlushResult> flush({String? countId}) {
    final running = _flushing;
    if (running != null) return running;
    final future = _runFlush(countId).whenComplete(() => _flushing = null);
    _flushing = future;
    return future;
  }

  Future<CountFlushResult> _runFlush(String? onlyCount) async {
    var synced = 0;
    var failed = 0;

    // Group the stored rows by count, keeping the raw text of each row so a
    // newer save made during the request is not deleted by mistake.
    final byCount = <String, List<(String, String, PendingCountLine)>>{};
    for (final (key, raw, line) in _rawEntries()) {
      if (onlyCount != null && line.countId != onlyCount) continue;
      byCount.putIfAbsent(line.countId, () => []).add((key, raw, line));
    }

    for (final group in byCount.entries) {
      final rows = group.value;
      try {
        await _gateway.saveCountLines(group.key, [for (final r in rows) r.$3.toInput()]);
        for (final (key, raw, _) in rows) {
          if (_box.get(key) == raw) await _box.delete(key);
        }
        synced += rows.length;
        _emit();
      } on ApiError catch (e) {
        if (e.isNetwork) {
          return CountFlushResult(synced: synced, failed: failed, offline: true);
        }
        failed += rows.length;
      } catch (_) {
        return CountFlushResult(synced: synced, failed: failed, offline: true);
      }
    }
    _emit();
    return CountFlushResult(synced: synced, failed: failed);
  }

  /// Starts a periodic [flush]. Replaces any timer already running.
  void startAutoFlush({Duration every = defaultFlushInterval}) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) {
      if (pendingCount > 0) flush();
    });
  }

  /// (storage key, decoded line) for every readable row.
  Iterable<(String, PendingCountLine)> _entries() =>
      _rawEntries().map((e) => (e.$1, e.$3));

  /// (storage key, raw row text, decoded line) for every readable row.
  Iterable<(String, String, PendingCountLine)> _rawEntries() sync* {
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw == null) continue;
      try {
        yield (key.toString(), raw, PendingCountLine.fromJson(jsonMap(jsonDecode(raw))));
      } catch (_) {
        // A row that cannot be read is skipped; it must not block the queue.
      }
    }
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(pendingCount);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _changes.close();
  }
}

/// Opens the Hive box once and keeps the queue alive for the session. Open the
/// box after `SessionStore.init()` has run.
final offlineCountQueueProvider = FutureProvider<OfflineCountQueue>((ref) async {
  final box = Hive.isBoxOpen(OfflineCountQueue.boxName)
      ? Hive.box<String>(OfflineCountQueue.boxName)
      : await Hive.openBox<String>(OfflineCountQueue.boxName);
  final queue = OfflineCountQueue(gateway: ref.watch(inventoryRepositoryProvider), box: box);
  queue.startAutoFlush();
  ref.onDispose(queue.dispose);
  return queue;
});

/// Lines waiting on this phone, for the "18 counts are saved" banner.
final offlineCountPendingProvider = StreamProvider<int>((ref) async* {
  final queue = await ref.watch(offlineCountQueueProvider.future);
  yield queue.pendingCount;
  yield* queue.changes;
});
