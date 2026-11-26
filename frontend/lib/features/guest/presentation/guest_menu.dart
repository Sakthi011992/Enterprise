import 'package:flutter/material.dart';

import '../../pos/presentation/modifier_rules.dart';
import '../../pos/presentation/pos_format.dart';
import '../application/guest_controller.dart';
import '../data/guest_models.dart';
import 'guest_widgets.dart';

/// Id of the "Popular" tab (featured items, as on the kiosk).
const kPopularTab = '_popular';

/// Products for a tab, or for a search across the whole menu.
List<GuestProduct> productsFor(GuestMenu menu, String tab, String query) {
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    return menu.products
        .where((p) => p.name.toLowerCase().contains(q) || p.description.toLowerCase().contains(q))
        .toList();
  }
  if (tab == kPopularTab) {
    final popular = menu.popular;
    return popular.isEmpty ? menu.products.take(8).toList() : popular;
  }
  return menu.categories.where((c) => c.id == tab).expand((c) => c.products).toList();
}

/// Default tab: Popular when there are featured items, else the first category.
String defaultTab(GuestMenu menu) =>
    menu.popular.isNotEmpty || menu.categories.isEmpty ? kPopularTab : menu.categories.first.id;

/// Category pills. The selected one is filled green.
class CategoryTabs extends StatelessWidget {
  const CategoryTabs({super.key, required this.menu, required this.selected, required this.onSelect});

  final GuestMenu menu;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final tabs = [
      (kPopularTab, 'Popular'),
      for (final c in menu.categories) (c.id, c.name),
    ];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final (id, label) = tabs[i];
          final on = id == selected;
          return Semantics(
            selected: on,
            button: true,
            child: InkWell(
              onTap: () => onSelect(id),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: on ? p.header : p.card,
                  border: Border.all(color: on ? p.header : p.line),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(label,
                    style: p.body(12, weight: FontWeight.w600, color: on ? p.onHeader : p.ink)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Vertical list of categories with counts (desktop left column).
class CategoryRail extends StatelessWidget {
  const CategoryRail({super.key, required this.menu, required this.selected, required this.onSelect});

  final GuestMenu menu;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    Widget item(String id, String label, int? count) {
      final on = id == selected;
      return Semantics(
        selected: on,
        button: true,
        child: InkWell(
          onTap: () => onSelect(id),
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: on ? p.accentSoft : null,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(children: [
              Expanded(
                child: Text(label,
                    style: p.body(13.5,
                        weight: on ? FontWeight.w600 : FontWeight.w400,
                        color: on ? p.onAccentSoft : p.ink)),
              ),
              if (count != null) Text('$count', style: p.body(12, color: p.muted)),
            ]),
          ),
        ),
      );
    }

    return Container(
      key: const Key('guest-category-rail'),
      color: p.card,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      child: ListView(children: [
        item(kPopularTab, 'Popular', null),
        for (final c in menu.categories) item(c.id, c.name, c.products.length),
      ]),
    );
  }
}

/// Search box for the menu.
class MenuSearchField extends StatelessWidget {
  const MenuSearchField({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return SizedBox(
      height: 40,
      child: TextField(
        key: const Key('guest-menu-search'),
        onChanged: onChanged,
        style: p.body(13),
        decoration: InputDecoration(
          hintText: 'Search the menu',
          hintStyle: p.body(13, color: p.muted),
          prefixIcon: Icon(Icons.search, size: 18, color: p.muted),
          filled: true,
          fillColor: p.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.line)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.accent, width: 2)),
        ),
      ),
    );
  }
}

/// Add, stepper or "Sold out" for one product.
class ProductControl extends StatelessWidget {
  const ProductControl({super.key, required this.product, required this.state, required this.onAdd, required this.onChange});

  final GuestProduct product;
  final GuestState state;
  final VoidCallback onAdd;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    if (!product.available) return const SoldOutTag();
    final qty = state.quantityOf(product.id);
    if (qty == 0) {
      return AddButton(onTap: state.placing ? null : onAdd, label: 'Add ${product.name}');
    }
    return GuestStepper(
      value: qty,
      name: product.name,
      onMinus: state.placing ? null : () => onChange(-1),
      // Items with choices open the sheet again, so each set of choices is its own line.
      onPlus: state.placing ? null : (product.hasChoices ? onAdd : () => onChange(1)),
    );
  }
}

