import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui_style.dart';

/// Raised surface with a hairline border. Optional title row with actions.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.title,
    this.actions = const [],
  });

  final Widget child;
  final EdgeInsets? padding;
  final String? title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final heading = title;
    return Container(
      decoration: BoxDecoration(
        color: t.color.background.raised,
        borderRadius: BorderRadius.circular(t.radius.lg),
        border: Border.all(color: t.color.border.subtle, width: t.borderWidth.hairline),
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (heading != null || actions.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: heading == null
                        ? const SizedBox.shrink()
                        : Text(
                            heading,
                            style: kitTextStyle(t, t.typography.label, t.color.content.primary),
                          ),
                  ),
                  ...actions,
                ],
              ),
              SizedBox(height: t.spacing.sm),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
