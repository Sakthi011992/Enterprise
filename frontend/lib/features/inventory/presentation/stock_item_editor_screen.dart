import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../../pos/presentation/pos_format.dart';
import '../../procurement/data/procurement_repository.dart';
import '../../procurement/data/procurement_models.dart';
import '../data/inventory_models.dart';
import '../data/inventory_repository.dart';
import '../data/json_read.dart';
import 'inventory_messages.dart';

/// One item's detail (`GET /stock/items/:id`).
final stockItemDetailProvider = FutureProvider.family<StockItemDetail, String>(
  (ref, id) => ref.watch(inventoryRepositoryProvider).stockItem(id),
);

/// Recent movements of one item (`GET /stock/items/:id/movements`).
final stockItemMovementsProvider = FutureProvider.family<List<MovementRow>, String>(
  (ref, id) => ref.watch(inventoryRepositoryProvider).movements(id, limit: 20),
);

/// Stock item editor (Inventory board, "Edit stock item"). `id` is `new` to
/// create an item.
class StockItemEditorScreen extends ConsumerStatefulWidget {
  const StockItemEditorScreen({super.key, required this.itemId});

  final String itemId;

  bool get isNew => itemId == 'new';

  @override
  ConsumerState<StockItemEditorScreen> createState() => _StockItemEditorScreenState();
}

class _StockItemEditorScreenState extends ConsumerState<StockItemEditorScreen> {
  bool _initialised = false;
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _category = TextEditingController();
  final _packSize = TextEditingController(text: '1');
  final _packName = TextEditingController(text: 'pc');
  final _purchaseUnitName = TextEditingController(text: 'Unit');
  final _purchaseUnitQty = TextEditingController(text: '1');
  final _shelfLife = TextEditingController();
  final _par = <String, TextEditingController>{};
  final _opening = <String, TextEditingController>{};
  String _baseUnit = BaseUnits.ml;
  String _costing = 'WEIGHTED_AVERAGE';
  String? _vendorId;
  bool _isLiquor = false;
  bool _isKeg = false;
  bool _isActive = true;
  bool _saving = false;
  String? _error;
  String? _nameError;

