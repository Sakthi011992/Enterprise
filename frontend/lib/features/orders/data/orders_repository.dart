import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.watch(dioProvider)),
);

/// Filters for the Orders list. [days] counts back from today (1 = today).
typedef OrderQuery = ({String? status, String? type, String? payment, String search, int days});

String _money(Object? v) => v?.toString() ?? '0.00';

/// One row of the Orders list.
class OrderRow {
  const OrderRow({
    required this.id,
    required this.orderNumber,
    required this.type,
    required this.status,
    required this.grandTotal,
    this.tableName,
    this.invoiceNumber,
    this.paidAt,
  });

  final String id;
  final String orderNumber;
  final String type;
  final String status;
  final String grandTotal;
  final String? tableName;
  final String? invoiceNumber;
  final DateTime? paidAt;

  factory OrderRow.fromJson(Map j) {
    final totals = j['totals'];
    final table = j['table'];
    return OrderRow(
      id: j['id'] as String,
      orderNumber: j['orderNumber'] as String? ?? '',
      type: j['type'] as String? ?? '',
      status: j['status'] as String? ?? '',
      grandTotal: _money(totals is Map ? totals['grandTotal'] : j['grandTotal']),
      tableName: table is Map ? table['name'] as String? : null,
      invoiceNumber: j['invoiceNumber'] as String?,
      paidAt: j['paidAt'] == null ? null : DateTime.tryParse(j['paidAt'].toString()),
    );
  }
}

class OrderDetailLine {
  const OrderDetailLine({required this.name, required this.quantity, required this.total, this.seat});

  final String name;
  final int quantity;
  final String total;
  final int? seat;

  factory OrderDetailLine.fromJson(Map j) => OrderDetailLine(
        name: j['name'] as String? ?? '',
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        total: _money(j['total']),
        seat: (j['seat'] as num?)?.toInt(),
      );
}

class OrderDetailPayment {
  const OrderDetailPayment({
    required this.id,
    required this.method,
    required this.amount,
    required this.status,
    this.changeGiven,
    this.createdAt,
  });

  final String id;
  final String method;
  final String amount;
  final String status;
  final String? changeGiven;
  final DateTime? createdAt;

  factory OrderDetailPayment.fromJson(Map j) => OrderDetailPayment(
        id: j['id'] as String,
        method: j['method'] as String? ?? '',
        amount: _money(j['amount']),
        status: j['status'] as String? ?? '',
        changeGiven: j['changeGiven'] == null ? null : _money(j['changeGiven']),
        createdAt: j['createdAt'] == null ? null : DateTime.tryParse(j['createdAt'].toString()),
      );
}

/// Full order as shown in the Orders drawer (`GET /orders/:id`).
class OrderDetail {
  const OrderDetail({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.grandTotal,
    required this.paid,
    required this.due,
    required this.items,
    required this.payments,
    this.tableName,
    this.invoiceNumber,
  });

  final String id;
  final String orderNumber;
  final String status;
  final String grandTotal;
  final String paid;
  final String due;
  final String? tableName;
  final String? invoiceNumber;
  final List<OrderDetailLine> items;
  final List<OrderDetailPayment> payments;

  /// True when some money has been taken; such an order can be refunded, not voided.
  bool get hasPayments => payments.any((p) => p.status != 'REFUNDED') && paid != '0.00';

  factory OrderDetail.fromJson(Map j) {
    final totals = j['totals'] is Map ? j['totals'] as Map : const <dynamic, dynamic>{};
    final table = j['table'];
    return OrderDetail(
      id: j['id'] as String,
      orderNumber: j['orderNumber'] as String? ?? '',
      status: j['status'] as String? ?? '',
      grandTotal: _money(totals['grandTotal'] ?? j['grandTotal']),
      paid: _money(totals['paid'] ?? '0.00'),
      due: _money(totals['due'] ?? '0.00'),
      tableName: table is Map ? table['name'] as String? : null,
      invoiceNumber: j['invoiceNumber'] as String?,
      items: [for (final i in (j['items'] as List? ?? const [])) OrderDetailLine.fromJson(i as Map)],
      payments: [
        for (final p in (j['payments'] as List? ?? const [])) OrderDetailPayment.fromJson(p as Map),
      ],
    );
  }
}

class OrdersRepository {
  OrdersRepository(this._dio);
  final Dio _dio;

  // Legacy billing calls. Used by the old billing screen until P2-D removes it.
  Future<Map> create(List<Map> items) async {
    final res = await _dio.post('/orders', data: {'items': items});
    return res.data as Map;
  }

  Future<Map> pay({required String orderId, required double amount, required String method}) async {
    final res = await _dio.post('/payments', data: {
      'orderId': orderId,
      'amount': amount,
      'paymentMethod': method,
    });
    return res.data as Map;
  }

  Future<List<Map>> history({String? search}) async {
    final res = await _dio.get('/orders', queryParameters: {
      if (search != null && search.isNotEmpty) 'search': search,
      'limit': 50,
    });
    return (res.data['data'] as List).cast<Map>();
  }

  Future<Map> detail(String id) async {
    final res = await _dio.get('/orders/$id');
    return res.data as Map;
  }

  /// URLs for printing (open in browser / external viewer).
  String thermalUrl(String orderId) => '${AppConfig.apiBaseUrl}/invoice/$orderId/thermal';
  String pdfUrl(String orderId) => '${AppConfig.apiBaseUrl}/invoice/$orderId/pdf';

  // Orders screen (PLAN 1.4 order endpoints)

  /// Orders of the outlet for the filters in [query].
  Future<List<OrderRow>> search(OrderQuery query) async {
    final today = DateTime.now();
    final from = today.subtract(Duration(days: query.days - 1));
    final fmt = DateFormat('yyyy-MM-dd');
    final res = await _dio.get('/orders', queryParameters: {
      if (query.status != null) 'status': query.status,
      if (query.type != null) 'type': query.type,
      if (query.payment != null) 'payment': query.payment,
      if (query.search.trim().isNotEmpty) 'search': query.search.trim(),
      'from': fmt.format(from),
      'to': fmt.format(today),
      'limit': 100,
    });
    final raw = res.data is Map ? res.data['data'] : res.data;
    return (raw as List).cast<Map>().map(OrderRow.fromJson).toList();
  }

  Future<OrderDetail> orderDetail(String id) async {
    final res = await _dio.get('/orders/$id');
    return OrderDetail.fromJson(res.data as Map);
  }

  Future<void> reprintBill(String id, {int copies = 1}) =>
      _dio.post('/orders/$id/bill', data: {'copies': copies});

  /// Whole-order void. Send [approvalId] after a manager approved it.
  Future<void> voidOrder(String id, {required String reason, String? approvalId}) =>
      _dio.post('/orders/$id/void', data: {
        'reason': reason,
        if (approvalId != null) 'approvalId': approvalId,
      });

  Future<void> refund(
    String id, {
    required String amount,
    required String reason,
    String? paymentId,
    String? approvalId,
  }) =>
      _dio.post('/orders/$id/refund', data: {
        'amount': amount,
        'reason': reason,
        if (paymentId != null) 'paymentId': paymentId,
        if (approvalId != null) 'approvalId': approvalId,
      });
}

final ordersSearchProvider = FutureProvider.family<List<OrderRow>, OrderQuery>(
  (ref, query) => ref.watch(ordersRepositoryProvider).search(query),
);

final orderDetailProvider = FutureProvider.family<OrderDetail, String>(
  (ref, id) => ref.watch(ordersRepositoryProvider).orderDetail(id),
);
