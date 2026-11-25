import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:pos_billing/core/auth/api_error.dart';
import 'package:pos_billing/features/pos/data/offline_queue.dart';
import 'package:pos_billing/features/pos/data/pos_models.dart';
import 'package:pos_billing/features/pos/data/pos_repository.dart';

/// Gateway that answers from a script. Each entry is an OrderView (success) or an
/// ApiError (failure). When the script runs out, every call succeeds.
class FakeGateway implements OrderCreationGateway {
  FakeGateway([List<Object>? script]) : _script = [...?script];

  final List<Object> _script;
  final List<CreateOrder> calls = [];

  @override
  Future<OrderView> createOrder(CreateOrder body) async {
    calls.add(body);
    final next = _script.isEmpty ? null : _script.removeAt(0);
    if (next is ApiError) throw next;
    if (next is OrderView) return next;
    return OrderView.fromJson({
      'id': 'server-${body.offlineId}',
      'orderNumber': 'A-${calls.length}',
      'type': body.type,
      'status': 'OPEN',
      'totals': <String, dynamic>{},
    });
  }
}

void main() {
  late Directory dir;
  late Box<String> box;
  DateTime tick = DateTime.utc(2026, 11, 25, 10);

  DateTime clock() {
    tick = tick.add(const Duration(seconds: 1));
    return tick;
  }

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('pos_offline_test');
    Hive.init(dir.path);
  });

  setUp(() async {
    box = await Hive.openBox<String>('offline_orders_test');
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

  const order = CreateOrder(type: OrderTypes.dineIn, tableId: 't4', covers: 4);

  test('generateOfflineId makes a version 4 UUID', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    for (var i = 0; i < 50; i++) {
      expect(pattern.hasMatch(generateOfflineId()), isTrue);
    }
    expect(generateOfflineId(), isNot(generateOfflineId()));
  });

  test('enqueue stores the request with its offlineId', () async {
    final queue = OfflineOrderQueue(gateway: FakeGateway(), box: box, clock: clock);
    final id = await queue.enqueue(order);
    expect(queue.pendingCount, 1);
    final entry = queue.entries.single;
    expect(entry.offlineId, id);
    expect(entry.request.tableId, 't4');
    expect(entry.request.covers, 4);
    expect(entry.isRejected, isFalse);
    queue.dispose();
  });

  test('entries survive a fresh queue on the same box', () async {
    final first = OfflineOrderQueue(gateway: FakeGateway(), box: box, clock: clock);
    await first.enqueue(order);
    first.dispose();

    final second = OfflineOrderQueue(gateway: FakeGateway(), box: box, clock: clock);
    expect(second.pendingCount, 1);
    expect(second.entries.single.request.type, OrderTypes.dineIn);
    second.dispose();
  });

  test('flush sends queued orders oldest first and removes them on success', () async {
    final gateway = FakeGateway();
    final queue = OfflineOrderQueue(gateway: gateway, box: box, clock: clock);
    final first = await queue.enqueue(order);
    final second = await queue.enqueue(const CreateOrder(type: OrderTypes.takeaway));

    final result = await queue.flush();

    expect(result.synced.length, 2);
    expect(result.rejected, 0);
    expect(result.stillPending, 0);
    expect(gateway.calls.map((c) => c.offlineId), [first, second]);
    expect(queue.pendingCount, 0);
    queue.dispose();
  });

  test('flush keeps the offlineId so a retry is idempotent', () async {
    final gateway = FakeGateway([
      ApiError(status: 0, message: "Couldn't reach the server."),
    ]);
    final queue = OfflineOrderQueue(gateway: gateway, box: box, clock: clock);
    final id = await queue.enqueue(order);

    await queue.flush(); // fails offline, stays queued
    await queue.flush(); // succeeds

    expect(gateway.calls.map((c) => c.offlineId).toSet(), {id});
    expect(queue.pendingCount, 0);
    queue.dispose();
  });

  test('a network failure stops the flush and keeps the rest waiting', () async {
    final gateway = FakeGateway([
      ApiError(status: 0, message: 'offline'),
    ]);
    final queue = OfflineOrderQueue(gateway: gateway, box: box, clock: clock);
    await queue.enqueue(order);
    await queue.enqueue(order);

    final result = await queue.flush();

    expect(result.synced, isEmpty);
    expect(result.stillPending, 2);
    expect(gateway.calls.length, 1, reason: 'stops after the first network error');
    expect(queue.pendingCount, 2);
    expect(queue.rejectedCount, 0);
    queue.dispose();
  });

  test('a server refusal is kept with its message until discarded', () async {
    final gateway = FakeGateway([
      ApiError(status: 409, code: 'TABLE_OCCUPIED', message: 'Table R4 is taken'),
    ]);
    final queue = OfflineOrderQueue(gateway: gateway, box: box, clock: clock);
    final id = await queue.enqueue(order);

    final result = await queue.flush();

    expect(result.rejected, 1);
    expect(result.stillPending, 0);
    expect(queue.pendingCount, 1);
    expect(queue.rejectedCount, 1);
    expect(queue.entries.single.lastError, 'Table R4 is taken');
    expect(queue.entries.single.attempts, 1);

    await queue.discard(id);
    expect(queue.pendingCount, 0);
    queue.dispose();
  });

  test('synced emits the offlineId and the server order', () async {
    final queue = OfflineOrderQueue(gateway: FakeGateway(), box: box, clock: clock);
    final id = await queue.enqueue(order);
    final events = queue.synced.take(1).toList();

    await queue.flush();
    final event = (await events).single;

    expect(event.$1, id);
    expect(event.$2.id, 'server-$id');
    queue.dispose();
  });

  test('changes emits the pending count after enqueue and sync', () async {
    final queue = OfflineOrderQueue(gateway: FakeGateway(), box: box, clock: clock);
    final counts = queue.changes.take(2).toList();

    await queue.enqueue(order);
    await queue.flush();

    expect(await counts, [1, 0]);
    queue.dispose();
  });

  test('concurrent flush calls share one run', () async {
    final gateway = FakeGateway();
    final queue = OfflineOrderQueue(gateway: gateway, box: box, clock: clock);
    await queue.enqueue(order);

    final a = queue.flush();
    final b = queue.flush();
    await Future.wait([a, b]);

    expect(gateway.calls.length, 1);
    queue.dispose();
  });
}
