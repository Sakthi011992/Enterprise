import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/auth/permission_keys.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/ui/ui.dart';
import '../../data/pos_models.dart';
import '../../data/pos_repository.dart';
import '../pos_format.dart';
import 'dialog_frame.dart';
import 'manager_pin_dialog.dart';

/// Reasons offered as chips. The reason is required.
const discountReasons = ['Regular guest', 'Service delay', 'Staff meal'];

/// Percent-equivalent of a discount, used to compare with the user's limit.
/// For a flat amount it is the amount over the base, times 100.
double discountPercentEquivalent({
  required bool percent,
  required double value,
  required double base,
}) {
  if (percent) return value;
  if (base <= 0) return 0;
  return value / base * 100;
}

/// True when the server would send this discount to a manager (PLAN 1.4
/// POST /orders/:id/discounts). APPROVE and EDIT apply directly, LIMITED applies
/// up to its limit, and anything lower needs approval.
bool discountNeedsApproval({
  required AccessLevel level,
  required double percentEquivalent,
  required num? limit,
}) {
  if (level.atLeast(AccessLevel.approve)) return false;
  if (level == AccessLevel.limited) {
    return percentEquivalent > (limit ?? 0);
  }
  return true;
}

/// Opens the discount sheet for [order]. Resolves to the updated order when the
/// discount is applied, or null when dismissed.
Future<OrderView?> showDiscountDialog(BuildContext context, {required OrderView order}) {
  return showDialog<OrderView>(
    context: context,
    builder: (_) => DiscountDialog(order: order),
  );
}

class DiscountDialog extends ConsumerStatefulWidget {
  const DiscountDialog({super.key, required this.order});

  final OrderView order;

  @override
  ConsumerState<DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends ConsumerState<DiscountDialog> {
  bool _percent = true;
  final _value = TextEditingController();
  bool _wholeBill = true;
  final Set<String> _selectedItemIds = {};
  String? _reason;
  bool _busy = false;
  String? _error;

  /// Shown after the server or the local check says a manager must approve.
  bool _needsManager = false;

  /// Phone approval in progress.
  String? _pendingApprovalId;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    _value.dispose();
    super.dispose();
  }

  /// Non-liquor lines with a price. Liquor is never discounted.
  List<OrderItemView> get _eligible => [
        for (final i in widget.order.liveItems)
          if (!i.isLiquor && i.grossValue > 0) i,
      ];

  double get _base {
    final lines = _wholeBill
        ? _eligible
        : _eligible.where((i) => _selectedItemIds.contains(i.id)).toList();
    return lines.fold<double>(0, (sum, i) => sum + i.grossValue.toDouble());
  }

  double get _enteredValue => parseRupeeInput(_value.text);

  double get _percentEquivalent => discountPercentEquivalent(
        percent: _percent,
        value: _enteredValue,
        base: _base,
      );

  double get _amount {
    if (_percent) return _base * _enteredValue / 100;
    return _enteredValue < _base ? _enteredValue : _base;
  }

  DiscountInput _input({String? approvalId}) => DiscountInput(
        type: _percent ? 'PERCENT' : 'FLAT',
        value: wireMoney(_enteredValue),
        itemIds: _wholeBill ? const [] : _selectedItemIds.toList(),
        reason: _reason ?? '',
        approvalId: approvalId,
      );

  /// Local preview of whether a manager is needed. The server still decides.
  bool _requiresManager(AccessLevel level, num? limit) => discountNeedsApproval(
        level: level,
        percentEquivalent: _percentEquivalent,
        limit: limit,
      );

  String? _validate() {
    if (_enteredValue <= 0) return 'Enter a discount above zero.';
    if (_reason == null) return 'Pick a reason.';
    if (!_wholeBill && _selectedItemIds.isEmpty) return 'Pick at least one item.';
    if (_base <= 0) return 'There is nothing to discount on this selection.';
    return null;
  }

