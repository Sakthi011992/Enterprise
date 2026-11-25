import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../data/menu_repository.dart';

/// Menu > Combos. A combo is one price for several products; POS sells it as a unit.
class CombosScreen extends ConsumerStatefulWidget {
  const CombosScreen({super.key});

  @override
  ConsumerState<CombosScreen> createState() => _CombosScreenState();
}

class _CombosScreenState extends ConsumerState<CombosScreen> {
  String? _error;

  Future<void> _edit({Combo? combo}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ComboDialog(combo: combo),
    );
    if (saved == true) {
      ref.invalidate(menuCombosProvider);
      if (mounted) showAppToast(context, combo == null ? 'Combo added' : 'Combo saved');
    }
  }

  Future<void> _delete(Combo combo) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${combo.name}?',
      message: 'It stops showing on the POS. Past orders keep their lines.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _error = null);
    try {
      await ref.read(menuRepositoryProvider).deleteCombo(combo.id);
      ref.invalidate(menuCombosProvider);
    } catch (e) {
      setState(() => _error = ApiError.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.menuEdit, AccessLevel.edit);
    final async = ref.watch(menuCombosProvider);
    final rows = async.valueOrNull ?? const <Combo>[];

    final columns = <AppColumn<Combo>>[
      AppColumn<Combo>(
        label: 'Combo',
        cell: (c) => Text(c.name, overflow: TextOverflow.ellipsis),
      ),
      AppColumn<Combo>(
        label: 'Price',
        numeric: true,
        width: 110,
        cell: (c) => Text('₹${c.price.toStringAsFixed(2)}'),
      ),
      AppColumn<Combo>(
        label: 'Includes',
        cell: (c) => Text(
          '${c.items.length} ${c.items.length == 1 ? 'item' : 'items'}',
        ),
      ),
      AppColumn<Combo>(
        label: 'Status',
        width: 120,
        cell: (c) => StatusBadge(
          label: c.isActive ? 'Active' : 'Hidden',
          tone: c.isActive ? StatusTone.success : StatusTone.neutral,
        ),
      ),
      if (canEdit)
        AppColumn<Combo>(
          label: 'Actions',
          width: 110,
          cell: (c) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit ${c.name}',
                onPressed: () => _edit(combo: c),
              ),
              AppIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete ${c.name}',
                onPressed: () => _delete(c),
              ),
            ],
          ),
        ),
    ];

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Combos',
              breadcrumb: 'Menu & products',
              actions: [
                if (canEdit)
                  AppButton(
                    label: 'New combo',
                    icon: Icons.add,
                    variant: AppButtonVariant.primary,
                    onPressed: () => _edit(),
                  ),
              ],
            ),
            if (_error != null) ...[
              SizedBox(height: t.spacing.sm),
              InlineAlert(message: _error!),
            ],
            SizedBox(height: t.spacing.md),
            Expanded(
              child: AppDataTable<Combo>(
                columns: columns,
                rows: rows,
                loading: async.isLoading && !async.hasValue,
                error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
                onRetry: () => ref.invalidate(menuCombosProvider),
                empty: EmptyState(
                  title: 'No combos yet',
                  message: 'Bundle items such as a burger, fries and a drink at one price.',
                  icon: Icons.layers_outlined,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow {
  _ItemRow({this.productId, String quantity = '1', this.swapAllowed = false})
      : quantity = TextEditingController(text: quantity);

  String? productId;
  final TextEditingController quantity;
  bool swapAllowed;

  void dispose() => quantity.dispose();
}

class _ComboDialog extends ConsumerStatefulWidget {
  const _ComboDialog({this.combo});

  final Combo? combo;

  @override
  ConsumerState<_ComboDialog> createState() => _ComboDialogState();
}

class _ComboDialogState extends ConsumerState<_ComboDialog> {
  late final _name = TextEditingController(text: widget.combo?.name ?? '');
  late final _price = TextEditingController(text: widget.combo?.price.toStringAsFixed(2) ?? '');
  late bool _isActive = widget.combo?.isActive ?? true;
  late final List<_ItemRow> _items = [
    for (final i in widget.combo?.items ?? const <ComboItem>[])
      _ItemRow(productId: i.productId, quantity: '${i.quantity}', swapAllowed: i.swapAllowed),
  ];
  String? _nameError;
  String? _priceError;
  String? _itemError;
  String? _apiError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.trim());
    setState(() {
      _apiError = null;
      _nameError = _name.text.trim().isEmpty ? 'Enter a name' : null;
      _priceError = (price == null || price < 0) ? 'Enter a price of 0 or more' : null;
      final bad = _items.any((i) {
        final q = int.tryParse(i.quantity.text.trim());
        return i.productId == null || q == null || q < 1;
      });
      _itemError = _items.isEmpty
          ? 'Add at least one product to the combo'
          : (bad ? 'Pick a product and a quantity of 1 or more for each line' : null);
    });
    if (_nameError != null || _priceError != null || _itemError != null) return;

    setState(() => _saving = true);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'price': price!.toStringAsFixed(2),
      'isActive': _isActive,
      'items': [
        for (final i in _items)
          ComboItem(
            productId: i.productId!,
            quantity: int.parse(i.quantity.text.trim()),
            swapAllowed: i.swapAllowed,
          ).toJson(),
      ],
    };
    final repo = ref.read(menuRepositoryProvider);
    try {
      if (widget.combo == null) {
        await repo.createCombo(body);
      } else {
        await repo.updateCombo(widget.combo!.id, body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _apiError = ApiError.from(e).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final products = ref.watch(menuProductsProvider).valueOrNull ?? const <MenuProduct>[];

    return AlertDialog(
      title: Text(widget.combo == null ? 'New combo' : 'Edit combo'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_apiError != null) ...[
                InlineAlert(message: _apiError!),
                SizedBox(height: t.spacing.sm),
              ],
              AppTextField(label: 'Combo name', controller: _name, errorText: _nameError, autofocus: true),
              SizedBox(height: t.spacing.md),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Combo price',
                      controller: _price,
                      keyboardType: TextInputType.number,
                      errorText: _priceError,
                    ),
                  ),
                  SizedBox(width: t.spacing.md),
                  Expanded(
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.spacing.sm),
              Text('Includes', style: Theme.of(context).textTheme.labelLarge),
              SizedBox(height: t.spacing.xs),
              if (_itemError != null) ...[
                InlineAlert(message: _itemError!),
                SizedBox(height: t.spacing.sm),
              ],
              for (var i = 0; i < _items.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: t.spacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: AppSelect<String>(
                          label: 'Product ${i + 1}',
                          value: _items[i].productId,
                          items: [for (final p in products) AppSelectItem(p.id, p.name)],
                          onChanged: (v) => setState(() => _items[i].productId = v),
                        ),
                      ),
                      SizedBox(width: t.spacing.sm),
                      Expanded(
                        flex: 2,
                        child: AppTextField(
                          label: 'Qty',
                          controller: _items[i].quantity,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      Checkbox(
                        value: _items[i].swapAllowed,
                        onChanged: (v) => setState(() => _items[i].swapAllowed = v ?? false),
                      ),
                      Text('Swap', style: Theme.of(context).textTheme.bodySmall),
                      AppIconButton(
                        icon: Icons.remove_circle_outline,
                        tooltip: 'Remove line ${i + 1}',
                        onPressed: () => setState(() => _items.removeAt(i).dispose()),
                      ),
                    ],
                  ),
                ),
              AppButton(
                label: 'Add product',
                icon: Icons.add,
                size: AppControlSize.sm,
                onPressed: () => setState(() => _items.add(_ItemRow())),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Save',
          variant: AppButtonVariant.primary,
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}