/// Phone menu row.
class MenuRow extends StatelessWidget {
  const MenuRow({super.key, required this.product, this.control, this.last = false});

  final GuestProduct product;
  final Widget? control;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Opacity(
      opacity: product.available ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: p.line2)),
        ),
        child: Row(children: [
          ProductThumb(product: product),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.name, style: p.body(13, weight: FontWeight.w600, height: 1.25)),
              if (product.description.isNotEmpty)
                Text(product.description, style: p.body(11, color: p.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            GuestPrice(price: product.price, basePrice: product.basePrice),
            if (control != null) ...[const SizedBox(height: 6), control!],
          ]),
        ]),
      ),
    );
  }
}

/// Tablet and desktop menu card.
class MenuCard extends StatelessWidget {
  const MenuCard({super.key, required this.product, this.control});

  final GuestProduct product;
  final Widget? control;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final drink = isDrink(product);
    final soft = drink ? p.drinkSoft : p.accentSoft;
    return Opacity(
      opacity: product.available ? 1 : 0.55,
      child: GuestCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 86,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [soft, Color.lerp(soft, drink ? p.header : p.accent, 0.12)!],
              ),
            ),
            child: Text(product.name.isEmpty ? '' : product.name[0].toUpperCase(),
                style: p.display(30, color: drink ? p.header : p.accent)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: p.body(13.5, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(product.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: p.body(11.5, color: p.muted)),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: Row(children: [
                  Expanded(child: GuestPrice(price: product.price, basePrice: product.basePrice)),
                  if (control != null) control!,
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Grid of [MenuCard]s. [columns] fixes the count (tablet: 2); otherwise
/// cards are at least 190 px wide.
class MenuGrid extends StatelessWidget {
  const MenuGrid({super.key, required this.products, required this.controlFor, this.columns});

  final List<GuestProduct> products;
  final Widget? Function(GuestProduct) controlFor;
  final int? columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final count = columns ?? (c.maxWidth / 202).floor().clamp(1, 6);
      final rows = <Widget>[];
      for (var i = 0; i < products.length; i += count) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var j = 0; j < count; j++) ...[
                if (j > 0) const SizedBox(width: 12),
                Expanded(
                  child: i + j < products.length
                      ? MenuCard(product: products[i + j], control: controlFor(products[i + j]))
                      : const SizedBox.shrink(),
                ),
              ],
            ]),
          ),
        ));
      }
      return Column(children: rows);
    });
  }
}

/// Result of the choices sheet.
class GuestChoice {
  const GuestChoice({this.variant, required this.optionIds, required this.quantity});

  final GuestVariant? variant;
  final Set<String> optionIds;
  final int quantity;
}

/// Modifier sheet. Required groups block "Add" until picked (modifier_rules).
Future<GuestChoice?> showChoicesSheet(BuildContext context, GuestProduct product) {
  return showModalBottomSheet<GuestChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GuestPalette(context).card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => ChoicesSheet(product: product),
  );
}

class ChoicesSheet extends StatefulWidget {
  const ChoicesSheet({super.key, required this.product});

  final GuestProduct product;

  @override
  State<ChoicesSheet> createState() => _ChoicesSheetState();
}

class _ChoicesSheetState extends State<ChoicesSheet> {
  Set<String> _selected = {};
  GuestVariant? _variant;
  int _qty = 1;

  @override
  void initState() {
    super.initState();
    final v = widget.product.variants;
    _variant = v.isEmpty ? null : v.first;
  }

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final product = widget.product;
    final groups = product.modifierGroups;
    final errors = modifierErrors(groups, _selected);
    final unit = (_variant?.price ?? product.price) + modifierDelta(groups, _selected);
    final base = _variant?.basePrice ?? product.basePrice;

