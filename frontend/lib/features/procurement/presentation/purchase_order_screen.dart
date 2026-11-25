import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../../inventory/data/inventory_models.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/data/json_read.dart';
import '../../inventory/domain/periods.dart';
import '../../inventory/presentation/inventory_messages.dart';
import '../../pos/presentation/pos_format.dart';
import '../data/procurement_models.dart';
import '../data/procurement_repository.dart';

/// One purchase order by id (`GET /purchase-orders/:id`).
final purchaseOrderProvider = FutureProvider.family<PoView, String>(
  (ref, id) => ref.watch(procurementRepositoryProvider).purchaseOrder(id),
);

/// Purchase order editor (Procurement board, "Purchase order PO-0318").
/// `id` is `new` to create one.
class PurchaseOrderScreen extends ConsumerStatefulWidget {
  const PurchaseOrderScreen({super.key, required this.poId});

  final String poId;

  bool get isNew => poId == 'new';

  @override
  ConsumerState<PurchaseOrderScreen> createState() => _PurchaseOrderScreenState();
}

class _Line {
  _Line({this.stockItemId, String qty = '', String rate = ''})
      : qty = TextEditingController(text: qty),
        rate = TextEditingController(text: rate);

  String? stockItemId;
  final TextEditingController qty;
  final TextEditingController rate;

  num get qtyValue => num.tryParse(qty.text.trim()) ?? 0;
  num get rateValue => num.tryParse(rate.text.trim()) ?? 0;

  void dispose() {
    qty.dispose();
    rate.dispose();
  }
}

class _PurchaseOrderScreenState extends ConsumerState<PurchaseOrderScreen> {
  bool _initialised = false;
  String? _vendorId;
  String? _locationId;
  DateTime? _due;
  final _permit = TextEditingController();
  final _note = TextEditingController();
  final _lines = <_Line>[];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _permit.dispose();
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _load(PoView po) {
    _vendorId = po.summary.vendor?.id;
    _locationId = po.summary.location?.id;
    _due = po.summary.dueDate;
    _permit.text = po.transportPermitNo ?? '';
    _note.text = po.note ?? '';
    for (final l in _lines) {
      l.dispose();
    }
    _lines
      ..clear()
      ..addAll([
        for (final line in po.lines)
          _Line(stockItemId: line.stockItemId, qty: _plain(decimalValue(line.qty)), rate: _plain(decimalValue(line.rate))),
      ]);
    _initialised = true;
  }

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  bool _editable(PoView? po) =>
      widget.isNew || po == null || po.status == PoStatus.draft || po.status == PoStatus.pendingApproval;

  num get _total => _lines.fold<num>(0, (sum, l) => sum + l.qtyValue * l.rateValue);

  Map<String, dynamic> _body() => {
        'vendorId': _vendorId,
        'locationId': _locationId,
        'dueDate': _due == null ? null : wireDay(_due!),
        'transportPermitNo': _permit.text.trim().isEmpty ? null : _permit.text.trim(),
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'lines': [
          for (final l in _lines)
            if (l.stockItemId != null && l.qtyValue > 0)
              {'stockItemId': l.stockItemId, 'qty': l.qtyValue, 'rate': l.rateValue},
        ],
      };

  /// Runs one server call, shows the result, and refreshes the PO.
  Future<void> _run(Future<PoView?> Function(ProcurementRepository repo) call, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final po = await call(ref.read(procurementRepositoryProvider));
      ref.invalidate(purchaseOrdersProvider);
      if (po != null) {
        ref.invalidate(purchaseOrderProvider(po.id));
        if (widget.isNew && mounted) {
          context.go('/procurement/po/${po.id}');
          return;
        }
      }
      if (mounted) showAppToast(context, done);
    } catch (e) {
      if (mounted) setState(() => _error = inventoryErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_lines.every((l) => l.stockItemId == null)) {
      setState(() => _error = 'Add at least one line first.');
      return;
    }
    if (_vendorId == null || _locationId == null) {
      setState(() => _error = 'Pick a vendor and where the goods are delivered.');
      return;
    }
    await _run((repo) async {
      if (widget.isNew) return repo.createPurchaseOrder(_body());
      return repo.updatePurchaseOrder(widget.poId, _body());
    }, 'Draft saved');
  }