  @override
  void dispose() {
    for (final c in [
      _name,
      _sku,
      _category,
      _packSize,
      _packName,
      _purchaseUnitName,
      _purchaseUnitQty,
      _shelfLife,
      ..._par.values,
      ..._opening.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(Map<String, TextEditingController> map, String locationId) =>
      map.putIfAbsent(locationId, () => TextEditingController(text: '0'));

  void _load(StockItemDetail d) {
    final i = d.input;
    _name.text = i.name;
    _sku.text = i.sku ?? '';
    _category.text = i.categoryName ?? '';
    _packSize.text = _plain(i.packSize);
    _packName.text = i.packName;
    _purchaseUnitName.text = i.purchaseUnitName;
    _purchaseUnitQty.text = _plain(i.purchaseUnitQty);
    _shelfLife.text = i.shelfLifeDays?.toString() ?? '';
    _baseUnit = i.baseUnit;
    _costing = i.costingMethod;
    _vendorId = i.preferredVendorId;
    _isLiquor = i.isLiquor;
    _isKeg = i.isKeg;
    _isActive = i.isActive;
    for (final level in d.levels) {
      _controllerFor(_par, level.locationId).text = _plain(decimalValue(level.parLevel));
    }
    _initialised = true;
  }

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  StockItemInput _input() => StockItemInput(
        name: _name.text.trim(),
        sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
        categoryName: _category.text.trim().isEmpty ? null : _category.text.trim(),
        baseUnit: _baseUnit,
        packSize: num.tryParse(_packSize.text.trim()) ?? 1,
        packName: _packName.text.trim().isEmpty ? 'pc' : _packName.text.trim(),
        purchaseUnitName: _purchaseUnitName.text.trim().isEmpty ? 'Unit' : _purchaseUnitName.text.trim(),
        purchaseUnitQty: num.tryParse(_purchaseUnitQty.text.trim()) ?? 1,
        costingMethod: _costing,
        preferredVendorId: _vendorId,
        isLiquor: _isLiquor,
        isKeg: _isKeg,
        shelfLifeDays: int.tryParse(_shelfLife.text.trim()),
        isActive: _isActive,
      );

  Future<void> _save(List<LocationView> locations) async {
    setState(() {
      _error = null;
      _nameError = _name.text.trim().isEmpty ? 'Enter a name' : null;
    });
    final packSize = num.tryParse(_packSize.text.trim());
    final purchaseQty = num.tryParse(_purchaseUnitQty.text.trim());
    if (_nameError != null) return;
    if (packSize == null || packSize <= 0) {
      setState(() => _error = 'Pack size must be above zero. Use 1 for items counted one by one.');
      return;
    }
    if (purchaseQty == null || purchaseQty <= 0) {
      setState(() => _error = 'Purchase unit quantity must be above zero.');
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(inventoryRepositoryProvider);
    try {
      if (widget.isNew) {
        final opening = [
          for (final l in locations)
            if (num.tryParse(_controllerFor(_opening, l.id).text.trim()) case final q? when q > 0)
              (locationId: l.id, qty: q),
        ];
        final created = await repo.createStockItem(_input(), opening: opening);
        if (mounted) {
          ref.invalidate(inventoryLocationsProvider);
          context.go('/inventory/items/${created.row.id}');
        }
      } else {
        await repo.updateStockItem(widget.itemId, _input());
        await repo.setPar(widget.itemId, [
          for (final l in locations)
            if (_par.containsKey(l.id))
              (locationId: l.id, parLevel: num.tryParse(_par[l.id]!.text.trim()) ?? 0),
        ]);
        ref.invalidate(stockItemDetailProvider(widget.itemId));
        ref.invalidate(inventoryLocationsProvider);
        if (mounted) showAppToast(context, 'Stock item saved');
      }
    } catch (e) {
      if (mounted) setState(() => _error = inventoryErrorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.menuEdit, AccessLevel.edit) ||
        can(ref, Perm.stockPurchaseOrders, AccessLevel.edit);
    final locations = ref.watch(inventoryLocationsProvider).valueOrNull ?? const <LocationView>[];
    final vendors = ref.watch(procurementVendorsProvider).valueOrNull ?? const <VendorView>[];

    final body = widget.isNew
        ? null
        : ref.watch(stockItemDetailProvider(widget.itemId));

    Widget content;
    if (!widget.isNew && body != null && !body.hasValue) {
      content = body.hasError
          ? ErrorState(
              message: ApiError.from(body.error!).message,
              onRetry: () => ref.invalidate(stockItemDetailProvider(widget.itemId)),
            )
          : DelayedSkeleton(child: SkeletonList());
    } else {
      if (!widget.isNew && !_initialised) {
        final d = body!.requireValue;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _load(d));
        });
        content = DelayedSkeleton(child: SkeletonList());
      } else {
        content = _form(context, canEdit, locations, vendors);
      }
    }

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: widget.isNew ? 'New stock item' : (_name.text.isEmpty ? 'Stock item' : _name.text),
              breadcrumb: 'Inventory',
              actions: [
                AppButton(
                  label: 'Back to inventory',
                  icon: Icons.arrow_back,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => context.go('/inventory'),
                ),
                if (canEdit)
                  AppButton(
                    label: 'Save',
                    variant: AppButtonVariant.primary,
                    loading: _saving,
                    onPressed: _saving ? null : () => _save(locations),
                  ),
              ],
            ),
            if (_error != null) ...[
              SizedBox(height: t.spacing.sm),
              InlineAlert(message: _error!),
            ],
            SizedBox(height: t.spacing.md),
            Expanded(child: SingleChildScrollView(child: content)),
          ],
        ),
      ),
    );
  }

  Widget _form(
    BuildContext context,
    bool canEdit,
    List<LocationView> locations,
    List<VendorView> vendors,
  ) {
    final t = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 720;
        final half = twoColumns ? (constraints.maxWidth - t.spacing.md) / 2 : constraints.maxWidth;
        Widget field(Widget child) => SizedBox(width: half, child: child);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              title: 'Details',
              child: Wrap(
                spacing: t.spacing.md,
                runSpacing: t.spacing.md,
                children: [
                  field(AppTextField(label: 'Name', controller: _name, errorText: _nameError)),
                  field(AppTextField(label: 'Category', controller: _category, hint: 'Spirits')),
                  field(AppTextField(label: 'SKU (optional)', controller: _sku)),
                  field(AppSelect<String>(
                    label: 'Base unit',
                    value: _baseUnit,
                    items: const [
                      AppSelectItem(BaseUnits.ml, 'ml (liquids)'),
                      AppSelectItem(BaseUnits.g, 'g (weighed food)'),
                      AppSelectItem(BaseUnits.pc, 'pc (pieces)'),
                    ],
                    onChanged: canEdit ? (v) => setState(() => _baseUnit = v ?? _baseUnit) : (_) {},
                  )),
                  field(AppTextField(
                    label: 'Pack size (${_baseUnit.toLowerCase()} per ${_packName.text.isEmpty ? 'pack' : _packName.text})',
                    controller: _packSize,
                    keyboardType: TextInputType.number,
                  )),
                  field(AppTextField(label: 'Pack name', controller: _packName, hint: 'btl, keg, pc')),
                  field(AppTextField(label: 'Purchase unit', controller: _purchaseUnitName, hint: 'Case of 12 bottles')),
                  field(AppTextField(
                    label: 'Purchase unit = ${_baseUnit.toLowerCase()}',
                    controller: _purchaseUnitQty,
                    keyboardType: TextInputType.number,
                    helperText: 'Base units in one purchase unit, for example 12 × 750 = 9000',
                  )),
                  field(AppSelect<String>(
                    label: 'Costing',
                    value: _costing,
                    items: const [
                      AppSelectItem('WEIGHTED_AVERAGE', 'Weighted average'),
                      AppSelectItem('FIFO', 'FIFO'),
                    ],
                    onChanged: canEdit ? (v) => setState(() => _costing = v ?? _costing) : (_) {},
                  )),
                  field(AppTextField(
                    label: 'Shelf life (days)',
                    controller: _shelfLife,
                    keyboardType: TextInputType.number,
                  )),
                ],
              ),
            ),
            if (_costing == 'FIFO') ...[
              SizedBox(height: t.spacing.xs),
              Text(
                'FIFO costing arrives later; weighted average is used for now.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            SizedBox(height: t.spacing.md),
            AppCard(
              title: 'Supply',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppSelect<String>(
                    label: 'Preferred vendor',
                    value: _vendorId,
                    items: [for (final v in vendors) AppSelectItem(v.id, v.name)],
                    onChanged: canEdit ? (v) => setState(() => _vendorId = v) : (_) {},
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Liquor'),
                    subtitle: const Text('Needs a transport permit on goods receipts.'),
                    value: _isLiquor,
                    onChanged: canEdit ? (v) => setState(() => _isLiquor = v) : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Keg'),
                    subtitle: const Text('Counted as full kegs and the amount on tap.'),
                    value: _isKeg,
                    onChanged: canEdit ? (v) => setState(() => _isKeg = v) : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active'),
                    value: _isActive,
                    onChanged: canEdit ? (v) => setState(() => _isActive = v) : null,
                  ),
                ],
              ),
            ),
            SizedBox(height: t.spacing.md),
            AppCard(
              title: widget.isNew ? 'Opening stock and par' : 'Par level per location',
              child: Wrap(
                spacing: t.spacing.md,
                runSpacing: t.spacing.md,
                children: [
                  for (final l in locations)
                    field(AppTextField(
                      label: '${l.name} par (${_baseUnit.toLowerCase()})',
                      controller: _controllerFor(_par, l.id),
                      keyboardType: TextInputType.number,
                    )),
                  if (widget.isNew)
                    for (final l in locations)
                      field(AppTextField(
                        label: '${l.name} opening (${_baseUnit.toLowerCase()})',
                        controller: _controllerFor(_opening, l.id),
                        keyboardType: TextInputType.number,
                      )),
                ],
              ),
            ),
            if (!widget.isNew) ...[
              SizedBox(height: t.spacing.md),
              AppCard(
                title: 'Recent movements',
                child: _movements(context),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _movements(BuildContext context) {
    final async = ref.watch(stockItemMovementsProvider(widget.itemId));
    return async.when(
      loading: () => DelayedSkeleton(child: SkeletonList(rows: 3)),
      error: (e, _) => ErrorState(message: ApiError.from(e).message),
      data: (rows) {
        if (rows.isEmpty) {
          return Text('No movements yet.', style: Theme.of(context).textTheme.bodySmall);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('${m.type.replaceAll('_', ' ').toLowerCase()} · ${m.qtyDisplay}'),
                subtitle: Text(
                  [
                    m.businessDate,
                    if (m.note != null && m.note!.isNotEmpty) m.note!,
                  ].join(' · '),
                ),
                trailing: Text(formatWire(m.value)),
              ),
          ],
        );
      },
    );
  }
}
