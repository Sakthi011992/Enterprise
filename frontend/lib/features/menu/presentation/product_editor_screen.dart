import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../../tax/data/tax_repository.dart';
import '../data/menu_repository.dart';
import 'widgets/recipe_editor.dart';

final menuProductProvider = FutureProvider.family<MenuProduct, String>(
  (ref, id) => ref.watch(menuRepositoryProvider).product(id),
);

/// One editable variant row. Owns its controllers.
class _VariantRow {
  _VariantRow({this.id, String name = '', String price = '', this.isDefault = false})
      : name = TextEditingController(text: name),
        price = TextEditingController(text: price);

  final String? id;
  final TextEditingController name;
  final TextEditingController price;
  bool isDefault;

  void dispose() {
    name.dispose();
    price.dispose();
  }
}

/// Menu > product editor: details, category, tax class, variants, modifier
/// groups and the 86 (out of stock) switch.
class ProductEditorScreen extends ConsumerStatefulWidget {
  const ProductEditorScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends ConsumerState<ProductEditorScreen> {
  bool _initialised = false;
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _variants = <_VariantRow>[];
  final _groupIds = <String>{};
  String? _categoryId;
  String? _taxClassId;
  bool _is86 = false;
  bool _saving = false;
  String? _error;
  Map<String, String?> _fieldErrors = const {};

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  void _load(MenuProduct p) {
    _name.text = p.name;
    _desc.text = p.description ?? '';
    _price.text = p.price.toStringAsFixed(2);
    _categoryId = p.categoryId;
    _taxClassId = p.taxClassId;
    _is86 = p.is86;
    _groupIds
      ..clear()
      ..addAll(p.modifierGroupIds);
    _variants
      ..clear()
      ..addAll([
        for (final v in p.variants)
          _VariantRow(id: v.id, name: v.name, price: v.price.toStringAsFixed(2), isDefault: v.isDefault),
      ]);
    _initialised = true;
  }

  void _addVariant() {
    setState(() => _variants.add(_VariantRow(isDefault: _variants.isEmpty)));
  }

  void _removeVariant(int index) {
    setState(() {
      final removed = _variants.removeAt(index);
      if (removed.isDefault && _variants.isNotEmpty) _variants.first.isDefault = true;
      removed.dispose();
    });
  }

  void _setDefault(int index) {
    setState(() {
      for (var i = 0; i < _variants.length; i++) {
        _variants[i].isDefault = i == index;
      }
    });
  }

  /// Checks the form and returns true when it can be saved. Fills field errors.
  bool _validate() {
    final price = double.tryParse(_price.text.trim());
    final errors = <String, String?>{
      'name': _name.text.trim().isEmpty ? 'Enter a name' : null,
      'price': (price == null || price < 0) ? 'Enter a price of 0 or more' : null,
    };
    for (var i = 0; i < _variants.length; i++) {
      final v = _variants[i];
      if (v.name.text.trim().isEmpty) errors['variant$i'] = 'Name this variant';
      final vp = double.tryParse(v.price.text.trim());
      if (vp == null || vp < 0) errors['variant$i'] = 'Enter a price for this variant';
    }
    if (_variants.isNotEmpty && !_variants.any((v) => v.isDefault)) {
      errors['variants'] = 'Pick one variant as the default';
    }
    setState(() => _fieldErrors = errors);
    return errors.values.every((e) => e == null);
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!_validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(menuRepositoryProvider);
    try {
      await repo.updateProduct(widget.productId, {
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'price': double.parse(_price.text.trim()).toStringAsFixed(2),
        'categoryId': _categoryId,
        'taxClassId': _taxClassId,
      });
      await repo.setVariants(
        widget.productId,
        [
          for (final v in _variants)
            MenuVariant(
              id: v.id,
              name: v.name.text.trim(),
              price: double.parse(v.price.text.trim()),
              isDefault: v.isDefault,
            ),
        ],
      );
      await repo.setModifierGroups(widget.productId, _groupIds.toList());
      ref.invalidate(menuProductProvider(widget.productId));
      ref.invalidate(menuProductsProvider);
      if (mounted) {
        setState(() => _saving = false);
        showAppToast(context, 'Product saved');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ApiError.from(e).message;
        });
      }
    }
  }

  Future<void> _set86(bool value) async {
    setState(() => _error = null);
    try {
      await ref.read(menuRepositoryProvider).set86(widget.productId, value);
      setState(() => _is86 = value);
      ref.invalidate(menuProductsProvider);
      if (mounted) showAppToast(context, value ? 'Marked out of stock' : 'Back on the menu');
    } catch (e) {
      if (mounted) setState(() => _error = ApiError.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final product = ref.watch(menuProductProvider(widget.productId));
    final canEdit = can(ref, Perm.menuEdit, AccessLevel.edit);
    final canMark86 = can(ref, Perm.menuMark86, AccessLevel.edit);

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: product.when(
          skipLoadingOnReload: true,
          loading: () => DelayedSkeleton(child: SkeletonList()),
          error: (e, _) => ErrorState(
            message: ApiError.from(e).message,
            onRetry: () => ref.invalidate(menuProductProvider(widget.productId)),
          ),
          data: (p) {
            if (!_initialised) _load(p);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: p.name,
                  breadcrumb: 'Menu & products',
                  actions: [
                    AppButton(
                      label: 'Back to products',
                      icon: Icons.arrow_back,
                      variant: AppButtonVariant.ghost,
                      onPressed: () => context.go('/menu'),
                    ),
                    if (canEdit)
                      AppButton(
                        label: 'Save',
                        variant: AppButtonVariant.primary,
                        loading: _saving,
                        onPressed: _save,
                      ),
                  ],
                ),
                if (_error != null) ...[
                  SizedBox(height: t.spacing.sm),
                  InlineAlert(message: _error!),
                ],
                SizedBox(height: t.spacing.md),
                Expanded(
                  child: SingleChildScrollView(
                    child: _sections(canEdit, canMark86, p),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sections(bool canEdit, bool canMark86, MenuProduct product) {
    final t = context.tokens;
    final categories = ref.watch(menuCategoriesProvider).valueOrNull ?? const <MenuCategory>[];
    final taxClasses = ref.watch(taxClassesProvider).valueOrNull ?? const <TaxClass>[];
    final groups = ref.watch(menuModifierGroupsProvider).valueOrNull ?? const <ModifierGroup>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          title: 'Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                label: 'Name',
                controller: _name,
                errorText: _fieldErrors['name'],
              ),
              SizedBox(height: t.spacing.md),
              AppTextField(label: 'Description', controller: _desc),
              SizedBox(height: t.spacing.md),
              AppTextField(
                label: 'Base price',
                controller: _price,
                keyboardType: TextInputType.number,
                errorText: _fieldErrors['price'],
                prefix: const Padding(padding: EdgeInsets.only(left: 12), child: Text('₹')),
              ),
              SizedBox(height: t.spacing.md),
              AppSelect<String>(
                label: 'Category',
                value: _pick(_categoryId, categories.map((c) => c.id)),
                items: [for (final c in categories) AppSelectItem(c.id, c.name)],
                onChanged: canEdit ? (v) => setState(() => _categoryId = v) : (_) {},
              ),
              SizedBox(height: t.spacing.md),
              AppSelect<String>(
                label: 'Tax class',
                value: _pick(_taxClassId, taxClasses.map((c) => c.id)),
                items: [for (final c in taxClasses) AppSelectItem(c.id, '${c.name} (${c.rate.toStringAsFixed(2)}%)')],
                onChanged: canEdit ? (v) => setState(() => _taxClassId = v) : (_) {},
              ),
            ],
          ),
        ),
        SizedBox(height: t.spacing.md),
        AppCard(
          title: 'Variants',
          actions: [
            if (canEdit)
              AppButton(
                label: 'Add variant',
                icon: Icons.add,
                size: AppControlSize.sm,
                onPressed: _addVariant,
              ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_fieldErrors['variants'] != null) ...[
                InlineAlert(message: _fieldErrors['variants']!),
                SizedBox(height: t.spacing.sm),
              ],
              if (_variants.isEmpty)
                Text(
                  'No variants. The base price applies.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              for (var i = 0; i < _variants.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: t.spacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: AppTextField(
                          label: 'Variant ${i + 1}',
                          controller: _variants[i].name,
                          errorText: _fieldErrors['variant$i'],
                        ),
                      ),
                      SizedBox(width: t.spacing.sm),
                      Expanded(
                        flex: 2,
                        child: AppTextField(
                          label: 'Price',
                          controller: _variants[i].price,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      SizedBox(width: t.spacing.sm),
                      ChoiceChip(
                        label: const Text('Default'),
                        selected: _variants[i].isDefault,
                        onSelected: canEdit ? (_) => _setDefault(i) : null,
                      ),
                      if (canEdit)
                        AppIconButton(
                          icon: Icons.delete_outline,
                          tooltip: 'Remove variant ${i + 1}',
                          onPressed: () => _removeVariant(i),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: t.spacing.md),
        AppCard(
          title: 'Modifier groups',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (groups.isEmpty)
                Text('No modifier groups yet. Create them under Modifiers.', style: Theme.of(context).textTheme.bodySmall),
              for (final g in groups)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(g.name),
                  subtitle: Text('Pick ${g.minSelect} to ${g.maxSelect}'),
                  value: _groupIds.contains(g.id),
                  onChanged: canEdit
                      ? (v) => setState(() {
                            if (v == true) {
                              _groupIds.add(g.id);
                            } else {
                              _groupIds.remove(g.id);
                            }
                          })
                      : null,
                ),
            ],
          ),
        ),
        SizedBox(height: t.spacing.md),
        AppCard(
          title: 'Availability',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Out of stock (86)'),
            subtitle: const Text('Greys the item out on the POS and tells the outlet.'),
            value: _is86,
            onChanged: canMark86 ? _set86 : null,
          ),
        ),
        SizedBox(height: t.spacing.md),
        AppCard(
          title: 'Recipe',
          child: RecipeEditor(
            productId: product.id,
            sellingPrice: product.price,
            variants: [
              for (final v in product.variants)
                if (v.id != null) (id: v.id!, name: v.name),
            ],
            canEdit: canEdit,
          ),
        ),
      ],
    );
  }
}

/// The dropdown value only when it is one of [ids], otherwise null.
String? _pick(String? id, Iterable<String> ids) {
  if (id == null) return null;
  for (final candidate in ids) {
    if (candidate == id) return id;
  }
  return null;
}
