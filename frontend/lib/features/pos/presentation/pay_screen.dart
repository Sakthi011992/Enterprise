import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../data/pos_models.dart';
import '../data/pos_repository.dart';
import 'dialogs/dialog_frame.dart';
import 'pay_math.dart';
import 'pos_format.dart';
import 'pos_order_controller.dart';
import 'pos_ticket_panel.dart' show nextSeat;

/// Split modes from the POSPay board.
enum PayMode { oneBill, equal, bySeat, byItem }

/// Pay screen (`/pos/:orderId/pay`). Splits the bill, takes tenders, and completes
/// a share or the whole bill. Payments are online only.
class PayScreen extends ConsumerStatefulWidget {
  const PayScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends ConsumerState<PayScreen> {
  PayMode _mode = PayMode.oneBill;
  int _parts = 2;
  List<SplitShare> _shares = const [];
  int _selected = 0;
  bool _loadingShares = false;
  String? _shareError;

  /// Seat chosen per item in by-item mode. Unset items go to seat 1.
  final Map<String, int> _itemSeat = {};

  String _tipChoice = 'none';
  final _customTip = TextEditingController();

  /// Cash keypad, rupees as typed. Empty means no cash.
  String _cash = '';
  bool _useUpi = false;
  final _upiAmount = TextEditingController();
  final _upiRef = TextEditingController();
  bool _useCard = false;

  bool _paying = false;
  String? _payError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadShares();
    });
  }

  @override
  void dispose() {
    _customTip.dispose();
    _upiAmount.dispose();
    _upiRef.dispose();
    super.dispose();
  }

  OrderView? get _order => ref.read(posOrderProvider(widget.orderId)).order;

  SplitShare? get _share => _shares.isEmpty ? null : _shares[_selected.clamp(0, _shares.length - 1).toInt()];

  /// Loads the shares for the current mode. One-bill mode needs no call.
  Future<void> _loadShares() async {
    final order = _order;
    if (order == null) return;
    if (_mode == PayMode.oneBill) {
      setState(() {
        _shares = [
          SplitShare(
            label: 'Whole bill',
            amount: order.totals.grandTotal,
            paid: order.totals.paid,
            due: order.totals.due,
          ),
        ];
        _selected = 0;
        _shareError = null;
      });
      return;
    }
    setState(() {
      _loadingShares = true;
      _shareError = null;
    });
    try {
      final repo = ref.read(posRepositoryProvider);
      final result = switch (_mode) {
        PayMode.equal => await repo.split(widget.orderId, mode: 'EQUAL', parts: _parts),
        PayMode.bySeat => await repo.split(widget.orderId, mode: 'SEAT'),
        PayMode.byItem => await repo.split(
            widget.orderId,
            mode: 'ITEMS',
            assign: [
              for (final item in order.liveItems)
                (itemId: item.id, seat: _itemSeat[item.id] ?? 1),
            ],
          ),
        PayMode.oneBill => const SplitResult(),
      };
      if (!mounted) return;
      setState(() {
        _shares = result.shares;
        _selected = _firstOpenShare(result.shares);
        _loadingShares = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingShares = false;
        _shareError = ApiError.from(e).message;
      });
    }
  }

  int _firstOpenShare(List<SplitShare> shares) {
    for (var i = 0; i < shares.length; i++) {
      if (!shares[i].isSettled) return i;
    }
    return 0;
  }

  void _setMode(PayMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _payError = null;
    });
    _loadShares();
  }

  void _resetTenders() {
    _cash = '';
    _useUpi = false;
    _useCard = false;
    _upiAmount.clear();
    _upiRef.clear();
    _tipChoice = 'none';
    _customTip.clear();
  }

  TenderPlan get _plan {
    final share = _share;
    return planTender(
      due: share?.dueValue.toDouble() ?? 0,
      tipChoice: _tipChoice,
      customTip: parseRupeeInput(_customTip.text),
      cash: parseRupeeInput(_cash),
      useUpi: _useUpi,
      upi: parseRupeeInput(_upiAmount.text),
      useCard: _useCard,
    );
  }

  /// Button text for the current share. Seat modes say "Complete seat N".
  String _completeLabel(SplitShare? share) {
    if (share == null || _mode == PayMode.oneBill) return 'Complete payment';
    return 'Complete ${_lowerFirst(share.label)}';
  }

  static String _lowerFirst(String text) =>
      text.isEmpty ? text : '${text[0].toLowerCase()}${text.substring(1)}';

  void _key(String k) {
    setState(() {
      _payError = null;
      if (k == '⌫') {
        if (_cash.isNotEmpty) _cash = _cash.substring(0, _cash.length - 1);
        return;
      }
      if (_cash.length >= 7) return;
      if (k == '00' && _cash.isEmpty) return;
      final dot = _cash.indexOf('.');
      if (dot >= 0 && _cash.length - dot > 2) return; // no more than paise
      _cash = (_cash == '0' || _cash.isEmpty) && k != '00' ? k : '$_cash$k';
    });
  }

  Future<void> _complete() async {
    final share = _share;
    final order = _order;
    if (share == null || order == null) return;
    final plan = _plan;
    if (!plan.isCovered) {
      setState(() => _payError = 'Still to pay: ${formatRupees(plan.remaining, alwaysPaise: true)}.');
      return;
    }
    final payments = <PaymentInput>[
      if (plan.cashApplied > 0)
        PaymentInput(
          method: PaymentMethods.cash,
          amount: wireMoney(plan.cashApplied),
          tendered: wireMoney(parseRupeeInput(_cash)),
          seat: share.seat,
        ),
      if (plan.upiApplied > 0)
        PaymentInput(
          method: PaymentMethods.upi,
          amount: wireMoney(plan.upiApplied),
          reference: _upiRef.text.trim(),
          seat: share.seat,
        ),
      if (plan.cardApplied > 0)
        PaymentInput(
          method: PaymentMethods.card,
          amount: wireMoney(plan.cardApplied),
          seat: share.seat,
        ),
    ];
    final completeSeat = (_mode == PayMode.bySeat || _mode == PayMode.byItem) ? share.seat : null;

    setState(() {
      _paying = true;
      _payError = null;
    });
    try {
      final result = await ref.read(posRepositoryProvider).pay(
            widget.orderId,
            PaymentRequest(payments: payments, tipAmount: plan.tipWire, completeSeat: completeSeat),
          );
      if (!mounted) return;
      ref.read(posOrderProvider(widget.orderId).notifier).replaceOrder(result.order);
      setState(() {
        _paying = false;
        _resetTenders();
      });
      final change = result.changeValue;
      final changeText = change > 0 ? ' Change ${formatWire(result.change, alwaysPaise: true)}.' : '';
      if (result.order.isPaid || result.order.status == OrderStatuses.closed) {
        showAppToast(context, 'Paid.$changeText');
        context.go('/pos/${widget.orderId}');
      } else {
        showAppToast(context, '${share.label} paid.$changeText');
        await _loadShares();
      }
    } catch (e) {
      if (!mounted) return;
      final err = ApiError.from(e);
      setState(() {
        _paying = false;
        _payError = err.code == 'PAYMENT_EXCEEDS_DUE'
            ? 'That is more than is due. Check the amounts.'
            : err.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posOrderProvider(widget.orderId));
    final order = state.order;
    final canPay = can(ref, Perm.salesPaymentsTake, AccessLevel.edit);
    return DensityScope(
      density: AppDensity.pos,
      child: Scaffold(
        body: SafeArea(
          child: order == null
              ? (state.error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: ErrorState(message: state.error!),
                    )
                  : const Center(child: CircularProgressIndicator()))
              : !canPay
                  ? const Center(child: Text('You do not have permission to take payments.'))
                  : _body(order, state),
        ),
      ),
    );
  }

  Widget _body(OrderView order, PosOrderState state) {
    final t = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final left = _SharesPane(
          order: order,
          mode: _mode,
          parts: _parts,
          shares: _shares,
          selected: _selected,
          loading: _loadingShares,
          error: _shareError,
          itemSeat: _itemSeat,
          onBack: () => context.go('/pos/${widget.orderId}'),
          onMode: _setMode,
          onParts: (p) {
            setState(() => _parts = p);
            _loadShares();
          },
          onSelect: (i) => setState(() {
            _selected = i;
            _resetTenders();
          }),
          onItemSeat: (item) {
            setState(() => _itemSeat[item.id] = nextSeat(_itemSeat[item.id], order.covers));
            _loadShares();
          },
        );
        final right = _TenderPane(
          order: order,
          share: _share,
          plan: _plan,
          offline: state.offline,
          paying: _paying,
          payError: _payError,
          completeLabel: _completeLabel(share),
          cash: _cash,
          useUpi: _useUpi,
          upiAmount: _upiAmount,
          upiRef: _upiRef,
          useCard: _useCard,
          tipChoice: _tipChoice,
          customTip: _customTip,
          onKey: _key,
          onQuick: (amount) => setState(() {
            _cash = '$amount';
            _payError = null;
          }),
          onExact: () => setState(() {
            final total = _plan.due + _plan.tip;
            _cash = total == total.roundToDouble()
                ? total.toStringAsFixed(0)
                : total.toStringAsFixed(2);
            _payError = null;
          }),
          onUpi: () => setState(() => _useUpi = !_useUpi),
          onCard: () => setState(() => _useCard = !_useCard),
          onTip: (choice) => setState(() => _tipChoice = choice),
          onChanged: () => setState(() => _payError = null),
          onComplete: _complete,
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: Padding(padding: EdgeInsets.all(t.spacing.md), child: left)),
              SizedBox(
                width: 420,
                child: Container(
                  color: t.color.background.surface,
                  padding: EdgeInsets.all(t.spacing.md),
                  child: SingleChildScrollView(child: right),
                ),
              ),
            ],
          );
        }
        return SingleChildScrollView(
          padding: EdgeInsets.all(t.spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, SizedBox(height: t.spacing.lg), right],
          ),
        );
      },
    );
  }
}