  Future<void> _addFromReorder() async {
    final picked = await showDialog<List<ReorderSuggestion>>(
      context: context,
      builder: (_) => _ReorderPicker(vendorId: _vendorId),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      for (final s in picked) {
        _lines.add(_Line(
          stockItemId: s.stockItemId,
          qty: '${s.suggestedQty}',
          rate: s.rate == 0 ? '' : _plain(s.rate),
        ));
      }
    });
  }

  Future<void> _cancel() async {
    final reason = await _askReason(context);
    if (reason == null || !mounted) return;
    await _run((repo) => repo.cancelPurchaseOrder(widget.poId, reason), 'Purchase order cancelled');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canRequest = can(ref, Perm.stockPurchaseOrders, AccessLevel.request);
    final canApprove = can(ref, Perm.stockPurchaseOrders, AccessLevel.approve);
    final vendors = ref.watch(procurementVendorsProvider).valueOrNull ?? const <VendorView>[];
    final locations = ref.watch(inventoryLocationsProvider).valueOrNull ?? const <LocationView>[];
    final items = ref.watch(stockItemsProvider((locationId: null, status: null, liquor: false))).valueOrNull ??
        const <StockItemRow>[];

    final AsyncValue<PoView>? async = widget.isNew ? null : ref.watch(purchaseOrderProvider(widget.poId));
    final po = async?.valueOrNull;
    if (po != null && !_initialised) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_initialised) setState(() => _load(po));
      });
    }
    if (widget.isNew && !_initialised) _initialised = true;

    final editable = _editable(po) && canRequest;
    final title = widget.isNew ? 'New purchase order' : (po?.summary.number ?? 'Purchase order');

    Widget body;
    if (async != null && !async.hasValue) {
      body = async.hasError
          ? ErrorState(
              message: ApiError.from(async.error!).message,
              onRetry: () => ref.invalidate(purchaseOrderProvider(widget.poId)),
            )
          : DelayedSkeleton(child: SkeletonList());
    } else {
      body = LayoutBuilder(builder: (context, constraints) {
        final half = constraints.maxWidth >= 720 ? (constraints.maxWidth - t.spacing.md) / 2 : constraints.maxWidth;
        Widget field(Widget child) => SizedBox(width: half, child: child);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (po != null) ...[
              Row(
                children: [
                  StatusBadge(label: PoStatus.label(po.status), tone: StatusTone.info),
                  SizedBox(width: t.spacing.md),
                  Expanded(
                    child: Text(
                      po.grns.isEmpty ? '' : 'Receipts: ${po.grns.map((g) => g.number).join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.spacing.md),
            ],
            AppCard(
              title: 'Delivery details',
              child: Wrap(
                spacing: t.spacing.md,
                runSpacing: t.spacing.md,
                children: [
                  field(AppSelect<String>(
                    label: 'Vendor',
                    value: _vendorId,
                    items: [for (final v in vendors) AppSelectItem(v.id, v.name)],
                    onChanged: editable ? (v) => setState(() => _vendorId = v) : (_) {},
                  )),
                  field(AppSelect<String>(
                    label: 'Deliver to',
                    value: _locationId,
                    items: [for (final l in locations) AppSelectItem(l.id, l.name)],
                    onChanged: editable ? (v) => setState(() => _locationId = v) : (_) {},
                  )),
                  field(_dueField(context, editable)),
                  field(AppTextField(
                    label: 'Transport permit no.',
                    controller: _permit,
                    helperText: 'Needed for liquor deliveries',
                  )),
                  field(AppTextField(label: 'Note', controller: _note)),
                ],
              ),
            ),
            SizedBox(height: t.spacing.md),
            AppCard(
              title: 'Line items',
              actions: [
                if (editable)
                  AppButton(
                    label: 'Add from reorder list',
                    icon: Icons.replay,
                    size: AppControlSize.sm,
                    onPressed: _addFromReorder,
                  ),
                if (editable)
                  AppButton(
                    label: 'Add line',
                    icon: Icons.add,
                    size: AppControlSize.sm,
                    onPressed: () => setState(() => _lines.add(_Line(qty: '1'))),
                  ),
              ],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _lines.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: t.spacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: AppSelect<String>(
                              label: 'Item ${i + 1}',
                              value: _lines[i].stockItemId,
                              items: [for (final s in items) AppSelectItem(s.id, s.name)],
                              onChanged: editable ? (v) => setState(() => _lines[i].stockItemId = v) : (_) {},
                            ),
                          ),
                          SizedBox(width: t.spacing.sm),
                          Expanded(
                            flex: 2,
                            child: AppTextField(
                              label: 'Qty',
                              controller: _lines[i].qty,
                              keyboardType: TextInputType.number,
                              onChanged: editable ? (_) => setState(() {}) : null,
                            ),
                          ),
                          SizedBox(width: t.spacing.sm),
                          Expanded(
                            flex: 2,
                            child: AppTextField(
                              label: 'Rate ₹',
                              controller: _lines[i].rate,
                              keyboardType: TextInputType.number,
                              onChanged: editable ? (_) => setState(() {}) : null,
                            ),
                          ),
                          SizedBox(width: t.spacing.sm),
                          SizedBox(
                            width: 100,
                            child: Text(
                              formatRupees(_lines[i].qtyValue * _lines[i].rateValue),
                              textAlign: TextAlign.right,
                            ),
                          ),
                          if (editable)
                            AppIconButton(
                              icon: Icons.delete_outline,
                              tooltip: 'Remove line ${i + 1}',
                              onPressed: () => setState(() => _lines.removeAt(i).dispose()),
                            ),
                        ],
                      ),
                    ),
                  if (_lines.isEmpty)
                    Text('No lines yet.', style: Theme.of(context).textTheme.bodySmall),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total ${formatRupees(_total)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            if (po != null && po.summary.total != '0.00') ...[
              SizedBox(height: t.spacing.sm),
              Text(
                'Saved total ${formatWire(po.summary.total)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      });
    }

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: title,
              breadcrumb: 'Procurement',
              actions: [
                AppButton(
                  label: 'Back to procurement',
                  icon: Icons.arrow_back,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => context.go('/procurement'),
                ),
              ],
            ),
            if (_error != null) ...[
              SizedBox(height: t.spacing.sm),
              InlineAlert(message: _error!),
            ],
            SizedBox(height: t.spacing.md),
            Expanded(child: SingleChildScrollView(child: body)),
            SizedBox(height: t.spacing.md),
            _actionBar(context, po, canRequest, canApprove, editable),
          ],
        ),
      ),
    );
  }

  Widget _dueField(BuildContext context, bool editable) {
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Delivery date', border: OutlineInputBorder()),
      child: Row(
        children: [
          Expanded(child: Text(_due == null ? 'Not set' : shortDay(_due))),
          if (editable)
            TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _due ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _due = picked);
              },
              child: const Text('Pick'),
            ),
        ],
      ),
    );
  }

  Widget _actionBar(BuildContext context, PoView? po, bool canRequest, bool canApprove, bool editable) {
    final t = context.tokens;
    final status = po?.status ?? PoStatus.draft;
    final buttons = <Widget>[];

    if (widget.isNew || status == PoStatus.draft || status == PoStatus.pendingApproval) {
      if (canRequest && editable) {
        buttons.add(AppButton(
          label: 'Save draft',
          loading: _busy,
          onPressed: _busy ? null : _save,
        ));
      }
    }
    if (!widget.isNew && status == PoStatus.draft && canRequest) {
      buttons.add(AppButton(
        label: 'Delete draft',
        variant: AppButtonVariant.danger,
        onPressed: _busy
            ? null
            : () async {
                final ok = await showConfirmDialog(
                  context,
                  title: 'Delete this draft?',
                  message: 'The draft is removed. Nothing has been sent to the vendor.',
                  confirmLabel: 'Delete',
                  destructive: true,
                );
                if (!ok) return;
                await _run((repo) async {
                  await repo.deletePurchaseOrder(widget.poId);
                  return null;
                }, 'Draft deleted');
                if (mounted) context.go('/procurement');
              },
      ));
    }
    if (!widget.isNew && (status == PoStatus.draft) && canRequest) {
      buttons.add(AppButton(
        label: 'Submit for approval',
        onPressed: _busy ? null : () => _run((repo) => repo.submitPurchaseOrder(widget.poId), 'Sent for approval'),
      ));
    }
    if (!widget.isNew && canApprove && (status == PoStatus.draft || status == PoStatus.pendingApproval)) {
      buttons.add(AppButton(
        label: 'Approve',
        variant: AppButtonVariant.primary,
        onPressed: _busy ? null : () => _run((repo) => repo.approvePurchaseOrder(widget.poId), 'Approved'),
      ));
    }
    if (!widget.isNew && canApprove && (status == PoStatus.approved || status == PoStatus.draft || status == PoStatus.pendingApproval)) {
      buttons.add(AppButton(
        label: 'Send to vendor',
        variant: AppButtonVariant.primary,
        onPressed: _busy ? null : () => _run((repo) => repo.sendPurchaseOrder(widget.poId), 'Sent to vendor'),
      ));
    }
    if (!widget.isNew && canRequest && (status == PoStatus.sent || status == PoStatus.partlyReceived)) {
      buttons.add(AppButton(
        label: status == PoStatus.partlyReceived ? 'Receive rest' : 'Receive',
        variant: AppButtonVariant.primary,
        onPressed: () => context.go('/procurement/grn/new?poId=${widget.poId}'),
      ));
    }
    if (!widget.isNew && canApprove && status != PoStatus.received && status != PoStatus.cancelled) {
      buttons.add(AppButton(
        label: 'Cancel PO',
        variant: AppButtonVariant.danger,
        onPressed: _busy ? null : _cancel,
      ));
    }

    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: t.spacing.sm,
      runSpacing: t.spacing.sm,
      children: buttons,
    );
  }
}

