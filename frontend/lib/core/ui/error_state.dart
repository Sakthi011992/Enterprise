import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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
            Icon(Icons.error_outline, size: 40, color: t.color.content.danger),
            SizedBox(height: t.spacing.sm),
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
