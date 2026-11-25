import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../data/pos_models.dart';
import 'pos_format.dart';

/// Product cards for the POS. Each card shows its variant chips. Tapping the card
/// adds the default variant, and tapping a chip adds that variant. 86'd products
/// are greyed out with "Out of stock".
class PosProductGrid extends StatelessWidget {
  const PosProductGrid({
    super.key,
    required this.products,
    required this.combos,
    required this.showCombos,
    required this.onProduct,
    required this.onVariant,
    required this.onCombo,
  });

  final List<PosProduct> products;
  final List<PosCombo> combos;

  /// When true, the grid shows [combos] instead of [products].
  final bool showCombos;
  final ValueChanged<PosProduct> onProduct;
  final void Function(PosProduct product, PosVariant variant) onVariant;
  final ValueChanged<PosCombo> onCombo;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final count = showCombos ? combos.length : products.length;
    if (count == 0) {
      return const EmptyState(
        title: 'Nothing here yet',
        message: 'Try another category or clear the search.',
        icon: Icons.search_off_outlined,
      );
    }
    return GridView.builder(
      padding: EdgeInsets.all(t.spacing.md),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.8, // room for two rows of variant chips
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        if (showCombos) {
          final combo = combos[index];
          return _ComboCard(combo: combo, onTap: combo.availableNow ? () => onCombo(combo) : null);
        }
        final product = products[index];
        return _ProductCard(
          product: product,
          onTap: product.is86 ? null : () => onProduct(product),
          onVariant: product.is86 ? null : (v) => onVariant(product, v),
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, this.onTap, this.onVariant});

  final PosProduct product;
  final VoidCallback? onTap;
  final ValueChanged<PosVariant>? onVariant;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final out = product.is86;
    final price = product.defaultVariant?.price ?? product.price;
    return Opacity(
      opacity: out ? 0.5 : 1,
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
              border: Border.all(color: t.color.border.standard, width: t.borderWidth.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.color.content.primary,
                  ),
                ),
                const Spacer(),
                if (out)
                  Text(
                    'Out of stock',
                    style: TextStyle(color: t.color.content.danger, fontWeight: FontWeight.w600),
                  )
                else ...[
                  if (product.variants.length > 1)
                    Wrap(
                      spacing: t.spacing.xs,
                      runSpacing: t.spacing.xs,
                      children: [
                        for (final v in product.variants)
                          _VariantChip(
                            label: v.name,
                            onTap: onVariant == null ? null : () => onVariant!(v),
                          ),
                      ],
                    ),
                  SizedBox(height: t.spacing.xs),
                  Text(
                    '${formatWire(price)}${product.variants.length > 1 ? ' / ${product.defaultVariant?.name ?? ''}' : ''}',
                    style: TextStyle(color: t.color.content.secondary, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VariantChip extends StatelessWidget {
  const _VariantChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: t.color.background.surface,
      shape: StadiumBorder(
        side: BorderSide(color: t.color.border.strong, width: t.borderWidth.hairline),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: t.spacing.sm),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: t.color.content.primary),
          ),
        ),
      ),
    );
  }
}

class _ComboCard extends StatelessWidget {
  const _ComboCard({required this.combo, this.onTap});

  final PosCombo combo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: combo.availableNow ? 1 : 0.5,
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
              border: Border.all(color: t.color.border.standard, width: t.borderWidth.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  combo.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.color.content.primary),
                ),
                const Spacer(),
                Text(
                  combo.availableNow ? formatWire(combo.price) : 'Not available now',
                  style: TextStyle(color: t.color.content.secondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
