import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/providers.dart';
import 'pos_models.dart';

final posRepositoryProvider = Provider<PosRepository>(
  (ref) => PosRepository(ref.watch(dioProvider)),
);

/// The one call the offline queue needs. [PosRepository] implements it, and
/// tests implement it with a fake.
abstract interface class OrderCreationGateway {
  Future<OrderView> createOrder(CreateOrder body);
}

/// Every POS, pay, approval, table and report call (PLAN 1.4). Dio errors are
/// rethrown as [ApiError] with the server `code` and `details`.
///
/// Mutations that the plan does not describe a response for return the
/// updated [OrderView]. That is an assumption for P2-C to confirm.
class PosRepository implements OrderCreationGateway {
  PosRepository(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  static OrderView _order(Response<dynamic> r) => OrderView.fromJson(asMap(r.data));

  static Map<String, dynamic> _body(Map<String, dynamic> raw) {
    raw.removeWhere((_, v) => v == null);
    return raw;
  }

  // --- menu (P2-B endpoint, used by the POS screen) -------------------------

  /// GET /menu/pos
  Future<PosMenu> menu() => _guard(() async {
        final r = await _dio.get<dynamic>('/menu/pos');
        return PosMenu.fromJson(asMap(r.data));
      });

  // --- tables ---------------------------------------------------------------

  /// GET /tables (live view with the open order per table)
  Future<List<TableView>> tables() => _guard(() async {
        final r = await _dio.get<dynamic>('/tables');
        return [for (final t in asMaps(r.data)) TableView.fromJson(t)];
      });

  // --- orders ---------------------------------------------------------------

  /// POST /orders. Idempotent on `offlineId`.
  @override
  Future<OrderView> createOrder(CreateOrder body) => _guard(() async {
        final r = await _dio.post<dynamic>('/orders', data: body.toJson());
        return _order(r);
      });

  /// GET /orders/open
  Future<List<OpenOrderSummary>> openOrders() => _guard(() async {
        final r = await _dio.get<dynamic>('/orders/open');
        return [for (final o in asMaps(r.data)) OpenOrderSummary.fromJson(o)];
      });

  /// GET /orders/:id
  Future<OrderView> order(String id) => _guard(() async {
        final r = await _dio.get<dynamic>('/orders/$id');
        return _order(r);
      });

  /// POST /orders/:id/items
  Future<OrderView> addItems(String orderId, List<AddItem> items) => _guard(() async {
        final r = await _dio.post<dynamic>(
          '/orders/$orderId/items',
          data: {'items': [for (final i in items) i.toJson()]},
        );
        return _order(r);
      });

  /// PATCH /orders/:id/items/:itemId (only while the item is NEW).
  /// `modifierOptionIds` is sent as `modifiers`.
  Future<OrderView> updateItem(
    String orderId,
    String itemId, {
    int? quantity,
    int? seat,
    String? note,
    List<String>? modifierOptionIds,
  }) =>
      _guard(() async {
        final r = await _dio.patch<dynamic>(
          '/orders/$orderId/items/$itemId',
          data: _body({
            'quantity': quantity,
            'seat': seat,
            'note': note,
            'modifiers': modifierOptionIds,
          }),
        );
        return _order(r);
      });

  /// DELETE /orders/:id/items/:itemId (NEW items only; no approval).
  Future<OrderView> removeItem(String orderId, String itemId) => _guard(() async {
        final r = await _dio.delete<dynamic>('/orders/$orderId/items/$itemId');
        return _order(r);
      });

  /// POST /orders/:id/send
  Future<SendResult> send(String orderId) => _guard(() async {
        final r = await _dio.post<dynamic>('/orders/$orderId/send');
        return SendResult.fromJson(asMap(r.data));
      });

  /// POST /orders/:id/hold or /unhold
  Future<OrderView> setHold(String orderId, {required bool held}) => _guard(() async {
        final r = await _dio.post<dynamic>('/orders/$orderId/${held ? 'hold' : 'unhold'}');
        return _order(r);
      });

  /// POST /orders/:id/discounts
  Future<OrderView> addDiscount(String orderId, DiscountInput input) => _guard(() async {
        final r = await _dio.post<dynamic>('/orders/$orderId/discounts', data: input.toJson());
        return _order(r);
      });

  /// DELETE /orders/:id/discounts/:discountId
  Future<OrderView> removeDiscount(String orderId, String discountId) => _guard(() async {
        final r = await _dio.delete<dynamic>('/orders/$orderId/discounts/$discountId');
        return _order(r);
      });

  /// POST /orders/:id/void-items
  Future<OrderView> voidItems(
    String orderId, {
    required List<String> itemIds,
    required String reason,
    String? approvalId,
  }) =>
      _guard(() async {
        final r = await _dio.post<dynamic>(
          '/orders/$orderId/void-items',
          data: _body({'itemIds': itemIds, 'reason': reason, 'approvalId': approvalId}),
        );
        return _order(r);
      });

  /// POST /orders/:id/void (whole order; only with no payments)
  Future<OrderView> voidOrder(String orderId, {required String reason, String? approvalId}) =>
      _guard(() async {
        final r = await _dio.post<dynamic>(
          '/orders/$orderId/void',
          data: _body({'reason': reason, 'approvalId': approvalId}),
        );
        return _order(r);
      });

  /// POST /orders/:id/move
  Future<OrderView> move(String orderId, {required String toTableId, bool force = false}) =>
      _guard(() async {
        final r = await _dio.post<dynamic>(
          '/orders/$orderId/move',
          data: {'toTableId': toTableId, if (force) 'force': true},
        );
        return _order(r);
      });

  /// POST /orders/:id/merge. Moves `fromOrderId` into this order.
  Future<OrderView> merge(String orderId, {required String fromOrderId}) => _guard(() async {
        final r = await _dio.post<dynamic>(
          '/orders/$orderId/merge',
          data: {'fromOrderId': fromOrderId},
        );
        return _order(r);
      });

  /// POST /orders/:id/transfer-items. Returns the source order.
  Future<OrderView> transferItems(
    String orderId, {
    required List<String> itemIds,
    String? toOrderId,
    String? toTableId,
  }) =>
      _guard(() async {
        final r = await _dio.post<dynamic>(
          '/orders/$orderId/transfer-items',
          data: _body({'itemIds': itemIds, 'toOrderId': toOrderId, 'toTableId': toTableId}),
        );
        return _order(r);
      });

  /// POST /orders/:id/bill
  Future<OrderView> bill(String orderId, {int? copies}) => _guard(() async {
        final r = await _dio.post<dynamic>(
          '/orders/$orderId/bill',
          data: _body({'copies': copies}),
        );
        return _order(r);
      });

  /// GET /orders/:id/split. [mode] is `EQUAL`, `SEAT` or `ITEMS`.
  /// [assign] is `itemId:seat` pairs for `ITEMS`, such as `a:1,b:2`.
  Future<SplitResult> split(
    String orderId, {
    required String mode,
    int? parts,
    List<({String itemId, int seat})> assign = const [],
  }) =>
      _guard(() async {
        final r = await _dio.get<dynamic>(
          '/orders/$orderId/split',
          queryParameters: _body({
            'mode': mode,
            'parts': parts,
            if (assign.isNotEmpty)
              'assign': assign.map((a) => '${a.itemId}:${a.seat}').join(','),
          }),
        );
        return SplitResult.fromJson(asMap(r.data));
      });

  /// POST /orders/:id/payments. Returns the order and the change.
  Future<PayResult> pay(String orderId, PaymentRequest request) => _guard(() async {
        final r = await _dio.post<dynamic>('/orders/$orderId/payments', data: request.toJson());
        return PayResult.fromJson(asMap(r.data));
      });

  /// POST /orders/:id/close
  Future<OrderView> close(String orderId) => _guard(() async {
        final r = await _dio.post<dynamic>('/orders/$orderId/close');
        return _order(r);
      });

  /// POST /orders/:id/refund
  Future<OrderView> refund(
    String orderId, {
    required String amount,
    required String reason,
    String? paymentId,
    String? approvalId,
  }) =>
      _guard(() async {
        final r = await _dio.post<dynamic>(
          '/orders/$orderId/refund',
          data: _body({
            'amount': amount,
            'reason': reason,
            'paymentId': paymentId,
            'approvalId': approvalId,
          }),
        );
        return _order(r);
      });

  // --- approvals -------------------------------------------------------------

  /// POST /approvals (sends the request to the manager's phone)
  Future<ApprovalView> createApproval(ApprovalRequest request) => _guard(() async {
        final r = await _dio.post<dynamic>('/approvals', data: request.toJson());
        return ApprovalView.fromJson(asMap(r.data));
      });

  /// POST /approvals/:id/decide
  Future<ApprovalView> decideApproval(String approvalId, {required bool approved}) =>
      _guard(() async {
        final r = await _dio.post<dynamic>(
          '/approvals/$approvalId/decide',
          data: {'decision': approved ? 'APPROVED' : 'DECLINED'},
        );
        return ApprovalView.fromJson(asMap(r.data));
      });

  /// POST /approvals/pin. Creates and approves in one step, using a manager PIN.
  Future<ApprovalView> approveWithPin(PinApprovalRequest request) => _guard(() async {
        final r = await _dio.post<dynamic>('/approvals/pin', data: request.toJson());
        return ApprovalView.fromJson(asMap(r.data));
      });

  /// GET /approvals/:id (polled every 3 s while waiting)
  Future<ApprovalView> approval(String approvalId) => _guard(() async {
        final r = await _dio.get<dynamic>('/approvals/$approvalId');
        return ApprovalView.fromJson(asMap(r.data));
      });

  /// GET /approvals?status=PENDING
  Future<List<ApprovalView>> pendingApprovals() => _guard(() async {
        final r = await _dio.get<dynamic>(
          '/approvals',
          queryParameters: {'status': ApprovalStatuses.pending},
        );
        return [for (final a in asMaps(r.data)) ApprovalView.fromJson(a)];
      });

  // --- reports and cash ------------------------------------------------------

  /// GET /reports/x
  Future<DayCloseTotals> xReport() => _guard(() async {
        final r = await _dio.get<dynamic>('/reports/x');
        return DayCloseTotals.fromJson(asMap(r.data));
      });

  /// POST /reports/z. Returns the totals of the new day close.
  Future<DayCloseTotals> closeDay({required String cashCounted, bool force = false}) =>
      _guard(() async {
        final r = await _dio.post<dynamic>(
          '/reports/z',
          data: {'cashCounted': cashCounted, if (force) 'force': true},
        );
        final data = asMap(r.data);
        return DayCloseTotals.fromJson(
          data['totals'] is Map ? asMap(data['totals']) : data,
        );
      });

  /// GET /reports/day-closes
  Future<List<DayCloseTotals>> dayCloses() => _guard(() async {
        final r = await _dio.get<dynamic>('/reports/day-closes');
        return [
          for (final row in asMaps(r.data))
            DayCloseTotals.fromJson(
              row['totals'] is Map
                  ? {...asMap(row['totals']), 'businessDate': row['businessDate']}
                  : row,
            ),
        ];
      });

  /// POST /cash-drawer/open (a "No sale" needs an approval first unless EDIT)
  Future<void> openCashDrawer({required String reason}) => _guard(() async {
        await _dio.post<dynamic>('/cash-drawer/open', data: {'reason': reason});
      });
}
