import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/files/pick_file.dart';
import '../../../core/ui/ui.dart';
import '../../inventory/data/inventory_models.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/data/json_read.dart';
import '../../inventory/domain/periods.dart';
import '../../inventory/presentation/inventory_messages.dart';
import '../../inventory/presentation/stock_item_editor_screen.dart';
import '../../pos/presentation/pos_format.dart';
import '../data/procurement_models.dart';
import '../data/procurement_repository.dart';
import '../domain/grn_math.dart';
import 'purchase_order_screen.dart';

/// Goods receipt (GRN and TabletOps "Receive a delivery"). `grnId` is `new`
/// to start one; `poId` pre-fills the lines from that PO's outstanding quantity.
class GrnScreen extends ConsumerStatefulWidget {
  const GrnScreen({super.key, required this.grnId, this.poId});

  final String grnId;
  final String? poId;

  bool get isNew => grnId == 'new';

  @override
  ConsumerState<GrnScreen> createState() => _GrnScreenState();
}

/// One editable line. Owns its controllers.
class _GLine {
  _GLine({
    this.poLineId,
    required this.stockItemId,
    required this.name,
    required this.purchaseUnitName,
    String ordered = '0',
    String invoiced = '0',
    String received = '0',
    String damaged = '0',
    String rate = '0',
    String batch = '',
    String expiry = '',
  })  : ordered = TextEditingController(text: ordered),
        invoiced = TextEditingController(text: invoiced),
        received = TextEditingController(text: received),
        damaged = TextEditingController(text: damaged),
        rate = TextEditingController(text: rate),
        batch = TextEditingController(text: batch),
        expiry = TextEditingController(text: expiry);

  final String? poLineId;
  final String stockItemId;
  final String name;
  String purchaseUnitName;

  final TextEditingController ordered;
  final TextEditingController invoiced;
  final TextEditingController received;
  final TextEditingController damaged;
  final TextEditingController rate;
  final TextEditingController batch;
  final TextEditingController expiry;

  static num _n(TextEditingController c) => num.tryParse(c.text.trim()) ?? 0;

  num get orderedQty => _n(ordered);
  num get invoicedQty => _n(invoiced);
  num get receivedQty => _n(received);
  num get damagedQty => _n(damaged);
  num get rateValue => _n(rate);

  bool get hasNegative =>
      orderedQty < 0 || invoicedQty < 0 || receivedQty < 0 || damagedQty < 0;

  GrnLine toLine() => GrnLine(
        poLineId: poLineId,
        stockItemId: stockItemId,
        name: name,
        purchaseUnitName: purchaseUnitName,
        orderedQty: orderedQty,
        invoicedQty: invoicedQty,
        receivedQty: receivedQty,
        damagedQty: damagedQty,
        rate: rateValue,
        batch: batch.text.trim().isEmpty ? null : batch.text.trim(),
        expiry: expiry.text.trim().isEmpty ? null : expiry.text.trim(),
      );

  void dispose() {
    for (final c in [ordered, invoiced, received, damaged, rate, batch, expiry]) {
      c.dispose();
    }
  }
}

class _GrnScreenState extends ConsumerState<GrnScreen> {
  GrnView? _grn;
  bool _loading = false;
  bool _busy = false;
  bool _started = false;
  String? _error;
  String? _fieldError;
  Map<String, String?> _lineErrors = {};

  String? _vendorId;
  String? _locationId;
  String? _poId;
  DateTime _receivedOn = DateTime.now();
  final _invoiceNo = TextEditingController();
  final _invoiceValue = TextEditingController();
  final _permit = TextEditingController();
  String? _photoUrl;
  String? _photoName;
  bool _uploading = false;
  final _lines = <_GLine>[];

