import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../../pos/presentation/dialogs/manager_pin_dialog.dart';
import '../data/orders_repository.dart';

final _timeFormat = DateFormat('d MMM, h:mm a');

const _statusItems = [
  AppSelectItem('', 'All statuses'),
  AppSelectItem('OPEN', 'Open'),
  AppSelectItem('PAID', 'Paid'),
  AppSelectItem('VOID', 'Voided'),
  AppSelectItem('REFUNDED', 'Refunded'),
];

const _typeItems = [
  AppSelectItem('', 'All types'),
  AppSelectItem('DINE_IN', 'Dine-in'),
  AppSelectItem('BAR_COUNTER', 'Bar counter'),
  AppSelectItem('TAKEAWAY', 'Takeaway'),
  AppSelectItem('DELIVERY', 'Delivery'),
];

const _paymentItems = [
  AppSelectItem('', 'All payments'),
  AppSelectItem('CASH', 'Cash'),
  AppSelectItem('UPI', 'UPI'),
  AppSelectItem('CARD', 'Card'),
];

const _dateItems = [
  AppSelectItem(1, 'Today'),
  AppSelectItem(7, 'Last 7 days'),
  AppSelectItem(30, 'Last 30 days'),
];

/// Orders: filter by status, type, payment and date. Open a row for the
/// detail drawer, where reprint, refund and void live.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String _status = '';
  String _type = '';
  String _payment = '';
  int _days = 1;
  String _search = '';
  String? _drawerOrderId;

  OrderQuery get _query => (
        status: _status.isEmpty ? null : _status,
        type: _type.isEmpty ? null : _type,
        payment: _payment.isEmpty ? null : _payment,
        search: _search,
        days: _days,
      );

  void _open(OrderRow row) {
    setState(() => _drawerOrderId = row.id);
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _refresh() {
    ref.invalidate(ordersSearchProvider(_query));
    if (_drawerOrderId != null) ref.invalidate(orderDetailProvider(_drawerOrderId!));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final async = ref.watch(ordersSearchProvider(_query));
    final rows = async.valueOrNull ?? const <OrderRow>[];

    final columns = <AppColumn<OrderRow>>[
      AppColumn<OrderRow>(
        label: 'Order',
        cell: (r) => Text(
          r.invoiceNumber == null ? r.orderNumber : '${r.orderNumber} · ${r.invoiceNumber}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      AppColumn<OrderRow>(
        label: 'Type',
        width: 130,
        cell: (r) => Text(_typeLabel(r.type)),
      ),
      AppColumn<OrderRow>(
        label: 'Table',
        width: 100,
        cell: (r) => Text(r.tableName ?? '-'),
      ),
      AppColumn<OrderRow>(
        label: 'Status',
        width: 120,
        cell: (r) => _statusBadge(r.status),
      ),
      AppColumn<OrderRow>(
        label: 'Paid',
        width: 160,
        cell: (r) => Text(r.paidAt == null ? '-' : _timeFormat.format(r.paidAt!.toLocal())),
      ),
      AppColumn<OrderRow>(
        label: 'Total',
        numeric: true,
        width: 110,
        cell: (r) => Text('₹${r.grandTotal}'),
      ),
    ];

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: Drawer(
        width: 440,
        child: SafeArea(
          child: _drawerOrderId == null
              ? const SizedBox.shrink()
              : _OrderDrawer(
                  key: ValueKey(_drawerOrderId),
                  orderId: _drawerOrderId!,
                  onChanged: _refresh,
                ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Orders & invoices',
              breadcrumb: 'Sales',
              actions: [
                AppButton(
                  label: 'Refresh',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.ghost,
                  onPressed: _refresh,
                ),
              ],
            ),
            Expanded(
              child: AppDataTable<OrderRow>(
                columns: columns,
                rows: rows,
                searchHint: 'Search order or invoice number',
                onSearch: (v) => setState(() => _search = v),
                filters: [
                  _FilterBox(
                    child: AppSelect<String>(
                      label: 'Status',
                      value: _status,
                      items: _statusItems,
                      onChanged: (v) => setState(() => _status = v ?? ''),
                    ),
                  ),
                  _FilterBox(
                    child: AppSelect<String>(
                      label: 'Type',
                      value: _type,
                      items: _typeItems,
                      onChanged: (v) => setState(() => _type = v ?? ''),
                    ),
                  ),
                  _FilterBox(
                    child: AppSelect<String>(
                      label: 'Payment',
                      value: _payment,
                      items: _paymentItems,
                      onChanged: (v) => setState(() => _payment = v ?? ''),
                    ),
                  ),
                  _FilterBox(
                    child: AppSelect<int>(
                      label: 'Date',
                      value: _days,
                      items: _dateItems,
                      onChanged: (v) => setState(() => _days = v ?? 1),
                    ),
                  ),
                ],
                onRowTap: _open,
                loading: async.isLoading && !async.hasValue,
                error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
                onRetry: _refresh,
                empty: EmptyState(
                  title: 'No orders match',
                  message: 'Try another status, type or date.',
                  icon: Icons.receipt_long_outlined,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBox extends StatelessWidget {
  const _FilterBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(width: 170, child: child);
}

String _typeLabel(String type) => switch (type) {
      'DINE_IN' => 'Dine-in',
      'BAR_COUNTER' => 'Bar counter',
      'TAKEAWAY' => 'Takeaway',
      'DELIVERY' => 'Delivery',
      _ => type,
    };

Widget _statusBadge(String status) {
  final (label, tone) = switch (status) {
    'PAID' || 'CLOSED' => ('Paid', StatusTone.success),
    'VOID' => ('Voided', StatusTone.danger),
    'REFUNDED' => ('Refunded', StatusTone.warning),
    'OPEN' || 'SENT' || 'BILLED' => ('Open', StatusTone.info),
    _ => (status, StatusTone.neutral),
  };
  return StatusBadge(label: label, tone: tone);
}

/// Result of the refund or void dialog.
typedef _ActionInput = ({String? amount, String reason});

/// Detail drawer for one order: lines, payments and the three actions.
class _OrderDrawer extends ConsumerStatefulWidget {
  const _OrderDrawer({super.key, required this.orderId, required this.onChanged});

  final String orderId;
  final VoidCallback onChanged;

  @override
  ConsumerState<_OrderDrawer> createState() => _OrderDrawerState();
}

class _OrderDrawerState extends ConsumerState<_OrderDrawer> {
  String? _error;
  bool _busy = false;

  /// Runs [action]. On APPROVAL_REQUIRED, asks a manager for a PIN and retries
  /// once with the approval id. Returns true when the action went through.
  Future<bool> _guarded({
    required String approvalType,
    required Map<String, dynamic> payload,
    required String reason,
    required Future<void> Function(String? approvalId) action,
  }) async {
    try {
      await action(null);
      return true;
    } catch (e) {
      final err = ApiError.from(e);
      if (err.code != 'APPROVAL_REQUIRED') {
        _fail(err.message);
        return false;
      }
    }
    if (!mounted) return false;
    final approval = await showManagerPinDialog(
      context,
      type: approvalType,
      orderId: widget.orderId,
      payload: payload,
      reason: reason,
    );
    if (approval == null) return false;
    try {
      await action(approval.id);
      return true;
    } catch (e) {
      _fail(ApiError.from(e).message);
      return false;
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _run(Future<bool> Function() work, String success) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await work();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onChanged();
      showAppToast(context, success);
    }
  }

  Future<void> _reprint() => _run(() async {
        try {
          await ref.read(ordersRepositoryProvider).reprintBill(widget.orderId);
          return true;
        } catch (e) {
          _fail(ApiError.from(e).message);
          return false;
        }
      }, 'Bill sent to the printer');

  Future<void> _refund(OrderDetail order) async {
    final input = await showDialog<_ActionInput>(
      context: context,
      builder: (_) => _ActionDialog(
        title: 'Refund ${order.orderNumber}',
        confirmLabel: 'Refund',
        withAmount: true,
        maxAmount: double.tryParse(order.paid) ?? 0,
      ),
    );
    if (input == null) return;
    final amount = input.amount ?? order.paid;
    await _run(
      () => _guarded(
        approvalType: 'REFUND',
        payload: {'amount': amount},
        reason: input.reason,
        action: (approvalId) => ref.read(ordersRepositoryProvider).refund(
              widget.orderId,
              amount: amount,
              reason: input.reason,
              approvalId: approvalId,
            ),
      ),
      'Refund recorded',
    );
  }

  Future<void> _void(OrderDetail order) async {
    final input = await showDialog<_ActionInput>(
      context: context,
      builder: (_) => _ActionDialog(
        title: 'Void ${order.orderNumber}?',
        confirmLabel: 'Void order',
        destructive: true,
      ),
    );
    if (input == null) return;
    await _run(
      () => _guarded(
        approvalType: 'VOID',
        payload: const {},
        reason: input.reason,
        action: (approvalId) => ref.read(ordersRepositoryProvider).voidOrder(
              widget.orderId,
              reason: input.reason,
              approvalId: approvalId,
            ),
      ),
      'Order voided',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final detail = ref.watch(orderDetailProvider(widget.orderId));
    final canRefund = can(ref, Perm.salesPaymentsTake, AccessLevel.edit);
    final canVoid = can(ref, Perm.salesVoid, AccessLevel.request);

    return detail.when(
      loading: () => DelayedSkeleton(child: SkeletonList()),
      error: (e, _) => ErrorState(
        message: ApiError.from(e).message,
        onRetry: () => ref.invalidate(orderDetailProvider(widget.orderId)),
      ),
      data: (order) {
        final canVoidNow = canVoid && !order.hasPayments && order.status != 'VOID';
        final canRefundNow = canRefund && order.hasPayments && order.status != 'VOID';
        return ListView(
          padding: EdgeInsets.all(t.spacing.md),
          children: [
            Text(order.orderNumber, style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: t.spacing.xs),
            Wrap(
              spacing: t.spacing.sm,
              children: [
                _statusBadge(order.status),
                if (order.tableName != null) StatusBadge(label: order.tableName!, tone: StatusTone.neutral),
                if (order.invoiceNumber != null)
                  StatusBadge(label: order.invoiceNumber!, tone: StatusTone.neutral),
              ],
            ),
            SizedBox(height: t.spacing.md),
            if (_error != null) ...[
              InlineAlert(message: _error!),
              SizedBox(height: t.spacing.sm),
            ],
            AppCard(
              title: 'Items',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final line in order.items)
                    _Line(
                      label: '${line.quantity} × ${line.name}${line.seat == null ? '' : ' (seat ${line.seat})'}',
                      value: '₹${line.total}',
                    ),
                  if (order.items.isEmpty) const Text('No items'),
                ],
              ),
            ),
            SizedBox(height: t.spacing.md),
            AppCard(
              title: 'Payments',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in order.payments)
                    _Line(
                      label: '${p.method}${p.status == 'REFUNDED' ? ' (refunded)' : ''}',
                      value: '₹${p.amount}',
                    ),
                  if (order.payments.isEmpty) const Text('No payments yet'),
                  SizedBox(height: t.spacing.sm),
                  _Line(label: 'Total', value: '₹${order.grandTotal}'),
                  _Line(label: 'Paid', value: '₹${order.paid}'),
                  _Line(label: 'Due', value: '₹${order.due}'),
                ],
              ),
            ),
            SizedBox(height: t.spacing.md),
            Wrap(
              spacing: t.spacing.sm,
              runSpacing: t.spacing.sm,
              children: [
                AppButton(
                  label: 'Reprint bill',
                  icon: Icons.print_outlined,
                  onPressed: _busy ? null : _reprint,
                ),
                if (canRefundNow)
                  AppButton(
                    label: 'Refund',
                    icon: Icons.undo,
                    onPressed: _busy ? null : () => _refund(order),
                  ),
                if (canVoidNow)
                  AppButton(
                    label: 'Void order',
                    icon: Icons.block,
                    variant: AppButtonVariant.danger,
                    onPressed: _busy ? null : () => _void(order),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.spacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Reason (and optional amount) for a refund or void. Pops an [_ActionInput].
class _ActionDialog extends StatefulWidget {
  const _ActionDialog({
    required this.title,
    required this.confirmLabel,
    this.withAmount = false,
    this.maxAmount = 0,
    this.destructive = false,
  });

  final String title;
  final String confirmLabel;
  final bool withAmount;
  final double maxAmount;
  final bool destructive;

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String? _amountError;
  String? _reasonError;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final reason = _reason.text.trim();
    String? amount;
    String? amountError;
    if (widget.withAmount) {
      final value = double.tryParse(_amount.text.trim());
      if (value == null || value <= 0 || value > widget.maxAmount) {
        amountError = 'Enter more than 0 and up to ₹${widget.maxAmount.toStringAsFixed(2)}';
      } else {
        amount = value.toStringAsFixed(2);
      }
    }
    setState(() {
      _amountError = amountError;
      _reasonError = reason.isEmpty ? 'Enter a reason' : null;
    });
    if (amountError != null || _reasonError != null) return;
    Navigator.of(context).pop<_ActionInput>((amount: amount, reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.withAmount) ...[
              AppTextField(
                label: 'Amount',
                controller: _amount,
                keyboardType: TextInputType.number,
                errorText: _amountError,
                hint: widget.maxAmount.toStringAsFixed(2),
                helperText: 'Leave as the full paid amount for a full refund.',
              ),
              SizedBox(height: t.spacing.md),
            ],
            AppTextField(
              label: 'Reason',
              controller: _reason,
              errorText: _reasonError,
              autofocus: true,
            ),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: widget.confirmLabel,
          variant: widget.destructive ? AppButtonVariant.danger : AppButtonVariant.primary,
          onPressed: _confirm,
        ),
      ],
    );
  }
}
