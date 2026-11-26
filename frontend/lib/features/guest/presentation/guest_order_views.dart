import 'package:flutter/material.dart';

import '../../pos/presentation/pos_format.dart';
import '../application/guest_controller.dart';
import '../data/guest_models.dart';
import 'guest_widgets.dart';

/// "Your waiter confirms before it goes to the kitchen." / "Goes straight to the kitchen."
String routingMessage(GuestRouting routing) => routing == GuestRouting.direct
    ? 'Goes straight to the kitchen.'
    : 'Your waiter confirms before it goes to the kitchen.';

/// Lines of this guest's cart plus the kitchen note.
class CartLines extends StatelessWidget {
  const CartLines({super.key, required this.state, required this.controller, this.noteController});

  final GuestState state;
  final GuestController controller;
  final TextEditingController? noteController;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    if (state.cart.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('Your cart is empty. Add something from the menu.',
            textAlign: TextAlign.center, style: p.body(13, color: p.ink2)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GuestCard(
        child: Column(children: [
          for (var i = 0; i < state.cart.length; i++)
            _CartRow(
              line: state.cart[i],
              last: i == state.cart.length - 1,
              locked: state.placing,
              onQty: (q) => controller.setQuantity(state.cart[i].key, q),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      Text('Note for the kitchen (optional)', style: p.body(12, weight: FontWeight.w600)),
      const SizedBox(height: 5),
      TextField(
        key: const Key('guest-cart-note'),
        controller: noteController,
        enabled: !state.placing,
        maxLength: 140,
        onChanged: controller.setNote,
        style: p.body(14),
        decoration: InputDecoration(
          counterText: '',
          hintText: 'Less sugar in the colada',
          hintStyle: p.body(14, color: p.muted),
          filled: true,
          fillColor: p.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.accent, width: 2)),
        ),
      ),
    ]);
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({required this.line, required this.last, required this.locked, required this.onQty});

  final GuestCartLine line;
  final bool last;
  final bool locked;
  final ValueChanged<int> onQty;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final sub = line.optionNames.isNotEmpty ? line.optionNames.join(', ') : line.product.description;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: p.line2))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${line.quantity} × ${line.product.name}', style: p.body(13, weight: FontWeight.w600)),
            if (sub.isNotEmpty) Text(sub, style: p.body(11, color: p.muted)),
          ]),
        ),
        GuestStepper(
          value: line.quantity,
          name: line.product.name,
          onMinus: locked ? null : () => onQty(line.quantity - 1),
          onPlus: locked || line.quantity >= 10 ? null : () => onQty(line.quantity + 1),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 64,
          child: Text(formatRupees(line.total), textAlign: TextAlign.end, style: p.mono(12.5)),
        ),
      ]),
    );
  }
}

/// Items total, routing message and Place order.
class CartFooter extends StatelessWidget {
  const CartFooter({super.key, required this.state, required this.controller, this.showTaxRow = true});

  final GuestState state;
  final GuestController controller;
  final bool showTaxRow;

  @override
  Widget build(BuildContext context) {
    final total = formatRupees(state.cartTotal);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AmountRow(label: 'Items', amount: total, strong: !showTaxRow),
      if (showTaxRow) ...[
        const SizedBox(height: 6),
        const AmountRow(label: 'Tax and service on the bill', amount: '—'),
      ],
      const SizedBox(height: 10),
      GuestNote(routingMessage(state.settings.routing)),
      if (state.error != null) ...[
        const SizedBox(height: 8),
        GuestNote(state.error!, tone: GuestNoteTone.error),
      ],
      const SizedBox(height: 9),
      GuestButton(
        key: const Key('guest-place-order'),
        kind: state.cart.isEmpty ? GuestButtonKind.off : GuestButtonKind.primary,
        label: state.placing && state.offline
            ? "You're offline — we'll retry"
            : state.cart.isEmpty
                ? 'Place order'
                : 'Place order · $total',
        loading: state.placing,
        onPressed: state.cart.isEmpty || state.placing ? null : controller.placeOrder,
      ),
    ]);
  }
}

/// Every round at the table, newest first, grouped by who placed it.
class TableOrderRounds extends StatelessWidget {
  const TableOrderRounds({super.key, required this.state, required this.controller, this.compact = false});

  final GuestState state;
  final GuestController controller;

  /// Desktop side panel: short chip labels, "1 min" without "ago".
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final order = state.order;
    if (order == null || order.rounds.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('Nothing ordered yet. Rounds from everyone at the table show here.',
            textAlign: TextAlign.center, style: p.body(13, color: p.ink2)),
      );
    }
    final names = <String>[];
    for (final r in order.rounds.reversed) {
      if (!names.contains(r.by)) names.add(r.by);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final r in order.rounds)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RoundCard(
            round: r,
            compact: compact,
            alt: names.indexOf(r.by).isOdd,
            canCancel: _isMine(r) && r.status == GuestRoundStatus.pending && state.settings.allowGuestCancel,
            onCancel: () => controller.cancelRound(r.id),
          ),
        ),
    ]);
  }

  bool _isMine(GuestRound r) {
    if (r.mine) return true;
    final g = state.guest;
    if (g == null) return false;
    if (r.participantId != null) return r.participantId == g.participantId;
    return r.by == g.name;
  }
}

/// Explains why a round did not reach the kitchen.
String? roundProblem(GuestRound r) => switch (r.status) {
      GuestRoundStatus.rejected => r.rejectReason == null || r.rejectReason!.trim().isEmpty
          ? "Your waiter couldn't take this round."
          : "Your waiter couldn't take this round: ${r.rejectReason}",
      GuestRoundStatus.expired =>
        'No waiter confirmed this round in time. Place it again if you still want it.',
      _ => null,
    };

