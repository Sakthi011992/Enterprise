import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/token_ext.dart';
import 'app_button.dart';
import 'ui_style.dart';

/// Centred "Couldn't load this" with the error detail and an optional retry.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(t.spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IconWell(
              icon: Icons.error_outline,
              background: context.ext.dangerSubtle,
              color: context.ext.onDangerSubtle,
            ),
            SizedBox(height: t.spacing.md),
            Text(
              "Couldn't load this",
              textAlign: TextAlign.center,
              style: kitTextStyle(t, t.typography.title, t.color.content.primary, display: true),
            ),
            SizedBox(height: t.spacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: kitTextStyle(t, t.typography.body, t.color.content.secondary),
            ),
            if (onRetry != null) ...[
              SizedBox(height: t.spacing.md),
              AppButton(
                label: 'Try again',
                icon: Icons.refresh,
                onPressed: onRetry,
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