    Widget option({
      required String label,
      required bool on,
      required bool square,
      String? extra,
      required VoidCallback onTap,
    }) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            checked: on,
            button: true,
            label: label,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
                decoration: BoxDecoration(
                  color: on ? Color.lerp(p.card, p.accent, 0.04) : p.card,
                  border: Border.all(color: on ? p.accent : p.line, width: on ? 2 : 1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: square ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: square ? BorderRadius.circular(5) : null,
                      color: square && on ? p.accent : null,
                      border: Border.all(
                          color: on ? p.accent : p.t.color.border.strong, width: on && !square ? 5 : 2),
                    ),
                    child: square && on ? Icon(Icons.check, size: 11, color: p.onAccent) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label, style: p.body(13))),
                  if (extra != null) Text(extra, style: p.mono(12, color: p.ink2)),
                ]),
              ),
            ),
          ),
        );

    Widget groupTitle(String name, String rule) => Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: name, style: p.body(12, weight: FontWeight.w600)),
            TextSpan(text: ' · $rule', style: p.body(12, color: p.muted)),
          ])),
        );

    String ruleText(PosModifierGroup g) {
      if (g.minSelect == 0) return g.maxSelect == 1 ? 'optional' : 'optional, up to ${g.maxSelect}';
      if (g.minSelect == g.maxSelect) return 'choose ${g.minSelect}';
      return 'choose ${g.minSelect}–${g.maxSelect}';
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 8, 14, 14 + MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(children: [
                  Expanded(child: Text(product.name, style: p.display(20))),
                  GuestPrice(price: _variant?.price ?? product.price, basePrice: base),
                ]),
                const SizedBox(height: 10),
                if (product.variants.length > 1) ...[
                  groupTitle('Size', 'choose 1'),
                  for (final v in product.variants)
                    option(
                      label: v.name,
                      on: _variant?.id == v.id,
                      square: false,
                      extra: formatRupees(v.price),
                      onTap: () => setState(() => _variant = v),
                    ),
                ],
                for (final g in groups) ...[
                  groupTitle(g.name, ruleText(g)),
                  for (final o in g.options)
                    option(
                      label: o.name,
                      on: _selected.contains(o.id),
                      square: !g.isSingleChoice,
                      extra: o.priceDeltaValue > 0 ? '+${formatRupees(o.priceDeltaValue)}' : null,
                      onTap: () => setState(() => _selected = toggleModifierOption(g, _selected, o.id)),
                    ),
                ],
                const SizedBox(height: 4),
                Row(children: [
                  GuestStepper(
                    value: _qty,
                    name: product.name,
                    onMinus: _qty > 1 ? () => setState(() => _qty--) : null,
                    onPlus: _qty < 10 ? () => setState(() => _qty++) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GuestButton(
                      kind: errors.isEmpty ? GuestButtonKind.primary : GuestButtonKind.off,
                      label: errors.isEmpty ? 'Add · ${formatRupees(unit * _qty)}' : errors.values.first,
                      onPressed: errors.isEmpty
                          ? () => Navigator.of(context).pop(
                                GuestChoice(variant: _variant, optionIds: _selected, quantity: _qty))
                          : null,
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Age question before the first alcoholic item (PLAN 2.8, `minAge`).
Future<bool> showAgeGate(BuildContext context, int minAge) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AgeGateDialog(minAge: minAge),
  );
  return ok ?? false;
}

class AgeGateDialog extends StatelessWidget {
  const AgeGateDialog({super.key, required this.minAge});

  final int minAge;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Dialog(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Are you $minAge or over?', style: p.display(22)),
            const SizedBox(height: 8),
            Text('Alcohol is served only to guests $minAge and over. Staff may check ID at your table.',
                style: p.body(13, color: p.ink2)),
            const SizedBox(height: 16),
            GuestButton(
              kind: GuestButtonKind.primary,
              label: "Yes, I'm $minAge or over",
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 8),
            GuestButton(
              label: 'No, show me other drinks',
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Add flow for one product: age check, then choices, then the cart.
Future<void> addProductFlow(BuildContext context, GuestController controller, GuestProduct product) async {
  if (!product.available) return;
  if (controller.needsAgeCheck(product)) {
    final yes = await showAgeGate(context, controller.minAge);
    if (!yes) return;
    final ok = await controller.confirmAge();
    if (!ok) return;
  }
  if (!context.mounted) return;
  if (product.hasChoices) {
    final choice = await showChoicesSheet(context, product);
    if (choice == null) return;
    controller.add(product, variant: choice.variant, optionIds: choice.optionIds, quantity: choice.quantity);
  } else {
    controller.add(product);
  }
}
