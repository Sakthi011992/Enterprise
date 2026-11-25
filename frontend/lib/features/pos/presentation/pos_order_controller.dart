import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../auth/data/auth_repository.dart';
import '../data/pos_models.dart';
import '../data/pos_repository.dart';

/// A line that is on its way to the server. It is shown with a spinner until
/// the server returns the order (PLAN 1.4 "optimistic line").
class PendingLine {
  const PendingLine({
    required this.tempId,
    required this.name,
    required this.quantity,
    this.seat,
  });

  final String tempId;
  final String name;
  final int quantity;
  final int? seat;
}

class PosOrderState {
  const PosOrderState({
    this.order,
    this.loading = false,
    this.busy = false,
    this.error,
    this.offline = false,
    this.pending = const [],
  });

  /// Server truth. Every price on screen comes from here.
  final OrderView? order;
  final bool loading;

  /// True while a mutation is in flight.
  final bool busy;

  /// Last failure message, cleared on the next successful call.
  final String? error;

  /// Set when the last call could not reach the server (status 0).
  final bool offline;
  final List<PendingLine> pending;

  PosOrderState copyWith({
    OrderView? order,
    bool? loading,
    bool? busy,
    String? error,
    bool clearError = false,
    bool? offline,
    List<PendingLine>? pending,
  }) =>
      PosOrderState(
        order: order ?? this.order,
        loading: loading ?? this.loading,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
        offline: offline ?? this.offline,
        pending: pending ?? this.pending,
      );
}

/// Holds one open order on the POS screen. Each action sends the request, then
/// replaces the order with the server's answer. Dialogs that need the approval
/// flow call the repository directly and hand the result back through
/// [replaceOrder].
class PosOrderController extends StateNotifier<PosOrderState> {
  PosOrderController(this._repo, this.orderId) : super(const PosOrderState());

  final PosRepository _repo;
  final String orderId;
  int _tempCounter = 0;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final order = await _repo.order(orderId);
      if (!mounted) return;
      state = state.copyWith(order: order, loading: false, offline: false);
    } catch (e) {
      _fail(e, loading: false);
    }
  }

  /// Takes a fresh order from a dialog or another screen.
  void replaceOrder(OrderView order) {
    state = state.copyWith(order: order, offline: false, clearError: true);
  }

  void clearError() => state = state.copyWith(clearError: true);

  void showError(String message) => state = state.copyWith(error: message);

  /// Runs one server call and stores the answer. Returns null on failure.
  Future<OrderView?> run(Future<OrderView> Function() call) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final order = await call();
      if (!mounted) return order;
      state = state.copyWith(order: order, busy: false, offline: false);
      return order;
    } catch (e) {
      _fail(e);
      return null;
    }
  }

  /// Adds one line with an optimistic placeholder while the request is open.
  Future<OrderView?> addLine(
    AddItem item, {
    required String name,
    int? seat,
  }) {
    final temp = 'tmp-${++_tempCounter}';
    state = state.copyWith(
      pending: [
        ...state.pending,
        PendingLine(tempId: temp, name: name, quantity: item.quantity, seat: seat),
      ],
    );
    return _addItemsThenClear([item], temp);
  }

  Future<OrderView?> _addItemsThenClear(List<AddItem> items, String temp) async {
    final result = await run(() => _repo.addItems(orderId, items));
    if (!mounted) return result;
    state = state.copyWith(
      pending: [
        for (final p in state.pending)
          if (p.tempId != temp) p,
      ],
    );
    return result;
  }

  Future<OrderView?> setQuantity(OrderItemView item, int quantity) {
    if (quantity <= 0) return run(() => _repo.removeItem(orderId, item.id));
    return run(() => _repo.updateItem(orderId, item.id, quantity: quantity));
  }

  Future<OrderView?> setSeat(OrderItemView item, int seat) =>
      run(() => _repo.updateItem(orderId, item.id, seat: seat));

  Future<SendResult?> send() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await _repo.send(orderId);
      if (!mounted) return result;
      state = state.copyWith(order: result.order, busy: false, offline: false);
      return result;
    } catch (e) {
      _fail(e);
      return null;
    }
  }

  Future<OrderView?> setHold({required bool held}) =>
      run(() => _repo.setHold(orderId, held: held));

  Future<OrderView?> printBill() => run(() => _repo.bill(orderId));

  Future<OrderView?> closeTable() => run(() => _repo.close(orderId));

  void _fail(Object e, {bool loading = false}) {
    if (!mounted) return;
    final err = ApiError.from(e);
    state = state.copyWith(
      busy: false,
      loading: loading ? false : state.loading,
      error: err.message,
      offline: err.isNetwork,
    );
  }
}

/// One controller per open order. Auto-disposed when the screen leaves.
final posOrderProvider =
    StateNotifierProvider.autoDispose.family<PosOrderController, PosOrderState, String>(
  (ref, orderId) {
    final controller = PosOrderController(ref.watch(posRepositoryProvider), orderId);
    controller.load();
    return controller;
  },
);

/// `GET /menu/pos`, shared by the POS screen and the modifier sheet.
final posMenuProvider = FutureProvider.autoDispose<PosMenu>(
  (ref) => ref.watch(posRepositoryProvider).menu(),
);

/// `GET /tables` (live view). Invalidate to refresh.
final posTablesProvider = FutureProvider.autoDispose<List<TableView>>(
  (ref) => ref.watch(posRepositoryProvider).tables(),
);

/// `GET /orders/open`, used by the merge option in the transfer dialog.
final openOrdersProvider = FutureProvider.autoDispose<List<OpenOrderSummary>>(
  (ref) => ref.watch(posRepositoryProvider).openOrders(),
);

/// Staff list from the existing PIN staff endpoint. Managers are picked from it.
final managerStaffProvider = FutureProvider.autoDispose<List<PinStaffMember>>((ref) async {
  final list = await ref.watch(authRepositoryProvider).pinStaff();
  return list.staff;
});