  Future<void> _applyDirect() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    await _send(null);
  }

  Future<void> _send(String? approvalId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await ref.read(posRepositoryProvider).addDiscount(
            widget.order.id,
            _input(approvalId: approvalId),
          );
      if (!mounted) return;
      Navigator.of(context).pop(order);
    } catch (e) {
      if (!mounted) return;
      final err = ApiError.from(e);
      setState(() {
        _busy = false;
        if (err.code == 'APPROVAL_REQUIRED') {
          _needsManager = true;
          _error = 'A manager must approve this discount.';
        } else {
          _error = err.message;
        }
      });
    }
  }

  Future<void> _managerPin() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final approval = await showManagerPinDialog(
      context,
      type: ApprovalTypes.discount,
      orderId: widget.order.id,
      payload: _input().toApprovalPayload(),
      reason: _reason!,
      title: 'Manager approves the discount',
    );
    if (!mounted || approval == null || !approval.isApproved) return;
    await _send(approval.id);
  }

  Future<void> _sendToPhone() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final input = _input();
      final approval = await ref.read(posRepositoryProvider).createApproval(
            ApprovalRequest(
              type: ApprovalTypes.discount,
              orderId: widget.order.id,
              payload: input.toApprovalPayload(),
              reason: _reason!,
            ),
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pendingApprovalId = approval.id;
      });
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _checkApproval(approval.id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = ApiError.from(e).message;
      });
    }
  }

  Future<void> _checkApproval(String approvalId) async {
    try {
      final approval = await ref.read(posRepositoryProvider).approval(approvalId);
      if (!mounted) return;
      if (approval.isApproved) {
        _poll?.cancel();
        await _send(approval.id);
      } else if (approval.isFinal) {
        _poll?.cancel();
        setState(() {
          _pendingApprovalId = null;
          _error = approval.status == ApprovalStatuses.declined
              ? 'The manager declined this discount.'
              : 'The approval request expired. Send it again.';
        });
      }
    } catch (e) {
      // A failed poll is retried on the next tick. Nothing to show yet.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final session = ref.watch(sessionProvider.select((s) => s.session));
    final perm = session?.permissions[Perm.salesDiscountGive];
    final level = session?.levelOf(Perm.salesDiscountGive) ?? AccessLevel.none;
    final limit = perm?.limit;
    final needsManager = _needsManager || _requiresManager(level, limit);
    final waiting = _pendingApprovalId != null;

    return PosDialogFrame(
      title: 'Discount',
      subtitle: 'Order ${widget.order.orderNumber} · liquor is excluded by law',
      actions: [
        AppButton(
          label: waiting ? 'Close' : 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (!waiting && !needsManager)
          AppButton(
            label: 'Apply discount',
            variant: AppButtonVariant.primary,
            loading: _busy,
            onPressed: _busy ? null : _applyDirect,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.sm,
            children: [
              PosChoiceChip(
                label: 'Percent',
                selected: _percent,
                onTap: waiting ? null : () => setState(() => _percent = true),
              ),
              PosChoiceChip(
                label: 'Flat ₹',
                selected: !_percent,
                onTap: waiting ? null : () => setState(() => _percent = false),
              ),
            ],
          ),
          SizedBox(height: t.spacing.md),
          AppTextField(
            label: _percent ? 'Discount (%)' : 'Discount (₹)',
            controller: _value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {
              _error = null;
              _needsManager = false;
            }),
          ),
          if (_percent) ...[
            SizedBox(height: t.spacing.sm),
            Wrap(
              spacing: t.spacing.sm,
              runSpacing: t.spacing.sm,
              children: [
                for (final q in const ['5', '10', '20'])
                  PosChoiceChip(
                    label: '$q%',
                    selected: _value.text == q,
                    onTap: waiting
                        ? null
                        : () => setState(() {
                              _value.text = q;
                              _error = null;
                            }),
                  ),
              ],
            ),
          ],
          SizedBox(height: t.spacing.md),
          Text('Apply to', style: TextStyle(color: t.color.content.secondary)),
          SizedBox(height: t.spacing.xs),
          Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.sm,
            children: [
              PosChoiceChip(
                label: 'Whole bill',
                selected: _wholeBill,
                onTap: waiting ? null : () => setState(() => _wholeBill = true),
              ),
              PosChoiceChip(
                label: 'Selected items',
                selected: !_wholeBill,
                onTap: waiting ? null : () => setState(() => _wholeBill = false),
              ),
            ],
          ),
          if (!_wholeBill) ...[
            SizedBox(height: t.spacing.sm),
            for (final item in widget.order.liveItems)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.name),
                subtitle: Text(
                  item.isLiquor
                      ? "Liquor can't be discounted"
                      : formatWire(item.gross),
                ),
                value: _selectedItemIds.contains(item.id),
                onChanged: (item.isLiquor || waiting)
                    ? null
                    : (v) => setState(() {
                          if (v == true) {
                            _selectedItemIds.add(item.id);
                          } else {
                            _selectedItemIds.remove(item.id);
                          }
                        }),
              ),
          ],
          SizedBox(height: t.spacing.md),
          Text('Reason', style: TextStyle(color: t.color.content.secondary)),
          SizedBox(height: t.spacing.xs),
          Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.sm,
            children: [
              for (final r in discountReasons)
                PosChoiceChip(
                  label: r,
                  selected: _reason == r,
                  onTap: waiting ? null : () => setState(() => _reason = r),
                ),
            ],
          ),
          SizedBox(height: t.spacing.md),
          Text(
            'Discount ${formatRupees(_amount, alwaysPaise: true)} on ${formatRupees(_base, alwaysPaise: true)}',
            style: TextStyle(color: t.color.content.secondary),
          ),
          if (_error != null) ...[
            SizedBox(height: t.spacing.sm),
            InlineAlert(message: _error!),
          ],
          if (!waiting && needsManager && _enteredValue > 0) ...[
            SizedBox(height: t.spacing.sm),
            AppBanner(
              tone: StatusTone.warning,
              message: _managerMessage(level, limit),
            ),
            SizedBox(height: t.spacing.sm),
            AppButton(
              label: 'Manager enters PIN here',
              variant: AppButtonVariant.primary,
              onPressed: _busy ? null : _managerPin,
            ),
            SizedBox(height: t.spacing.sm),
            AppButton(
              label: "Send to manager's phone",
              onPressed: _busy ? null : _sendToPhone,
            ),
          ],
          if (waiting) ...[
            SizedBox(height: t.spacing.md),
            InlineAlert(
              tone: StatusTone.info,
              message: "Sent to the manager's phone. Waiting for approval… "
                  'You can keep taking orders.',
            ),
          ],
        ],
      ),
    );
  }

  String _managerMessage(AccessLevel level, num? limit) {
    final pct = formatPercent(_percentEquivalent);
    if (level == AccessLevel.limited && limit != null) {
      return '$pct% is above your ${formatPercent(limit)}% limit. A manager must approve.';
    }
    return 'A manager must approve this discount.';
  }
}

/// Whole numbers without a decimal point, otherwise one decimal.
String formatPercent(num value) {
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}
