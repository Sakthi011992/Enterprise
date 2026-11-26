import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/files/pick_file.dart';
import '../../../core/ui/ui.dart';
import '../../pos/presentation/pos_format.dart';
import '../data/inventory_models.dart';
import '../data/inventory_repository.dart';
import '../data/stock_format.dart';
import 'inventory_messages.dart';
import 'widgets/qty_stepper.dart';
import 'widgets/ink_widgets.dart';

/// Wastage above this value needs a photo (PLAN 1.7).
const double wastagePhotoThreshold = 2000;

/// Opens the "Log wastage" sheet (MobileStaff board). Resolves to true when a
/// wastage entry was saved. P3-D calls this from the availability screen.
Future<bool> showLogWastageSheet(
  BuildContext context, {
  String? locationId,
  String? stockItemId,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DensityScope(
      density: AppDensity.pos,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: _LogWastageSheet(locationId: locationId, stockItemId: stockItemId),
      ),
    ),
  );
  return saved ?? false;
}

class _LogWastageSheet extends ConsumerStatefulWidget {
  const _LogWastageSheet({this.locationId, this.stockItemId});

  final String? locationId;
  final String? stockItemId;

  @override
  ConsumerState<_LogWastageSheet> createState() => _LogWastageSheetState();
}

class _LogWastageSheetState extends ConsumerState<_LogWastageSheet> {
  String? _locationId;
  String? _itemId;
  int _bottles = 0;
  final _openMl = TextEditingController(text: '0');
  final _note = TextEditingController();
  String? _reason;
  String? _photoUrl;
  String? _photoName;
  bool _uploading = false;
  bool _saving = false;
  String? _error;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    _locationId = widget.locationId;
    _itemId = widget.stockItemId;
  }

  @override
  void dispose() {
    _openMl.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Quantity in base units from the stepper (packs) and the open part.
  num _qtyBase(StockItemRow item) {
    final open = num.tryParse(_openMl.text.trim()) ?? 0;
    return parseStockInput(_bottles, open, item.packSize);
  }

  Future<void> _pickPhoto() async {
    final picked = await pickImageFile();
    if (picked == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await ref.read(inventoryRepositoryProvider).uploadFile(picked);
      if (mounted) setState(() => _photoUrl = url);
      if (mounted) setState(() => _photoName = picked.name);
    } catch (e) {
      if (mounted) setState(() => _error = inventoryErrorText(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save(StockItemRow item) async {
    final qty = _qtyBase(item);
    final problems = <String>[];
    if (_locationId == null) problems.add('Pick a location.');
    if (qty <= 0) problems.add('Enter a quantity above zero.');
    if (_reason == null) problems.add('Pick a reason.');
    setState(() {
      _error = null;
      _fieldError = problems.isEmpty ? null : problems.join(' ');
    });
    if (problems.isNotEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(inventoryRepositoryProvider).logWastage(
            locationId: _locationId!,
            stockItemId: item.id,
            qty: qty,
            reason: _reason!,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            photoUrl: _photoUrl,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = inventoryErrorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locations = ref.watch(inventoryLocationsProvider).valueOrNull ?? const <LocationView>[];
    final list = _locationId == null
        ? const <StockItemRow>[]
        : ref
                .watch(stockItemsProvider((locationId: _locationId, status: null, liquor: false)))
                .valueOrNull ??
            const <StockItemRow>[];
    StockItemRow? item;
    for (final i in list) {
      if (i.id == _itemId) item = i;
    }

    final qty = item == null ? 0 : _qtyBase(item);
    final value = item == null ? 0.0 : qty * item.avgCostAmount;
    final needsPhoto = value > wastagePhotoThreshold;
    final photoNeeded = needsPhoto && _photoUrl == null;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(t.spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Log wastage', style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: t.spacing.md),
            if (_error != null) ...[
              InlineAlert(message: _error!),
              SizedBox(height: t.spacing.sm),
            ],
            if (_fieldError != null) ...[
              InlineAlert(message: _fieldError!, tone: StatusTone.warning),
              SizedBox(height: t.spacing.sm),
            ],
            AppSelect<String>(
              label: 'Location',
              value: _locationId,
              items: [for (final l in locations) AppSelectItem(l.id, l.name)],
              onChanged: (v) => setState(() {
                _locationId = v;
                _itemId = null;
              }),
            ),
            SizedBox(height: t.spacing.md),
            AppSelect<String>(
              label: 'Item',
              value: _itemId,
              items: [for (final i in list) AppSelectItem(i.id, i.name)],
              onChanged: (v) => setState(() {
                _itemId = v;
                _bottles = 0;
                _openMl.text = '0';
              }),
            ),
            if (item != null) ...[
              SizedBox(height: t.spacing.md),
              Text('Quantity', style: Theme.of(context).textTheme.labelLarge),
              SizedBox(height: t.spacing.xs),
              if (item.packSize > 1)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: t.spacing.md,
                  runSpacing: t.spacing.sm,
                  children: [
                    QtyStepper(
                      value: _bottles,
                      unitLabel: item.packName,
                      onChanged: (v) => setState(() => _bottles = v),
                    ),
                    SizedBox(
                      width: 160,
                      child: AppTextField(
                        label: '${item.baseUnit.toLowerCase()} open',
                        controller: _openMl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                )
              else
                AppTextField(
                  label: 'Quantity (${item.baseUnit.toLowerCase()})',
                  controller: _openMl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              SizedBox(height: t.spacing.xs),
              Text(
                'Stock ${item.onHandDisplay} at this location',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            SizedBox(height: t.spacing.md),
            Text('Reason', style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: t.spacing.xs),
            Wrap(
              spacing: t.spacing.sm,
              runSpacing: t.spacing.sm,
              children: [
                for (final (wire, label) in WastageReasons.picks)
                  FilterPill(
                    label: label,
                    selected: _reason == wire,
                    onSelected: () => setState(() => _reason = wire),
                  ),
              ],
            ),
            SizedBox(height: t.spacing.md),
            AppTextField(label: 'Note (optional)', controller: _note),
            SizedBox(height: t.spacing.md),
            Row(
              children: [
                AppButton(
                  label: _photoUrl == null
                      ? (needsPhoto ? 'Add photo (needed above ₹2,000)' : 'Add photo')
                      : 'Change photo',
                  icon: Icons.photo_camera_outlined,
                  variant: photoNeeded ? AppButtonVariant.primary : AppButtonVariant.secondary,
                  loading: _uploading,
                  onPressed: _uploading ? null : _pickPhoto,
                ),
                SizedBox(width: t.spacing.sm),
                if (_photoName != null)
                  Expanded(
                    child: Text(_photoName!, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
            SizedBox(height: t.spacing.md),
            if (item != null)
              Text(
                'Value about ${formatRupees(value)}'
                '${value > wastagePhotoThreshold ? ' · Manager gets notified' : ''}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            if (item != null && qty > 0)
              Text(
                formatStockQty(qty, item.baseUnit, item.packSize, item.packName),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            SizedBox(height: t.spacing.lg),
            AppButton(
              label: 'Log wastage',
              variant: AppButtonVariant.primary,
              loading: _saving,
              onPressed: item == null || _saving ? null : () => _save(item!),
            ),
          ],
        ),
      ),
    );
  }
}
