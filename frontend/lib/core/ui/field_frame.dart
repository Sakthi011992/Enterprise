import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui_style.dart';

/// Label above, field in the middle, message below. An error message always
/// comes with an icon and the word itself, so it is never colour alone.
/// Internal to the kit.
class FieldFrame extends StatelessWidget {
  const FieldFrame({
    super.key,
    required this.label,
    required this.child,
    this.errorText,
    this.helperText,
    this.minHeight = 44,
  });

  final String label;
  final Widget child;
  final String? errorText;
  final String? helperText;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final err = errorText;
    final helper = helperText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: kitTextStyle(t, t.typography.label, t.color.content.secondary)),
        SizedBox(height: t.spacing.xs),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: child,
        ),
        if (err != null && err.isNotEmpty) ...[
          SizedBox(height: t.spacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 16, color: t.color.content.danger),
              SizedBox(width: t.spacing.xs),
              Expanded(
                child: Text(err, style: kitTextStyle(t, t.typography.caption, t.color.content.danger)),
              ),
            ],
          ),
        ] else if (helper != null) ...[
          SizedBox(height: t.spacing.xs),
          Text(helper, style: kitTextStyle(t, t.typography.caption, t.color.content.secondary)),
        ],
      ],
    );
  }
}
