import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

final floorRepositoryProvider = Provider<FloorRepository>(
  (ref) => FloorRepository(ref.watch(dioProvider)),
);

/// Table statuses sent by the API (PLAN 1.4, `GET /tables`).
abstract class TableStatus {
  static const free = 'FREE';
  static const occupied = 'OCCUPIED';
  static const billPrinted = 'BILL_PRINTED';
  static const cleaning = 'CLEANING';
  static const reserved = 'RESERVED';
}

class FloorArea {
  const FloorArea({required this.id, required this.name, this.sortOrder = 0});

  final String id;
  final String name;
  final int sortOrder;

  factory FloorArea.fromJson(Map j) => FloorArea(
        id: j['id'] as String,
        name: j['name'] as String,
        sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

/// The open order shown on a table in the live view.
class FloorOrder {
  const FloorOrder({
    required this.id,
    required this.orderNumber,
    required this.covers,
    required this.grandTotal,
    this.openedAt,
    this.waiterName,
  });

  final String id;
  final String orderNumber;
  final int covers;
  final String grandTotal;
  final DateTime? openedAt;
  final String? waiterName;

  factory FloorOrder.fromJson(Map j) => FloorOrder(
        id: j['id'] as String,
        orderNumber: j['orderNumber'] as String? ?? '',
        covers: (j['covers'] as num?)?.toInt() ?? 0,
        grandTotal: j['grandTotal']?.toString() ?? '0.00',
        openedAt: j['openedAt'] == null ? null : DateTime.tryParse(j['openedAt'].toString()),
        waiterName: j['waiterName'] as String?,
      );
}

class FloorTable {
  const FloorTable({
    required this.id,
    required this.name,
    required this.areaId,
    required this.seats,
    required this.shape,
    required this.posX,
    required this.posY,
    required this.status,
    this.mergedIntoId,
    this.order,
  });

  final String id;
  final String name;
  final String areaId;
  final int seats;
  final String shape;

  /// Grid cell of the top-left corner on the floor plan.
  final int posX;
  final int posY;
  final String status;
  final String? mergedIntoId;
  final FloorOrder? order;

  bool get isMerged => mergedIntoId != null;

  factory FloorTable.fromJson(Map j) {
    final order = j['order'];
    return FloorTable(
      id: j['id'] as String,
      name: j['name'] as String,
      areaId: j['areaId'] as String,
      seats: (j['seats'] as num?)?.toInt() ?? 1,
      shape: j['shape'] as String? ?? 'SQUARE',
      posX: (j['posX'] as num?)?.toInt() ?? 0,
      posY: (j['posY'] as num?)?.toInt() ?? 0,
      status: j['status'] as String? ?? TableStatus.free,
      mergedIntoId: j['mergedIntoId'] as String?,
      order: order is Map ? FloorOrder.fromJson(order) : null,
    );
  }
}

class FloorRepository {
  FloorRepository(this._dio);
  final Dio _dio;

  static List<Map> _rows(dynamic body) {
    final raw = body is Map ? body['data'] : body;
    return (raw as List).cast<Map>();
  }

  Future<List<FloorArea>> areas() async {
    final res = await _dio.get('/areas');
    return _rows(res.data).map(FloorArea.fromJson).toList();
  }

  /// Live view: every table with its open order, if any.
  Future<List<FloorTable>> tables() async {
    final res = await _dio.get('/tables');
    return _rows(res.data).map(FloorTable.fromJson).toList();
  }

  Future<void> setTableStatus(String id, String status) =>
      _dio.patch('/tables/$id/status', data: {'status': status});

  Future<FloorArea> createArea(String name) async {
    final res = await _dio.post('/areas', data: {'name': name});
    return FloorArea.fromJson(res.data as Map);
  }

  Future<void> renameArea(String id, String name) => _dio.patch('/areas/$id', data: {'name': name});

  Future<void> deleteArea(String id) => _dio.delete('/areas/$id');

  Future<void> createTable(Map<String, dynamic> body) => _dio.post('/tables', data: body);

  /// Used for table edits and for saving a dragged position (posX, posY).
  Future<void> updateTable(String id, Map<String, dynamic> body) =>
      _dio.patch('/tables/$id', data: body);

  Future<void> deleteTable(String id) => _dio.delete('/tables/$id');
}

final floorAreasProvider = FutureProvider<List<FloorArea>>(
  (ref) => ref.watch(floorRepositoryProvider).areas(),
);

final floorTablesProvider = FutureProvider<List<FloorTable>>(
  (ref) => ref.watch(floorRepositoryProvider).tables(),
);
