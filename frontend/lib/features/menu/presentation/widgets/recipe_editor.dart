import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/ui/ui.dart';
import '../../../inventory/data/inventory_models.dart';
import '../../../inventory/data/inventory_repository.dart';
import '../../../inventory/data/json_read.dart';
import '../../../inventory/presentation/inventory_messages.dart';
import '../../../pos/presentation/pos_format.dart';

/// Recipes of one product (`GET /products/:id/recipes`).
final productRecipesProvider = FutureProvider.family<List<RecipeView>, String>(
  (ref, productId) => ref.watch(inventoryRepositoryProvider).recipes(productId),
);

/// One ingredient row. Owns its controllers.
class _RLine {
  _RLine({this.stockItemId, String qty = '', String wastage = '0'})
      : qty = TextEditingController(text: qty),
        wastage = TextEditingController(text: wastage);

  String? stockItemId;
  final TextEditingController qty;
  final TextEditingController wastage;

  void dispose() {
    qty.dispose();
    wastage.dispose();
  }
}

/// Ingredients for one scope: "All variants" (variantId null) or one variant.
class _Scope {
  _Scope({required this.variantId, required this.name});

  final String? variantId;
  final String name;
  final List<_RLine> lines = [];

  void dispose() {
    for (final l in lines) {
      l.dispose();
    }
  }
}

/// Recipe section of the product editor (MenuEditors board). Each sale deducts
/// these amounts from stock, which is what the variance report compares against.
class RecipeEditor extends ConsumerStatefulWidget {
  const RecipeEditor({
    super.key,
    required this.productId,
    required this.sellingPrice,
    required this.variants,
    required this.canEdit,
  });

  final String productId;

  /// Base price of the product, used for pour cost and margin.
  final double sellingPrice;

  /// Saved variants (id and name). Unsaved variants have no recipe yet.
  final List<({String id, String name})> variants;
  final bool canEdit;

