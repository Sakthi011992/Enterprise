import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Shared shell for the POS dialogs: title, optional subtitle, body, and a
/// wrapping action row. Token colours only.
class PosDialogFrame extends StatelessWidget {
  const PosDialogFrame({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.actions = const [],
    this.width = 520,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: t.color.background.raised,
      insetPadding: EdgeInsets.all(t.spacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius.lg),
        side: BorderSide(color: t.color.border.subtle, width: t.borderWidth.hairline),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(t.spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              if (subtitle != null) ...[
                SizedBox(height: t.spacing.xs),
                Text(subtitle!, style: TextStyle(color: t.color.content.secondary)),
              ],
              SizedBox(height: t.spacing.md),
              child,
              if (actions.isNotEmpty) ...[
                SizedBox(height: t.spacing.lg),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: t.spacing.sm,
                  runSpacing: t.spacing.sm,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Sized row of chips used for reasons, quick amounts and modes.
class PosChoiceChip extends StatelessWidget {
  const PosChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.minHeight = 44,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = onTap != null;
    final background = selected ? context.ext.accentSubtle : t.color.background.surface;
    final foreground = selected ? context.ext.onAccentSubtle : t.color.content.primary;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: Opacity(
        // A selected chip stays solid even without a tap handler (read-only tabs).
        opacity: (enabled || selected) ? 1 : 0.45,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(t.radius.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(t.radius.pill),
            onTap: onTap,
            child: Container(
              constraints: BoxConstraints(minHeight: minHeight),
              padding: EdgeInsets.symmetric(horizontal: t.spacing.md),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(t.radius.pill),
                border: Border.all(
                  color: selected ? context.ext.accentSubtleBorder : t.color.border.standard,
                  width: t.borderWidth.hairline,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft brass pill used for happy-hour indicators.
class BrassBadge extends StatelessWidget {
  const BrassBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.spacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: ext.brassSubtle,
        borderRadius: BorderRadius.circular(t.radius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ext.onBrassSubtle),
      ),
    );
  }
}
