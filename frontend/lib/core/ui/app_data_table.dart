import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/token_ext.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'skeleton.dart';
import 'ui_style.dart';

/// One column of [AppDataTable]. [numeric] right-aligns the cells. A [width]
/// fixes the column; otherwise the remaining width is shared equally.
class AppColumn<T> {
  const AppColumn({
    required this.label,
    required this.cell,
    this.numeric = false,
    this.width,
  });

  final String label;
  final Widget Function(T row) cell;
  final bool numeric;
  final double? width;
}

const double _checkboxColumnWidth = 48;

/// Below this width the table scrolls sideways instead of squeezing.
const double _minTableWidth = 720;

/// Table with an optional search box, filter slot, row hover, selection
/// checkboxes and a bulk-action bar. Shows a skeleton while [loading], an
/// [ErrorState] on [error], and [empty] (or a default) when there are no rows.
class AppDataTable<T> extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.searchHint,
    this.onSearch,
    this.filters = const [],
    this.selected,
    this.onSelectionChanged,
    this.bulkActions = const [],
    this.onRowTap,
    this.loading = false,
    this.error,
    this.onRetry,
    this.empty,
  });

  final List<AppColumn<T>> columns;
  final List<T> rows;
  final String? searchHint;
  final ValueChanged<String>? onSearch;
  final List<Widget> filters;
  final Set<T>? selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final List<Widget> bulkActions;
  final void Function(T)? onRowTap;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    final selection = selected ?? <T>{};
    final selectable = onSelectionChanged != null;
    final failure = error;
    final showToolbar = searchHint != null || onSearch != null || filters.isNotEmpty;

    final Widget content;
    if (loading) {
      content = const DelayedSkeleton(child: SkeletonList());
    } else if (failure != null) {
      content = ErrorState(message: failure, onRetry: onRetry);
    } else if (rows.isEmpty) {
      content = empty ?? const EmptyState(title: 'Nothing here yet');
    } else {
      content = _responsiveTable(context, selection, selectable);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showToolbar) _toolbar(context),
        if (selectable && selection.isNotEmpty) _bulkBar(context, selection),
        content,
      ],
    );
  }

  Widget _toolbar(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.sm),
      child: Wrap(
        spacing: t.spacing.sm,
        runSpacing: t.spacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (searchHint != null || onSearch != null)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
              child: TextField(
                onChanged: onSearch,
                style: kitTextStyle(t, t.typography.body, t.color.content.primary),
                decoration: kitInputDecoration(
                  t,
                  ext,
                  hint: searchHint ?? 'Search',
                  prefix: const Icon(Icons.search),
                ),
              ),
            ),
          ...filters,
        ],
      ),
    );
  }

  Widget _bulkBar(BuildContext context, Set<T> selection) {
    final t = context.tokens;
    return Container(
      margin: EdgeInsets.only(bottom: t.spacing.sm),
      padding: EdgeInsets.symmetric(horizontal: t.spacing.md, vertical: t.spacing.sm),
      decoration: BoxDecoration(
        color: t.color.background.raised,
        borderRadius: BorderRadius.circular(t.radius.md),
        border: Border.all(color: t.color.border.accent, width: t.borderWidth.hairline),
      ),
      child: Row(
        children: [
          Text(
            '${selection.length} selected',
            style: kitTextStyle(t, t.typography.label, t.color.content.primary),
          ),
          SizedBox(width: t.spacing.md),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: t.spacing.sm,
              runSpacing: t.spacing.xs,
              children: [
                ...bulkActions,
                TextButton(
                  onPressed: () => onSelectionChanged?.call(<T>{}),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _responsiveTable(BuildContext context, Set<T> selection, bool selectable) {
    return LayoutBuilder(
      builder: (layoutContext, constraints) {
        final available = constraints.maxWidth;
        final scroll = !available.isFinite || available < _minTableWidth;
        final width = available.isFinite && available >= _minTableWidth ? available : _minTableWidth;
        final grid = _grid(layoutContext, width, selection, selectable);
        if (!scroll) return grid;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: width, child: grid),
        );
      },
    );
  }

  List<double> _columnWidths(double total, bool selectable) {
    final checkboxes = selectable ? _checkboxColumnWidth : 0.0;
    final fixed = columns.fold<double>(0, (sum, c) => sum + (c.width ?? 0.0));
    final flexCount = columns.where((c) => c.width == null).length;
    final remaining = total - checkboxes - fixed;
    final flexWidth = (flexCount == 0 || remaining <= 0) ? 0.0 : remaining / flexCount;
    return [for (final c in columns) c.width ?? flexWidth];
  }

  void _toggle(Set<T> current, T row, bool checked) {
    final next = Set<T>.of(current);
    if (checked) {
      next.add(row);
    } else {
      next.remove(row);
    }
    onSelectionChanged?.call(next);
  }

  Widget _grid(BuildContext context, double width, Set<T> selection, bool selectable) {
    final t = context.tokens;
    final widths = _columnWidths(width, selectable);
    final allSelected = rows.isNotEmpty && rows.every(selection.contains);
    final anySelected = rows.any(selection.contains);
    final tap = onRowTap;

    final header = Container(
      padding: EdgeInsets.symmetric(vertical: t.spacing.sm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.color.border.standard, width: t.borderWidth.hairline),
        ),
      ),
      child: Row(
        children: [
          if (selectable)
            SizedBox(
              width: _checkboxColumnWidth,
              child: Checkbox(
                tristate: true,
                value: allSelected ? true : (anySelected ? null : false),
                semanticLabel: 'Select all rows',
                onChanged: (_) => onSelectionChanged?.call(allSelected ? <T>{} : rows.toSet()),
              ),
            ),
          for (var i = 0; i < columns.length; i++)
            _cellBox(
              widths[i],
              columns[i].numeric,
              Text(
                columns[i].label,
                style: kitTextStyle(t, t.typography.label, t.color.content.secondary),
              ),
            ),
        ],
      ),
    );

    final body = [
      for (final row in rows)
        _HoverRow(
          highlighted: selection.contains(row),
          onTap: tap == null ? null : () => tap(row),
          child: Row(
            children: [
              if (selectable)
                SizedBox(
                  width: _checkboxColumnWidth,
                  child: Checkbox(
                    value: selection.contains(row),
                    semanticLabel: 'Select row',
                    onChanged: (checked) => _toggle(selection, row, checked ?? false),
                  ),
                ),
              for (var i = 0; i < columns.length; i++)
                _cellBox(widths[i], columns[i].numeric, columns[i].cell(row)),
            ],
          ),
        ),
    ];

    return SizedBox(
      width: width,
      child: DefaultTextStyle(
        style: kitTextStyle(t, t.typography.body, t.color.content.primary),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [header, ...body],
        ),
      ),
    );
  }

  Widget _cellBox(double width, bool numeric, Widget child) => SizedBox(
        width: width,
        child: Align(
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      );
}

/// A table row with a hover background and an optional tap target.
class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.child, this.onTap, this.highlighted = false});

  final Widget child;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final row = Container(
      padding: EdgeInsets.symmetric(vertical: t.spacing.sm),
      decoration: BoxDecoration(
        color: (_hovered || widget.highlighted) ? t.color.background.surface : null,
        border: Border(
          bottom: BorderSide(color: t.color.border.subtle, width: t.borderWidth.hairline),
        ),
      ),
      child: widget.child,
    );
    final tappable = widget.onTap == null
        ? row
        : InkWell(onTap: widget.onTap, child: row);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: tappable,
    );
  }
}
