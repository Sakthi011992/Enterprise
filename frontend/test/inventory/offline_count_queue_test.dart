import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pos_billing/core/auth/api_error.dart';
import 'package:pos_billing/features/inventory/data/inventory_models.dart';
import 'package:pos_billing/features/inventory/data/offline_count_queue.dart';

/// Gateway that records every PUT. Each scripted entry is an [ApiError] (thrown)
/// or anything else (success). When the script runs out, calls succeed.
class FakeCountGateway implements CountLineGateway {
  final List<(String, List<CountLineInput>)> calls = [];
  final List<Object> script = [];

  /// Runs during a call, before the answer. Used to simulate a newer save.
  Future<void> Function()? during;

  @override
  Future<Object?> saveCountLines(String countId, List<CountLineInput> lines) async {
    calls.add((countId, lines));
    if (during != null) await during!();
    final next = script.isEmpty ? null : script.removeAt(0);
    if (next is ApiError) throw next;
    return null;
  }
}

void main() {
  late Directory dir;
  late Box<String> box;
  DateTime tick = DateTime.utc(2026, 11, 25, 9);

  DateTime clock() {
    tick = tick.add(const Duration(seconds: 1));
    return tick;
  }

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('stock_count_queue_test');
    Hive.init(dir.path);
  });

  setUp(() async {
    box = await Hive.openBox<String>('offline_stock_counts_test');
    await box.clear();
  });

  tearDown(() async {
    await box.clear();
    await box.close();
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  OfflineCountQueue queueWith(FakeCountGateway gateway) =>
      OfflineCountQueue(gateway: gateway, box: box, clock: clock);

  test('a saved line stays on the phone and replaces the earlier value for the same item', () async {
    final queue = queueWith(FakeCountGateway());
    await queue.save(countId: 'C1', stockItemId: 'A', countedQty: '3000.000');
    await queue.save(countId: 'C1', stockItemId: 'A', countedQty: '6410.000');
    await queue.save(countId: 'C1', stockItemId: 'B', countedQty: null);

    expect(queue.pendingCount, 2);
    final lines = queue.linesFor('C1');
    expect(lines.map((l) => l.stockItemId), ['A', 'B']);
    expect(lines.first.countedQty, '6410.000');
    expect(lines.last.countedQty, isNull);
  });

  test('lines of other counts are kept apart', () async {
    final queue = queueWith(FakeCountGateway());
    await queue.save(countId: 'C1', stockItemId: 'A', countedQty: '1.000');
    await queue.save(countId: 'C2', stockItemId: 'A', countedQty: '2.000');
    expect(queue.linesFor('C1').single.countedQty, '1.000');
    expect(queue.linesFor('C2').single.countedQty, '2.000');
  });

  test('flush sends one PUT per count with every line, then clears them', () async {
    final gateway = FakeCountGateway();
    final queue = queueWith(gateway);
    await queue.save(countId: 'C1', stockItemId: 'A', countedQty: '1.000');
    await queue.save(countId: 'C1', stockItemId: 'B', countedQty: '2.000');
    await queue.save(countId: 'C2', stockItemId: 'A', countedQty: '3.000');

    final result = await queue.flush();

    expect(gateway.calls.length, 2);
    final c1 = gateway.calls.firstWhere((c) => c.$1 == 'C1').$2;
    expect(c1.map((l) => l.stockItemId), ['A', 'B']);
    expect(c1.map((l) => l.countedQty), ['1.000', '2.000']);
    expect(result.synced, 3);
    expect(result.failed, 0);
    expect(result.offline, isFalse);
    expect(queue.pendingCount, 0);
  });

  test('flush of one count leaves the others alone', () async {
    final gateway = FakeCountGateway();
    final queue = queueWith(gateway);
    await queue.save(countId: 'C1', stockItemId: 'A', countedQty: '1.000');
    await queue.save(countId: 'C2', stockItemId: 'A', countedQty: '2.000');

    await queue.flush(countId: 'C2');

    expect(gateway.calls.map((c) => c.$1), ['C2']);
    expect(queue.linesFor('C1').length, 1);
    expect(queue.linesFor('C2'), isEmpty);
  });

  test('when the connection is down, lines are kept and the result says offline', () async {
    final gateway = FakeCountGateway()..script.add(const ApiError(status: 0, message: 'offline'));
    final queue = queueWith(gateway);
    await queue.save(countId: 'C1', stockItemId: 'A', countedQty: '1.000');
    await queue.save(countId: 'C1', stockItemId: 'B', countedQty: '2.000');

    final result = await queue.flush();

    expect(result.offline, isTrue);
    expect(result.synced, 0);
    expect(queue.pendingCount, 2);
    expect(queue.linesFor('C1').map((l) => l.countedQty), ['1.000', '2.000']);
  });

  test('when the server refuses a count, its lines stay and are counted as failed', () async {
    final gateway = FakeCountGateway()
      ..script.add(const ApiError(status: 409, code: 'COUNT_NOT_OPEN', message: 'not open'));
    final queue = queueWith(gateway);
    await queue.save(countId: 'C1', stockItemId: 'A', countedQty: '1.000');

    final result = await queue.flush();

    expect(result.offline, isFalse);
    expect(result.failed, 1);
    expect(queue.pendingCount, 1);
  });

  test('a newer save made while a flush is in flight is not deleted by that flush', () async {
    final gateway = FakeCountGateway();
    late OfflineCountQueue queue;
    gateway.during = () async {
      await queue.save(countId: 'C1', stockItemId: 'A', countedQty: '5.000');
    };
    queue = queueWith(gateway);
    await queue.save(countId: 'C1', stockItemId: 'A', countedQty: '3.000');

    await queue.flush();

    expect(queue.linesFor('C1').single.countedQty, '5.000');
  });

  test('a second flush while one runs returns the same work', () async {
    final gateway = FakeCountGateway();
    final queue = queueWith(gateway);
    await queue.save(countId: 'C1', stockItemId: 'A', countedQty: '1.000');

    final first = queue.flush();
    final second = queue.flush();
    await Future.wait([first, second]);

    expect(gateway.calls.length, 1);
  });

  test('a row that cannot be read is skipped and does not block the others', () async {
    final queue = queueWith(FakeCountGateway());
    await box.put('broken', '{not json');
    await queue.save(countId: 'C1', stockItemId: 'A', countedQty: '1.000');
    expect(queue.linesFor('C1').length, 1);
  });
}
