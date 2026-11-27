import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/token_ext.dart';
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
            _IconWell(
              icon: icon,
              background: context.ext.neutralSubtle,
              color: t.color.content.muted,
            ),
            SizedBox(height: t.spacing.md),
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

class _IconWell extends StatelessWidget {
  const _IconWell({required this.icon, required this.background, required this.color});

  final IconData icon;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(shape: BoxShape.circle, color: background),
        alignment: Alignment.center,
        child: Icon(icon, size: 28, color: color),
      );
}
