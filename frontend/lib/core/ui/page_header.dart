import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui_style.dart';

/// Page title with an optional breadcrumb line and action buttons. Actions wrap
/// onto a new line on narrow screens.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.breadcrumb,
    this.actions = const [],
  });

  final String title;
  final String? breadcrumb;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final crumb = breadcrumb;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.spacing.md, t.spacing.md, t.spacing.md, t.spacing.sm),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: t.spacing.md,
        runSpacing: t.spacing.sm,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (crumb != null)
                Text(
                  crumb,
                  style: kitTextStyle(t, t.typography.label, t.color.content.secondary),
                ),
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: kitTextStyle(t, t.typography.display, t.color.content.primary, display: true),
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty)
            Wrap(
              spacing: t.spacing.sm,
              runSpacing: t.spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
        ],
      ),
    );
  }
}
