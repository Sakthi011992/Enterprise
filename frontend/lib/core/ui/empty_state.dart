import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_button.dart';
import 'ui_style.dart';

/// Centred placeholder for a list or page with nothing in it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final body = message;
    final action = actionLabel;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(t.spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: t.color.content.muted),
            SizedBox(height: t.spacing.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: kitTextStyle(t, t.typography.title, t.color.content.primary, display: true),
            ),
            if (body != null) ...[
              SizedBox(height: t.spacing.xs),
              Text(
                body,
                textAlign: TextAlign.center,
                style: kitTextStyle(t, t.typography.body, t.color.content.secondary),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: t.spacing.md),
              AppButton(
                label: action,
                variant: AppButtonVariant.secondary,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
