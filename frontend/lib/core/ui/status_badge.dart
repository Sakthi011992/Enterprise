import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'status_tone.dart';
import 'ui_style.dart';

/// Small pill with a word, an icon for the tone (where it has one), and a
/// subtle tone background.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
  });

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = toneColorsOf(context, tone);
    final icon = colors.icon;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.spacing.sm, vertical: t.spacing.xs),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(t.radius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.foreground),
            SizedBox(width: t.spacing.xs),
          ],
          Text(label, style: kitTextStyle(t, t.typography.label, colors.foreground)),
        ],
      ),
    );
  }
}