class _SharesPane extends StatelessWidget {
  const _SharesPane({
    required this.order,
    required this.mode,
    required this.parts,
    required this.shares,
    required this.selected,
    required this.loading,
    required this.error,
    required this.itemSeat,
    required this.onBack,
    required this.onMode,
    required this.onParts,
    required this.onSelect,
    required this.onItemSeat,
  });

  final OrderView order;
  final PayMode mode;
  final int parts;
  final List<SplitShare> shares;
  final int selected;
  final bool loading;
  final String? error;
  final Map<String, int> itemSeat;
  final VoidCallback onBack;
  final ValueChanged<PayMode> onMode;
  final ValueChanged<int> onParts;
  final ValueChanged<int> onSelect;
  final ValueChanged<OrderItemView> onItemSeat;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppIconButton(icon: Icons.arrow_back, tooltip: 'Back to order', onPressed: onBack),
            Expanded(
              child: Text(
                'Pay · Order ${order.orderNumber}${order.table == null ? '' : ' · ${order.table!.name}'}',
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Text(
          '${formatWire(order.totals.grandTotal)} incl. tax'
          '${order.totals.serviceCharge != '0.00' ? ' and service' : ''}',
          style: TextStyle(color: t.color.content.secondary),
        ),
        SizedBox(height: t.spacing.md),
        Wrap(
          spacing: t.spacing.sm,
          runSpacing: t.spacing.sm,
          children: [
            for (final entry in const {
              PayMode.oneBill: 'One bill',
              PayMode.equal: 'Split equally',
              PayMode.bySeat: 'By seat',
              PayMode.byItem: 'By item',
            }.entries)
              PosChoiceChip(
                label: entry.value,
                selected: mode == entry.key,
                minHeight: 52,
                onTap: () => onMode(entry.key),
              ),
          ],
        ),
        SizedBox(height: t.spacing.md),
        if (mode == PayMode.equal)
          Row(
            children: [
              Text('Parts', style: TextStyle(color: t.color.content.secondary)),
              SizedBox(width: t.spacing.sm),
              IconButton.outlined(
                tooltip: 'Fewer parts',
                icon: const Icon(Icons.remove),
                onPressed: parts > 2 ? () => onParts(parts - 1) : null,
              ),
              SizedBox(
                width: 40,
                child: Text('$parts', textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
              ),
              IconButton.outlined(
                tooltip: 'More parts',
                icon: const Icon(Icons.add),
                onPressed: parts < 8 ? () => onParts(parts + 1) : null,
              ),
            ],
          ),
        if (mode == PayMode.byItem) ...[
          Text(
            'Tap an item to move it to the next seat.',
            style: TextStyle(color: t.color.content.secondary),
          ),
          SizedBox(height: t.spacing.sm),
          for (final item in order.liveItems)
            Padding(
              padding: EdgeInsets.only(bottom: t.spacing.xs),
              child: Material(
                color: t.color.background.raised,
                borderRadius: BorderRadius.circular(t.radius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(t.radius.md),
                  onTap: () => onItemSeat(item),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: EdgeInsets.symmetric(horizontal: t.spacing.md),
                    child: Row(
                      children: [
                        Expanded(child: Text(item.name)),
                        StatusBadge(
                          label: 'Seat ${itemSeat[item.id] ?? 1}',
                          tone: StatusTone.neutral,
                        ),
                        SizedBox(width: t.spacing.sm),
                        Text(formatWire(item.total)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          SizedBox(height: t.spacing.md),
        ],
        if (loading)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else if (error != null)
          InlineAlert(message: error!)
        else if (shares.isEmpty)
          const EmptyState(title: 'Nothing to pay', message: 'The bill is already settled.')
        else
          for (var i = 0; i < shares.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: t.spacing.sm),
              child: _ShareCard(
                share: shares[i],
                selected: i == selected,
                onTap: () => onSelect(i),
              ),
            ),
      ],
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.share, required this.selected, required this.onTap});

  final SplitShare share;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final settled = share.isSettled;
    return Semantics(
      button: true,
      selected: selected,
      label: '${share.label}, due ${formatWire(share.due)}${settled ? ', paid' : ''}',
      child: Material(
        color: t.color.background.raised,
        borderRadius: BorderRadius.circular(t.radius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radius.lg),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.all(t.spacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius.lg),
              border: Border.all(
                color: selected ? t.color.border.focus : t.color.border.default,
                width: selected ? t.borderWidth.thick : t.borderWidth.hairline,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        share.label,
                        style: TextStyle(fontWeight: FontWeight.w700, color: t.color.content.primary),
                      ),
                      Text(
                        'Paid ${formatWire(share.paid)}',
                        style: TextStyle(color: t.color.content.secondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatWire(share.due),
                      style: TextStyle(fontWeight: FontWeight.w700, color: t.color.content.primary),
                    ),
                    settled
                        ? const StatusBadge(label: 'Paid', tone: StatusTone.success)
                        : const StatusBadge(label: 'Due', tone: StatusTone.warning),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TenderPane extends StatelessWidget {
  const _TenderPane({
    required this.order,
    required this.share,
    required this.plan,
    required this.offline,
    required this.paying,
    required this.payError,
    required this.completeLabel,
    required this.cash,
    required this.useUpi,
    required this.upiAmount,
    required this.upiRef,
    required this.useCard,
    required this.tipChoice,
    required this.customTip,
    required this.onKey,
    required this.onQuick,
    required this.onExact,
    required this.onUpi,
    required this.onCard,
    required this.onTip,
    required this.onChanged,
    required this.onComplete,
  });

  final OrderView order;
  final SplitShare? share;
  final TenderPlan plan;
  final bool offline;
  final bool paying;
  final String? payError;
  final String completeLabel;
  final String cash;
  final bool useUpi;
  final TextEditingController upiAmount;
  final TextEditingController upiRef;
  final bool useCard;
  final String tipChoice;
  final TextEditingController customTip;
  final ValueChanged<String> onKey;
  final ValueChanged<int> onQuick;
  final VoidCallback onExact;
  final VoidCallback onUpi;
  final VoidCallback onCard;
  final ValueChanged<String> onTip;
  final VoidCallback onChanged;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final s = share;
    final tipsSource = s?.dueValue.toDouble() ?? 0;
    final tip5 = roundPaise(tipsSource * 0.05);
    final tip10 = roundPaise(tipsSource * 0.10);
    final seatLabel = s == null ? '' : s.label;
    final canComplete = s != null && !s.isSettled && plan.isCovered && !offline && !paying;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          seatLabel.isEmpty ? 'Nothing to pay' : seatLabel,
          style: theme.textTheme.titleMedium,
        ),
        SizedBox(height: t.spacing.sm),
        _Line(label: 'Due', value: formatRupees(plan.due, alwaysPaise: true)),
        if (plan.tip > 0) _Line(label: 'Tip', value: formatRupees(plan.tip, alwaysPaise: true)),
        _Line(
          label: 'Total for this share',
          value: formatRupees(plan.due + plan.tip, alwaysPaise: true),
          strong: true,
        ),
        SizedBox(height: t.spacing.md),
        Text('Tip', style: TextStyle(color: t.color.content.secondary)),
        SizedBox(height: t.spacing.xs),
        Wrap(
          spacing: t.spacing.sm,
          runSpacing: t.spacing.sm,
          children: [
            PosChoiceChip(
              label: 'None',
              selected: tipChoice == 'none',
              minHeight: 48,
              onTap: () => onTip('none'),
            ),
            PosChoiceChip(
              label: '5% · ${formatRupees(tip5)}',
              selected: tipChoice == '5',
              minHeight: 48,
              onTap: () => onTip('5'),
            ),
            PosChoiceChip(
              label: '10% · ${formatRupees(tip10)}',
              selected: tipChoice == '10',
              minHeight: 48,
              onTap: () => onTip('10'),
            ),
            PosChoiceChip(
              label: 'Custom',
              selected: tipChoice == 'custom',
              minHeight: 48,
              onTap: () => onTip('custom'),
            ),
          ],
        ),
        if (tipChoice == 'custom') ...[
          SizedBox(height: t.spacing.sm),
          AppTextField(
            label: 'Tip amount (₹)',
            controller: customTip,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onChanged(),
          ),
        ],
        SizedBox(height: t.spacing.lg),
        Text('Payments', style: TextStyle(color: t.color.content.secondary)),
        SizedBox(height: t.spacing.xs),
        _TenderRow(
          label: 'Cash',
          detail: cash.isEmpty ? 'Use the keypad' : 'Received ${formatRupees(parseRupeeInput(cash))}',
          selected: cash.isNotEmpty,
          onTap: null,
        ),
        _TenderRow(
          label: 'UPI',
          detail: useUpi ? 'Reference below' : 'Off',
          selected: useUpi,
          onTap: onUpi,
        ),
        if (useUpi) ...[
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'UPI amount (₹)',
                  controller: upiAmount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => onChanged(),
                ),
              ),
              SizedBox(width: t.spacing.sm),
              Expanded(
                child: AppTextField(label: 'UPI reference', controller: upiRef),
              ),
            ],
          ),
        ],
        _TenderRow(
          label: 'Card terminal',
          detail: useCard ? 'Ready' : 'Off',
          selected: useCard,
          onTap: onCard,
        ),
        SizedBox(height: t.spacing.md),
        if (plan.changeToGive > 0)
          _Line(
            label: 'Change to give',
            value: formatRupees(plan.changeToGive, alwaysPaise: true),
            strong: true,
          ),
        if (!plan.isCovered && plan.due > 0)
          _Line(
            label: 'Still to pay',
            value: formatRupees(plan.remaining, alwaysPaise: true),
          ),
        SizedBox(height: t.spacing.md),
        _Keypad(
          quick: quickCashAmounts,
          onKey: onKey,
          onQuick: onQuick,
          onExact: onExact,
        ),
        SizedBox(height: t.spacing.md),
        if (offline)
          const InlineAlert(
            message: "Payments can't be taken offline. Reconnect to complete.",
            tone: StatusTone.warning,
          ),
        if (payError != null) InlineAlert(message: payError!),
        SizedBox(height: t.spacing.sm),
        AppButton(
          label: completeLabel,
          variant: AppButtonVariant.primary,
          loading: paying,
          onPressed: canComplete ? onComplete : null,
        ),
        SizedBox(height: t.spacing.xs),
        Text(
          'The cash drawer opens on Complete.',
          style: TextStyle(color: t.color.content.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.strong = false});

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

class _TenderRow extends StatelessWidget {
  const _TenderRow({required this.label, required this.detail, required this.selected, this.onTap});

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.xs),
      child: Material(
        color: selected ? t.color.background.surface : t.color.background.raised,
        borderRadius: BorderRadius.circular(t.radius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radius.md),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: EdgeInsets.symmetric(horizontal: t.spacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius.md),
              border: Border.all(
                color: selected ? t.color.border.accent : t.color.border.default,
                width: t.borderWidth.hairline,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? t.color.content.primary : t.color.content.muted,
                ),
                SizedBox(width: t.spacing.sm),
                Expanded(
                  child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: t.color.content.primary)),
                ),
                Text(detail, style: TextStyle(color: t.color.content.secondary, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.quick, required this.onKey, required this.onQuick, required this.onExact});

  final List<int> quick;
  final ValueChanged<String> onKey;
  final ValueChanged<int> onQuick;
  final VoidCallback onExact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', '⌫'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: t.spacing.sm,
          runSpacing: t.spacing.sm,
          children: [
            for (final q in quick)
              PosChoiceChip(
                label: formatRupees(q),
                selected: false,
                minHeight: 48,
                onTap: () => onQuick(q),
              ),
            PosChoiceChip(label: 'Exact', selected: false, minHeight: 48, onTap: onExact),
          ],
        ),
        SizedBox(height: t.spacing.sm),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: t.spacing.sm,
          crossAxisSpacing: t.spacing.sm,
          childAspectRatio: 2.2,
          children: [
            for (final k in keys)
              Material(
                color: t.color.background.surface,
                borderRadius: BorderRadius.circular(t.radius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(t.radius.md),
                  onTap: () => onKey(k),
                  child: Center(
                    child: Text(
                      k,
                      style: TextStyle(fontSize: 20, color: t.color.content.primary),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
