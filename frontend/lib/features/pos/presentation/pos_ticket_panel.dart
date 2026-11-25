import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../data/pos_models.dart';
import 'pos_format.dart';
import 'pos_order_controller.dart';

/// Callbacks from the ticket panel into the POS screen. The screen owns the
/// dialogs and the navigation.
class PosTicketActions {
  const PosTicketActions({
    required this.onQuantity,
    required this.onSeat,
    required this.onSend,
    required this.onHold,
    required this.onSplit,
    required this.onDiscount,
    required this.onTransfer,
    required this.onVoid,
    required this.onPrintBill,
    required this.onPay,
    required this.onCloseTable,
  });

  final void Function(OrderItemView item, int quantity) onQuantity;
  final void Function(OrderItemView item) onSeat;
  final VoidCallback onSend;
  final VoidCallback onHold;
  final VoidCallback onSplit;
  final VoidCallback onDiscount;
  final VoidCallback onTransfer;
  final VoidCallback onVoid;
  final VoidCallback onPrintBill;
  final VoidCallback onPay;
  final VoidCallback onCloseTable;
}

/// The right-hand ticket: lines, totals and the action row. It watches the
/// order itself, so the wide side panel and the tablet sheet stay in step.
class PosTicketPanel extends ConsumerWidget {
  const PosTicketPanel({super.key, required this.orderId, required this.actions});

  final String orderId;
  final PosTicketActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final state = ref.watch(posOrderProvider(orderId));
    final order = state.order;
    final canEdit = can(ref, Perm.salesOrdersTake, AccessLevel.edit);
    final canDiscount = can(ref, Perm.salesDiscountGive, AccessLevel.request);
    final canVoid = can(ref, Perm.salesVoid, AccessLevel.request);
    final canPay = can(ref, Perm.salesPaymentsTake, AccessLevel.edit);
    final canBill = can(ref, Perm.salesPaymentsTake, AccessLevel.view);