  @override
  ConsumerState<RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends ConsumerState<RecipeEditor> {
  final List<_Scope> _scopes = [];
  final Map<String, RecipeView> _saved = {};
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final s in _scopes) {
      s.dispose();
    }
    super.dispose();
  }

  static String _key(String? variantId) => variantId ?? '';

  void _load(List<RecipeView> recipes) {
    for (final s in _scopes) {
      s.dispose();
    }
    _scopes
      ..clear()
      ..add(_Scope(variantId: null, name: 'All variants'))
      ..addAll([for (final v in widget.variants) _Scope(variantId: v.id, name: v.name)]);
    _saved
      ..clear()
      ..addAll({for (final r in recipes) _key(r.variantId): r});
    for (final scope in _scopes) {
      final recipe = _saved[_key(scope.variantId)];
      if (recipe == null) continue;
      for (final l in recipe.lines) {
        scope.lines.add(_RLine(
          stockItemId: l.stockItemId,
          qty: _plain(decimalValue(l.qty)),
          wastage: _plain(decimalValue(l.wastagePercent)),
        ));
      }
    }
    _loaded = true;
  }

  static String _plain(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Cost of one serving of a scope, from the live inputs and the item averages.
  double _cost(_Scope scope, Map<String, StockItemRow> items) {
    var cost = 0.0;
    for (final l in scope.lines) {
      final item = items[l.stockItemId];
      if (item == null) continue;
      final qty = num.tryParse(l.qty.text.trim()) ?? 0;
      final wastage = num.tryParse(l.wastage.text.trim()) ?? 0;
      cost += qty * (1 + wastage / 100) * item.avgCostAmount;
    }
    return roundPaise(cost);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final recipes = <RecipeInput>[
      for (final scope in _scopes)
        if (scope.lines.any((l) => l.stockItemId != null))
          RecipeInput(
            variantId: scope.variantId,
            lines: [
              for (final l in scope.lines)
                if (l.stockItemId != null)
                  RecipeLineInput(
                    stockItemId: l.stockItemId!,
                    qty: num.tryParse(l.qty.text.trim()) ?? 0,
                    wastagePercent: num.tryParse(l.wastage.text.trim()) ?? 0,
                  ),
            ],
          ),
    ];
    try {
      await ref.read(inventoryRepositoryProvider).saveRecipes(widget.productId, recipes);
      ref.invalidate(productRecipesProvider(widget.productId));
      if (mounted) showAppToast(context, 'Recipes saved');
    } catch (e) {
      if (mounted) setState(() => _error = inventoryErrorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final async = ref.watch(productRecipesProvider(widget.productId));
    final items = ref.watch(stockItemsProvider((locationId: null, status: null, liquor: false)));
    final itemById = {for (final i in items.valueOrNull ?? const <StockItemRow>[]) i.id: i};

    if (!_loaded && async.hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loaded) setState(() => _load(async.requireValue));
      });
    }

    if (async.hasError && !async.hasValue) {
      return ErrorState(
        message: ApiError.from(async.error!).message,
        onRetry: () => ref.invalidate(productRecipesProvider(widget.productId)),
      );
    }
    if (!_loaded) return DelayedSkeleton(child: SkeletonList(rows: 2));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "Each sale deducts these amounts from Bar stock. That's what the variance report compares against.",
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_error != null) ...[
          SizedBox(height: t.spacing.sm),
          InlineAlert(message: _error!),
        ],
        for (final scope in _scopes) ...[
          SizedBox(height: t.spacing.md),
          _scopeCard(context, scope, itemById),
        ],
        SizedBox(height: t.spacing.md),
        if (widget.canEdit)
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'Save recipes',
              variant: AppButtonVariant.primary,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ),
      ],
    );
  }

  Widget _scopeCard(BuildContext context, _Scope scope, Map<String, StockItemRow> itemById) {
    final t = context.tokens;
    final cost = _cost(scope, itemById);
    final price = widget.sellingPrice;
    final pour = price > 0 ? cost / price * 100 : null;
    final margin = pour == null ? null : 100 - pour;
    final saved = _saved[_key(scope.variantId)];
    final items = itemById.values.toList()..sort((a, b) => a.name.compareTo(b.name));

    return AppCard(
      title: scope.name,
      actions: [
        if (widget.canEdit)
          AppButton(
            label: 'Add ingredient',
            icon: Icons.add,
            size: AppControlSize.sm,
            onPressed: () => setState(() => scope.lines.add(_RLine(qty: '0'))),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (scope.lines.isEmpty)
            Text(
              scope.variantId == null
                  ? 'No ingredients. Variants without their own recipe use this one.'
                  : 'No ingredients. The all-variants recipe is used instead.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          for (var i = 0; i < scope.lines.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: t.spacing.sm),
              child: _lineRow(context, scope, i, items, itemById),
            ),
          SizedBox(height: t.spacing.sm),
          Wrap(
            spacing: t.spacing.lg,
            runSpacing: t.spacing.sm,
            children: [
              _stat(context, 'Cost per drink', formatRupees(cost, alwaysPaise: true)),
              _stat(context, 'Selling price', formatRupees(price)),
              _stat(context, 'Pour cost', pour == null ? '-' : '${pour.toStringAsFixed(1)}%'),
              _stat(context, 'Margin', margin == null ? '-' : '${margin.toStringAsFixed(0)}%'),
              if (saved != null && saved.pourCostPercent != null)
                _stat(context, 'Saved pour cost', '${saved.pourCostPercent}%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lineRow(
    BuildContext context,
    _Scope scope,
    int i,
    List<StockItemRow> items,
    Map<String, StockItemRow> itemById,
  ) {
    final t = context.tokens;
    final line = scope.lines[i];
    final item = itemById[line.stockItemId];
    final unit = item == null ? 'unit' : item.baseUnit.toLowerCase();
    final lineCost = item == null
        ? 0.0
        : roundPaise((num.tryParse(line.qty.text.trim()) ?? 0) *
            (1 + (num.tryParse(line.wastage.text.trim()) ?? 0) / 100) *
            item.avgCostAmount);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: AppSelect<String>(
            label: 'Ingredient',
            value: line.stockItemId,
            items: [for (final s in items) AppSelectItem(s.id, s.name)],
            onChanged: widget.canEdit ? (v) => setState(() => line.stockItemId = v) : (_) {},
          ),
        ),
        SizedBox(width: t.spacing.sm),
        Expanded(
          flex: 2,
          child: AppTextField(
            label: 'Qty ($unit)',
            controller: line.qty,
            keyboardType: TextInputType.number,
            onChanged: widget.canEdit ? (_) => setState(() {}) : null,
          ),
        ),
        SizedBox(width: t.spacing.sm),
        Expanded(
          child: AppTextField(
            label: 'Wastage %',
            controller: line.wastage,
            keyboardType: TextInputType.number,
            onChanged: widget.canEdit ? (_) => setState(() {}) : null,
          ),
        ),
        SizedBox(width: t.spacing.sm),
        SizedBox(
          width: 90,
          child: Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Text(formatRupees(lineCost, alwaysPaise: true), textAlign: TextAlign.right),
          ),
        ),
        if (widget.canEdit)
          AppIconButton(
            icon: Icons.remove_circle_outline,
            tooltip: 'Remove ingredient',
            onPressed: () => setState(() => scope.lines.removeAt(i).dispose()),
          ),
      ],
    );
  }

  Widget _stat(BuildContext context, String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      );
}