/// Asks for a cancellation reason. Null when the user backs out.
Future<String?> _askReason(BuildContext context) async {
  final controller = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Cancel this purchase order?'),
      content: AppTextField(label: 'Reason', controller: controller, autofocus: true),
      actions: [
        AppButton(
          label: 'Keep it',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        AppButton(
          label: 'Cancel PO',
          variant: AppButtonVariant.danger,
          onPressed: () {
            final text = controller.text.trim();
            if (text.isEmpty) return;
            Navigator.of(dialogContext).pop(text);
          },
        ),
      ],
    ),
  );
  controller.dispose();
  return reason;
}

/// Picks reorder suggestions to add as PO lines. Filters to the vendor when one
/// is chosen on the PO.
class _ReorderPicker extends ConsumerStatefulWidget {
  const _ReorderPicker({this.vendorId});

  final String? vendorId;

  @override
  ConsumerState<_ReorderPicker> createState() => _ReorderPickerState();
}

class _ReorderPickerState extends ConsumerState<_ReorderPicker> {
  final _picked = <String>{};

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(reorderSuggestionsProvider(null));
    final all = async.valueOrNull ?? const <ReorderSuggestion>[];
    final rows = [
      for (final s in all)
        if (widget.vendorId == null || s.vendor?.id == widget.vendorId) s,
    ];
    return AlertDialog(
      title: const Text('Add from reorder list'),
      content: SizedBox(
        width: 480,
        child: async.hasError
            ? InlineAlert(message: ApiError.from(async.error!).message)
            : rows.isEmpty
                ? Text(async.isLoading ? 'Loading...' : 'Nothing below par for this vendor.')
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final s in rows)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(s.name),
                            subtitle: Text('${s.suggestedQty} ${s.purchaseUnitName} · ${s.locationName}'),
                            value: _picked.contains(s.stockItemId),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _picked.add(s.stockItemId);
                              } else {
                                _picked.remove(s.stockItemId);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Add lines',
          variant: AppButtonVariant.primary,
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.of(context).pop([
                    for (final s in rows)
                      if (_picked.contains(s.stockItemId)) s,
                  ]),
        ),
      ],
    );
  }
}