class RoundCard extends StatelessWidget {
  const RoundCard({
    super.key,
    required this.round,
    this.compact = false,
    this.alt = false,
    this.canCancel = false,
    this.onCancel,
  });

  final GuestRound round;
  final bool compact;
  final bool alt;
  final bool canCancel;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final ago = agoText(round.createdAt, suffix: !compact);
    final problem = roundProblem(round);
    return GuestCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          GuestAvatar(round.by, alt: alt),
          const SizedBox(width: 8),
          Text(round.by, style: p.body(12, weight: FontWeight.w700)),
          if (ago.isNotEmpty) Text(' · $ago', style: p.body(12, color: p.ink2)),
          const Spacer(),
          if (canCancel)
            Semantics(
              button: true,
              child: InkWell(
                onTap: onCancel,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Text('Cancel', style: p.body(12, weight: FontWeight.w600, color: p.accent)),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        for (final l in round.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 26, child: Text('${l.qty}×', style: p.mono(12, color: p.ink2))),
              Expanded(
                child: Text(
                  compact ? l.name.replaceAll(RegExp(r'\s*\(.*\)$'), '') : l.name,
                  style: p.body(13).copyWith(
                        decoration: l.state == GuestLineState.cancelled ? TextDecoration.lineThrough : null,
                      ),
                ),
              ),
              const SizedBox(width: 6),
              LineStateChip(l.state, short: compact),
            ]),
          ),
        if (problem != null) GuestNote(problem, tone: GuestNoteTone.error),
      ]),
    );
  }
}

/// Totals card of the bill.
class BillTotals extends StatelessWidget {
  const BillTotals({super.key, required this.order});

  final GuestOrderView order;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final t = order.totals;
    final pending = order.pendingEstimate;
    final items = order.itemCount;
    return GuestCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AmountRow(label: 'Subtotal ($items ${items == 1 ? 'item' : 'items'})', amount: formatRupees(t.subtotal)),
        if (t.discount > 0) ...[
          const SizedBox(height: 8),
          AmountRow(label: 'Discount', amount: formatRupees(-t.discount)),
        ],
        if (t.serviceCharge > 0) ...[
          const SizedBox(height: 8),
          AmountRow(label: 'Service charge', amount: formatRupees(t.serviceCharge)),
        ],
        const SizedBox(height: 8),
        AmountRow(label: 'GST', amount: formatRupees(t.tax)),
        if (t.roundOff != 0) ...[
          const SizedBox(height: 8),
          AmountRow(label: 'Round off', amount: formatRupees(t.roundOff, alwaysPaise: true)),
        ],
        const SizedBox(height: 8),
        Divider(height: 1, color: p.line),
        const SizedBox(height: 8),
        AmountRow(label: 'Total', amount: formatRupees(t.grandTotal), strong: true),
        if (t.paid > 0) ...[
          const SizedBox(height: 8),
          AmountRow(label: 'Paid', amount: formatRupees(t.paid)),
          const SizedBox(height: 8),
          AmountRow(label: 'Still to pay', amount: formatRupees(t.due)),
        ],
        if (pending > 0) ...[
          const SizedBox(height: 8),
          Text('Includes ${formatRupees(pending)} waiting for the waiter to confirm (estimate).',
              style: p.body(11, color: p.ext.onWarningSubtle)),
        ],
      ]),
    );
  }
}

/// Ask for the bill (primary) and the Pay online placeholder.
class BillActions extends StatelessWidget {
  const BillActions({super.key, required this.state, required this.controller});

  final GuestState state;
  final GuestController controller;

  @override
  Widget build(BuildContext context) {
    final asked = state.order?.checkout.requested ?? false;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (asked) ...[
        const GuestNote('Your waiter is bringing the bill', tone: GuestNoteTone.info),
        const SizedBox(height: 9),
      ] else ...[
        GuestButton(
          key: const Key('guest-ask-bill'),
          kind: GuestButtonKind.primary,
          icon: Icons.receipt_long_outlined,
          label: 'Ask for the bill',
          onPressed: controller.askForBill,
        ),
        const SizedBox(height: 9),
      ],
      const GuestButton(
        kind: GuestButtonKind.off,
        icon: Icons.lock_outline,
        label: 'Pay online',
        trailing: SoonPill(),
      ),
    ]);
  }
}

/// "Your waiter is bringing the bill" confirmation.
class BillAskedView extends StatelessWidget {
  const BillAskedView({super.key, required this.state, required this.onBack});

  final GuestState state;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final total = state.order?.totals.grandTotal ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _BigIcon(icon: Icons.receipt_long_outlined),
            const SizedBox(height: 10),
            Text('Your waiter is bringing the bill', textAlign: TextAlign.center, style: p.display(22)),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text('Total ${formatRupees(total)}. Pay by UPI, card or cash at the table.',
                  textAlign: TextAlign.center, style: p.body(13, color: p.ink2)),
            ),
          ]),
        ),
      ),
      GuestButton(label: 'Back to table order', onPressed: onBack),
    ]);
  }
}

class _BigIcon extends StatelessWidget {
  const _BigIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: p.ext.successSubtle, shape: BoxShape.circle),
      child: Icon(icon, size: 30, color: p.ext.onSuccessSubtle),
    );
  }
}

/// Big success icon, shared with the thank-you page.
class GuestBigIcon extends StatelessWidget {
  const GuestBigIcon({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => _BigIcon(icon: icon);
}