    if (order == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final lines = order.liveItems;
    final due = order.totals.dueValue;
    final payable = order.totals.paidValue > 0 ? due : order.totals.grandTotalValue;
    final unsent = order.newItems.length;
    final editable = canEdit && order.isOpen && !order.isPaid;

    return Container(
      color: t.color.background.surface,
      padding: EdgeInsets.all(t.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(order: order),
          SizedBox(height: t.spacing.sm),
          Expanded(
            child: ListView(
              children: [
                if (lines.isEmpty && state.pending.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: t.spacing.lg),
                    child: Text(
                      'Tap a product to add it to the order.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.color.content.secondary),
                    ),
                  ),
                for (final p in state.pending) _PendingRow(line: p),
                for (final item in lines)
                  _LineRow(
                    item: item,
                    covers: order.covers,
                    editable: editable && item.isNew,
                    onQuantity: (q) => actions.onQuantity(item, q),
                    onSeat: () => actions.onSeat(item),
                  ),
                SizedBox(height: t.spacing.md),
                _Totals(order: order),
              ],
            ),
          ),
          SizedBox(height: t.spacing.sm),
          Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.sm,
            children: [
              if (canEdit && order.isOpen)
                AppButton(
                  label: order.isHeld ? 'Resume' : 'Hold',
                  variant: AppButtonVariant.ghost,
                  size: AppControlSize.md,
                  onPressed: state.busy ? null : actions.onHold,
                ),
              if (canEdit && order.liveItems.isNotEmpty && order.isOpen)
                AppButton(
                  label: 'Split',
                  variant: AppButtonVariant.ghost,
                  size: AppControlSize.md,
                  onPressed: actions.onSplit,
                ),
              if (canDiscount && editable)
                AppButton(
                  label: 'Discount',
                  variant: AppButtonVariant.ghost,
                  size: AppControlSize.md,
                  onPressed: state.busy ? null : actions.onDiscount,
                ),
              if (canEdit && editable)
                AppButton(
                  label: 'Transfer',
                  variant: AppButtonVariant.ghost,
                  size: AppControlSize.md,
                  onPressed: state.busy ? null : actions.onTransfer,
                ),
              if (canVoid && editable && lines.isNotEmpty)
                AppButton(
                  label: 'Void item',
                  variant: AppButtonVariant.ghost,
                  size: AppControlSize.md,
                  onPressed: state.busy ? null : actions.onVoid,
                ),
              if (canBill && order.isOpen && lines.isNotEmpty)
                AppButton(
                  label: 'Print bill',
                  variant: AppButtonVariant.ghost,
                  size: AppControlSize.md,
                  onPressed: state.busy ? null : actions.onPrintBill,
                ),
              if (canEdit && order.type == OrderTypes.dineIn && order.status == OrderStatuses.paid)
                AppButton(
                  label: 'Close table',
                  variant: AppButtonVariant.secondary,
                  size: AppControlSize.md,
                  onPressed: state.busy ? null : actions.onCloseTable,
                ),
            ],
          ),
          SizedBox(height: t.spacing.sm),
          Row(
            children: [
              if (canEdit && editable)
                Expanded(
                  child: AppButton(
                    label: unsent > 0
                        ? 'Send KOT/BOT ($unsent)'
                        : 'Send KOT/BOT',
                    variant: AppButtonVariant.secondary,
                    loading: state.busy,
                    onPressed: (unsent == 0 || state.busy) ? null : actions.onSend,
                  ),
                ),
              if (canEdit && editable) SizedBox(width: t.spacing.sm),
              if (canPay && order.isOpen && lines.isNotEmpty)
                Expanded(
                  child: AppButton(
                    label: 'Pay ${formatRupees(payable)}',
                    variant: AppButtonVariant.primary,
                    onPressed: (state.offline || state.busy) ? null : actions.onPay,
                  ),
                ),
            ],
          ),
          if (state.offline)
            Padding(
              padding: EdgeInsets.only(top: t.spacing.xs),
              child: Text(
                "Payments can't be taken offline. Reconnect to complete.",
                style: TextStyle(color: t.color.content.secondary, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.order});

  final OrderView order;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final opened = order.openedAt == null ? null : formatClock(order.openedAt!.toLocal());
    final where = order.table?.name ?? OrderTypes.label(order.type);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Order ${order.orderNumber}',
            style: Theme.of(context).textTheme.titleLarge,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (order.isHeld)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: StatusBadge(label: 'Held', tone: StatusTone.warning),
          ),
        if (order.tab case final tab?)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: StatusBadge(
              label: 'Tab ${tab.number} · ${formatRupees(tab.spentValue)} / ${formatRupees(tab.tabLimitValue)}',
              tone: tab.nearLimit ? StatusTone.warning : StatusTone.neutral,
            ),
          ),
        StatusBadge(
          label: opened == null ? where : '$where · $opened',
          tone: StatusTone.neutral,
        ),
        SizedBox(width: t.spacing.xs),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.item,
    required this.covers,
    required this.editable,
    required this.onQuantity,
    required this.onSeat,
  });

  final OrderItemView item;
  final int covers;
  final bool editable;
  final ValueChanged<int> onQuantity;
  final VoidCallback onSeat;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final details = [
      if (item.variantName != null && item.variantName!.isNotEmpty) item.variantName!,
      if (item.modifierSummary.isNotEmpty) item.modifierSummary,
      if (item.note != null && item.note!.isNotEmpty) 'Note: ${item.note}',
    ];
    return Container(
      padding: EdgeInsets.symmetric(vertical: t.spacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.color.border.subtle, width: t.borderWidth.hairline),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.quantity > 1 ? '${item.quantity} × ${item.name}' : item.name,
                  style: TextStyle(fontWeight: FontWeight.w600, color: t.color.content.primary),
                ),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: TextStyle(color: t.color.content.secondary, fontSize: 13),
                  ),
                SizedBox(height: t.spacing.xs),
                Wrap(
                  spacing: t.spacing.xs,
                  runSpacing: t.spacing.xs,
                  children: [
                    _StatusChip(item: item),
                    if (item.hasHappyHour)
                      StatusBadge(
                        label: 'Happy hour −${item.happyHourPercent}%',
                        tone: StatusTone.warning,
                      ),
                    if (item.seat != null)
                      Semantics(
                        button: editable,
                        label: 'Seat ${item.seat}${editable ? ', tap to change' : ''}',
                        child: InkWell(
                          onTap: editable ? onSeat : null,
                          child: StatusBadge(label: 'Seat ${item.seat}', tone: StatusTone.neutral),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (editable)
            Row(
              children: [
                IconButton.outlined(
                  tooltip: 'Less',
                  icon: const Icon(Icons.remove),
                  onPressed: () => onQuantity(item.quantity - 1),
                ),
                SizedBox(
                  width: 32,
                  child: Text('${item.quantity}', textAlign: TextAlign.center),
                ),
                IconButton.outlined(
                  tooltip: 'More',
                  icon: const Icon(Icons.add),
                  onPressed: () => onQuantity(item.quantity + 1),
                ),
              ],
            ),
          SizedBox(width: t.spacing.sm),
          Text(
            formatWire(item.total),
            style: TextStyle(fontWeight: FontWeight.w600, color: t.color.content.primary),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.item});

  final OrderItemView item;

  @override
  Widget build(BuildContext context) {
    if (item.isSent) {
      final label = item.ticketKind == 'BOT' ? 'BOT sent' : 'KOT sent';
      return StatusBadge(label: item.status == ItemStatuses.served ? 'Served' : label, tone: StatusTone.success);
    }
    return const StatusBadge(label: 'New', tone: StatusTone.info);
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.line});

  final PendingLine line;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.spacing.sm),
      child: Row(
        children: [
          const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: t.spacing.sm),
          Expanded(
            child: Text(
              '${line.quantity} × ${line.name}',
              style: TextStyle(color: t.color.content.secondary),
            ),
          ),
          Text('Adding…', style: TextStyle(color: t.color.content.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.order});

  final OrderView order;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final totals = order.totals;
    final taxNames = {for (final line in totals.taxBreakdown) line.name}.join(' · ');
    return Column(
      children: [
        _TotalRow(label: 'Subtotal', value: formatWire(totals.subtotal)),
        if (totals.discountTotal != '0.00')
          _TotalRow(label: 'Discount', value: '−${formatWire(totals.discountTotal)}'),
        if (totals.serviceCharge != '0.00')
          _TotalRow(label: 'Service charge', value: formatWire(totals.serviceCharge)),
        _TotalRow(
          label: taxNames.isEmpty ? 'Tax' : taxNames,
          value: formatWire(totals.taxTotal),
        ),
        if (totals.roundOff != '0.00')
          _TotalRow(label: 'Round off', value: formatWire(totals.roundOff)),
        Divider(color: t.color.border.subtle, height: t.spacing.lg),
        _TotalRow(label: 'Total', value: formatWire(totals.grandTotal), strong: true),
        if (totals.paidValue > 0) ...[
          _TotalRow(label: 'Paid', value: formatWire(totals.paid)),
          _TotalRow(label: 'Due', value: formatWire(totals.due), strong: true),
        ],
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = TextStyle(
      fontSize: strong ? 17 : 14,
      fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
      color: strong ? t.color.content.primary : t.color.content.secondary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Keeps the seat cycle in one place: null → 1 → 2 … → covers → 1.
int nextSeat(int? current, int covers) {
  final max = covers < 1 ? 1 : covers;
  if (current == null || current >= max) return 1;
  return current + 1;
}
