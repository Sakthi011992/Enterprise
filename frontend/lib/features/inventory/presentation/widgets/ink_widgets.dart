import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// One metric in a [KpiStrip]. The [hero] cell is set bigger than the rest.
class KpiCell {
  const KpiCell({required this.label, required this.value, this.hero = false, this.caption});

  final String label;
  final String value;
  final bool hero;
  final String? caption;
}

/// KPI group: one white card split by hairline dividers (Ink & Emerald).
class KpiStrip extends StatelessWidget {
  const KpiStrip({super.key, required this.cells});

  final List<KpiCell> cells;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    return Container(
      decoration: BoxDecoration(
        color: t.color.background.raised,
        borderRadius: BorderRadius.circular(t.radius.lg),
        border: Border.all(color: t.color.border.standard, width: t.borderWidth.hairline),
        boxShadow: ext.cardShadow,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 640;
          final divider = Container(
            width: narrow ? double.infinity : t.borderWidth.hairline,
            height: narrow ? t.borderWidth.hairline : null,
            color: t.color.border.subtle,
          );
          final children = <Widget>[];
          for (var i = 0; i < cells.length; i++) {
            if (i > 0) children.add(divider);
            final cell = _KpiCellView(cell: cells[i]);
            children.add(narrow ? cell : Expanded(flex: cells[i].hero ? 3 : 2, child: cell));
          }
          return narrow
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
              : IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                );
        },
      ),
    );
  }
}

class _KpiCellView extends StatelessWidget {
  const _KpiCellView({required this.cell});

  final KpiCell cell;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final valueStyle = AppFonts.apply(
      t.typography.displayFamily,
      TextStyle(
        fontSize: cell.hero ? 40 : 28,
        fontWeight: cell.hero ? FontWeight.w800 : FontWeight.w700,
        color: t.color.content.primary,
        fontFeatures: kTabularFigures,
      ),
    );
    return Padding(
      padding: EdgeInsets.all(t.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            cell.label,
            style: TextStyle(
              fontFamily: t.typography.bodyFamily,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: t.color.content.secondary,
            ),
          ),
          SizedBox(height: t.spacing.xs),
          Text(cell.value, style: valueStyle),
          if (cell.caption != null) ...[
            SizedBox(height: t.spacing.xs),
            Text(
              cell.caption!,
              style: TextStyle(
                fontFamily: t.typography.bodyFamily,
                fontSize: 12,
                color: t.color.content.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Filter chip: selected = accentSubtle fill with accentSubtleBorder; idle =
/// raised fill with a strong hairline. Replaces ChoiceChip / FilterChip.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? ext.accentSubtle : t.color.background.raised,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? ext.accentSubtleBorder : t.color.border.strong,
            width: t.borderWidth.hairline,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onSelected,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: t.spacing.md, vertical: t.spacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: t.typography.bodyFamily,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? ext.onAccentSubtle : t.color.content.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal level bar for stock against par. [fraction] is on hand / par
/// (0..1+); the bar turns amber below par and red when empty or negative.
class LevelBar extends StatelessWidget {
  const LevelBar({super.key, required this.fraction, this.width = 96});

  final double fraction;

  /// Preferred width; the bar shrinks to fit a narrower column.
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    final color = fraction <= 0
        ? ext.statusRed
        : fraction < 1
            ? ext.statusAmber
            : ext.statusGreen;
    return ExcludeSemantics(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: SizedBox(
          width: double.infinity,
          height: 6,
          // Track and fill both get a size from their child: a ColoredBox with no child is 0×0.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(t.radius.pill),
            child: ColoredBox(
              color: ext.neutralSubtle,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: f,
                  heightFactor: 1,
                  child: ColoredBox(color: color, child: const SizedBox.expand()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