  @override
  void initState() {
    super.initState();
    _poId = widget.poId;
    if (widget.isNew && widget.poId != null) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startFromPo(widget.poId!));
    } else if (!widget.isNew) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
    } else {
      _started = true;
    }
  }

  @override
  void dispose() {
    _invoiceNo.dispose();
    _invoiceValue.dispose();
    _permit.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _startFromPo(String poId) async {
    if (_started) return;
    _started = true;
    setState(() => _busy = true);
    try {
      final g = await ref.read(procurementRepositoryProvider).createGrn({'poId': poId});
      if (mounted) context.go('/procurement/grn/${g.id}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _busy = false;
          _error = inventoryErrorText(e);
        });
      }
    }
  }

  Future<void> _loadExisting() async {
    try {
      final g = await ref.read(procurementRepositoryProvider).grn(widget.grnId);
      if (mounted) _apply(g);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = inventoryErrorText(e);
        });
      }
    }
  }

  void _apply(GrnView g) {
    for (final l in _lines) {
      l.dispose();
    }
    _grn = g;
    _vendorId = g.summary.vendor?.id;
    _locationId = g.summary.location?.id;
    _poId = g.poId;
    _receivedOn = g.summary.receivedOn ?? DateTime.now();
    _invoiceNo.text = g.vendorInvoiceNo ?? '';
    _invoiceValue.text = g.summary.invoiceValue == '0.00' ? '' : g.summary.invoiceValue;
    _permit.text = g.transportPermitNo ?? '';
    _photoUrl = g.invoicePhotoUrl;
    _photoName = g.invoicePhotoUrl == null ? null : 'Invoice photo';
    _lines
      ..clear()
      ..addAll([for (final l in g.lines) _lineFrom(l)]);
    _loading = false;
    _busy = false;
    _started = true;
    setState(() {});
  }

  static _GLine _lineFrom(GrnLine l) => _GLine(
        poLineId: l.poLineId,
        stockItemId: l.stockItemId,
        name: l.name,
        purchaseUnitName: l.purchaseUnitName,
        ordered: _plain(l.orderedQty),
        invoiced: _plain(l.invoicedQty),
        received: _plain(l.receivedQty),
        damaged: _plain(l.damagedQty),
        rate: _plain(l.rate),
        batch: l.batch ?? '',
        expiry: l.expiry ?? '',
      );

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  bool get _editable => widget.isNew || _grn == null || _grn!.status == GrnStatuses.draft;

  /// Checks the form before saving or posting. Fills inline errors.
  bool _validate({required bool forPost}) {
    final lineErrors = <String, String?>{};
    for (var i = 0; i < _lines.length; i++) {
      if (_lines[i].hasNegative) lineErrors['line$i'] = 'Must be 0 or more';
    }
    final problems = <String>[];
    if (_lines.isEmpty) problems.add('Add the lines that arrived.');
    if (forPost && _invoiceNo.text.trim().isEmpty) problems.add('Enter the vendor invoice number.');
    setState(() {
      _lineErrors = lineErrors;
      _fieldError = problems.isEmpty ? null : problems.join(' ');
    });
    return lineErrors.isEmpty && problems.isEmpty;
  }

  Map<String, dynamic> _body() => {
        'vendorId': _vendorId,
        'locationId': _locationId,
        'poId': _poId,
        'vendorInvoiceNo': _invoiceNo.text.trim().isEmpty ? null : _invoiceNo.text.trim(),
        'receivedOn': wireDay(_receivedOn),
        'transportPermitNo': _permit.text.trim().isEmpty ? null : _permit.text.trim(),
        'invoicePhotoUrl': _photoUrl,
        'invoiceValue': num.tryParse(_invoiceValue.text.trim()),
        'lines': [for (final l in _lines) l.toLine().toJson()],
      }..removeWhere((k, v) => v == null && k != 'lines');

  Future<void> _saveDraft({required bool post}) async {
    if (!_validate(forPost: post)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(procurementRepositoryProvider);
    try {
      // PUT takes the POST body without poId (PLAN 1.7).
      final body = _body();
      var g = _grn == null
          ? await repo.createGrn(body)
          : await repo.updateGrn(_grn!.id, body..remove('poId'));
      if (post) g = await repo.postGrn(g.id);
      ref.invalidate(goodsReceivedProvider);
      ref.invalidate(purchaseOrdersProvider);
      if (_poId != null) ref.invalidate(purchaseOrderProvider(_poId!));
      if (!mounted) return;
      if (post) {
        showAppToast(context, '${g.summary.number} posted');
        context.go('/procurement');
      } else if (_grn == null) {
        context.go('/procurement/grn/${g.id}');
      } else {
        _apply(g);
        showAppToast(context, 'Draft saved');
      }
    } catch (e) {
      if (mounted) setState(() => _error = inventoryErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await pickImageFile(allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf']);
    if (picked == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await ref.read(inventoryRepositoryProvider).uploadFile(picked);
      if (mounted) {
        setState(() {
          _photoUrl = url;
          _photoName = picked.name;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = inventoryErrorText(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickReceivedOn() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _receivedOn,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _receivedOn = picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canRequest = can(ref, Perm.stockPurchaseOrders, AccessLevel.request);
    final locations = ref.watch(inventoryLocationsProvider).valueOrNull ?? const <LocationView>[];
    final vendors = ref.watch(procurementVendorsProvider).valueOrNull ?? const <VendorView>[];
    final editable = _editable && canRequest;

    // Fill in unit names for lines added by hand, once the item loads.
    for (final l in _lines) {
      if (l.stockItemId.isEmpty) continue;
      final detail = ref.watch(stockItemDetailProvider(l.stockItemId)).valueOrNull;
      if (detail != null && l.purchaseUnitName == 'Unit') {
        l.purchaseUnitName = detail.input.purchaseUnitName;
      }
    }

    final totals = grnTotals(
      [for (final l in _lines) l.toLine()],
      invoiceValue: double.tryParse(_invoiceValue.text.trim()),
    );
    final locationName = _nameOf(locations, _locationId);
    final title = _grn?.summary.number ?? 'Receive a delivery';

    Widget body;
    if (_loading) {
      body = DelayedSkeleton(child: SkeletonList());
    } else {
      body = LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1024;
        final photo = _photoCard(context, editable);
        final details = _detailsCard(context, editable, vendors, locations);
        final lines = _linesCard(context, editable);
        final summary = _summaryCard(context, totals, locationName);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [lines, SizedBox(height: t.spacing.md), summary],
                ),
              ),
              SizedBox(width: t.spacing.md),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [photo, SizedBox(height: t.spacing.md), details],
                ),
              ),
            ],
          );
        }
        // Phone and tablet: the invoice photo comes first.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            photo,
            SizedBox(height: t.spacing.md),
            details,
            SizedBox(height: t.spacing.md),
            lines,
            SizedBox(height: t.spacing.md),
            summary,
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
              breadcrumb: 'Procurement / Goods received',
              actions: [
                AppButton(
                  label: 'Back to procurement',
                  icon: Icons.arrow_back,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => context.go('/procurement'),
                ),
                if (editable)
                  AppButton(
                    label: 'Save draft',
                    loading: _busy,
                    onPressed: _busy ? null : () => _saveDraft(post: false),
                  ),
                if (editable)
                  AppButton(
                    label: 'Post GRN',
                    variant: AppButtonVariant.primary,
                    loading: _busy,
                    onPressed: _busy ? null : () => _saveDraft(post: true),
                  ),
              ],
            ),
            if (_error != null) ...[
              SizedBox(height: t.spacing.sm),
              InlineAlert(message: _error!),
            ],
            if (_fieldError != null) ...[
              SizedBox(height: t.spacing.sm),
              InlineAlert(message: _fieldError!, tone: StatusTone.warning),
            ],
            SizedBox(height: t.spacing.md),
            Expanded(child: SingleChildScrollView(child: body)),
          ],
        ),
      ),
    );
  }

  static String _nameOf(List<LocationView> list, String? id) {
    for (final l in list) {
      if (l.id == id) return l.name;
    }
    return 'the location';
  }

  Widget _photoCard(BuildContext context, bool editable) {
    final t = context.tokens;
    return AppCard(
      title: 'Vendor invoice photo',
      child: Row(
        children: [
          Expanded(
            child: Text(
              _photoName ?? 'No photo yet. Take or upload the invoice before you check the lines.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SizedBox(width: t.spacing.sm),
          AppButton(
            label: _photoUrl == null ? 'Attach invoice photo or PDF' : 'Retake photo',
            icon: Icons.photo_camera_outlined,
            loading: _uploading,
            onPressed: editable && !_uploading ? _pickPhoto : null,
          ),
        ],
      ),
    );
  }

  Widget _detailsCard(
    BuildContext context,
    bool editable,
    List<VendorView> vendors,
    List<LocationView> locations,
  ) {
    final t = context.tokens;
    return AppCard(
      title: 'Delivery details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSelect<String>(
            label: 'Vendor',
            value: _vendorId,
            items: [for (final v in vendors) AppSelectItem(v.id, v.name)],
            onChanged: editable ? (v) => setState(() => _vendorId = v) : (_) {},
          ),
          SizedBox(height: t.spacing.sm),
          AppTextField(
            label: 'Vendor invoice no. *',
            controller: _invoiceNo,
            onChanged: editable ? (_) => setState(() {}) : null,
          ),
          SizedBox(height: t.spacing.sm),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Received on', border: OutlineInputBorder()),
            child: Row(
              children: [
                Expanded(child: Text(shortDay(_receivedOn))),
                if (editable) TextButton(onPressed: _pickReceivedOn, child: const Text('Change')),
              ],
            ),
          ),
          SizedBox(height: t.spacing.sm),
          AppSelect<String>(
            label: 'Into',
            value: _locationId,
            items: [for (final l in locations) AppSelectItem(l.id, l.name)],
            onChanged: editable ? (v) => setState(() => _locationId = v) : (_) {},
          ),
          SizedBox(height: t.spacing.sm),
          AppTextField(
            label: 'Transport permit *',
            controller: _permit,
            helperText: 'Required when a line is liquor',
            onChanged: editable ? (_) => setState(() {}) : null,
          ),
        ],
      ),
    );
  }

  Widget _linesCard(BuildContext context, bool editable) {
    final t = context.tokens;
    return AppCard(
      title: 'Check what arrived',
      actions: [
        if (editable)
          AppButton(
            label: 'Add line',
            icon: Icons.add,
            size: AppControlSize.sm,
            onPressed: () => _pickItemForLine(context),
          ),
      ],
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _head(context, 'Item', 220),
                _head(context, 'Ordered', 120),
                _head(context, 'Invoiced', 120),
                _head(context, 'Received', 120),
                _head(context, 'Damaged', 120),
                _head(context, 'Rate ₹', 110),
                _head(context, 'Batch', 130),
                _head(context, 'Expiry', 130),
                _head(context, 'Status', 150),
              ],
            ),
            for (var i = 0; i < _lines.length; i++) _lineRow(context, i, editable),
            if (_lines.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: t.spacing.md),
                child: Text(
                  'No lines yet. They fill in from the purchase order, or add them by hand.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _head(BuildContext context, String label, double width) => SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
      );

  Widget _lineRow(BuildContext context, int i, bool editable) {
    final t = context.tokens;
    final l = _lines[i];
    final status = grnLineStatus(l.toLine());
    final error = _lineErrors['line$i'];

    Widget qty(TextEditingController c) => SizedBox(
          width: 120,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: AppTextField(
              label: '',
              controller: c,
              keyboardType: TextInputType.number,
              errorText: error,
              onChanged: editable ? (_) => setState(() {}) : null,
            ),
          ),
        );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.spacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.name.isEmpty ? 'Pick an item' : l.name,
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(l.purchaseUnitName, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          qty(l.ordered),
          qty(l.invoiced),
          qty(l.received),
          qty(l.damaged),
          SizedBox(
            width: 110,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: AppTextField(
                label: '',
                controller: l.rate,
                keyboardType: TextInputType.number,
                onChanged: editable ? (_) => setState(() {}) : null,
              ),
            ),
          ),
          SizedBox(
            width: 130,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: AppTextField(label: '', controller: l.batch, onChanged: editable ? (_) => setState(() {}) : null),
            ),
          ),
          SizedBox(
            width: 130,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: AppTextField(
                label: '',
                controller: l.expiry,
                hint: 'yyyy-mm-dd',
                onChanged: editable ? (_) => setState(() {}) : null,
              ),
            ),
          ),
          SizedBox(
            width: 150,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(child: _statusChip(status, l)),
                  if (editable)
                    AppIconButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Remove line',
                      onPressed: () => setState(() {
                        _lines.removeAt(i).dispose();
                      }),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status, _GLine l) {
    switch (status) {
      case 'OVER_INVOICED':
        final extra = l.invoicedQty - l.orderedQty;
        return StatusBadge(label: 'Invoice +${_plain(extra)}', tone: StatusTone.warning);
      case 'DAMAGED':
        return StatusBadge(label: '${_plain(l.damagedQty)} damaged', tone: StatusTone.danger);
      case 'SHORT':
        return StatusBadge(
          label: 'Short ${_plain(l.invoicedQty - l.receivedQty)}',
          tone: StatusTone.warning,
        );
      default:
        return const StatusBadge(label: 'OK', tone: StatusTone.success);
    }
  }

  /// Adds a blank line for an item that is not on the PO.
  Future<void> _pickItemForLine(BuildContext context) async {
    final items = await ref
        .read(stockItemsProvider((locationId: null, status: null, liquor: false)).future);
    if (!context.mounted) return;
    final picked = await showDialog<StockItemRow>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Add a line'),
        children: [
          for (final i in items)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(i),
              child: Text(i.name),
            ),
          if (items.isEmpty) const Text('No stock items yet.'),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _lines.add(_GLine(
        stockItemId: picked.id,
        name: picked.name,
        purchaseUnitName: 'Unit',
        ordered: '1',
        invoiced: '1',
        received: '1',
      ));
    });
  }

  Widget _summaryCard(BuildContext context, GrnTotals totals, String locationName) {
    final t = context.tokens;
    final preview = grnPreviewSentence(totals, locationName: locationName);
    return AppCard(
      title: 'Posting',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(preview),
          SizedBox(height: t.spacing.md),
          Wrap(
            spacing: t.spacing.lg,
            runSpacing: t.spacing.sm,
            children: [
              _money(context, 'PO value', formatWire(_grn?.poValue ?? '0.00')),
              _money(context, 'Invoice value', formatRupees(totals.invoiceValue)),
              _money(context, 'Payable after GRN', formatRupees(totals.payable)),
            ],
          ),
          SizedBox(height: t.spacing.sm),
          Text(
            'Goes to the Accountant for the 3-way match: PO vs GRN vs invoice.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (totals.mismatch) ...[
            SizedBox(height: t.spacing.sm),
            InlineAlert(
              message: 'Invoice and received quantities differ. The PO will show as invoice mismatch.',
              tone: StatusTone.warning,
            ),
          ],
          SizedBox(height: t.spacing.sm),
          Text(
            'Invoice value (leave empty to use invoiced quantities)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SizedBox(
            width: 240,
            child: AppTextField(
              label: 'Invoice value ₹',
              controller: _invoiceValue,
              keyboardType: TextInputType.number,
              onChanged: _editable ? (_) => setState(() {}) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _money(BuildContext context, String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      );
}
