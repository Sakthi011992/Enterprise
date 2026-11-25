import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'status_tone.dart';
import 'ui_style.dart';

/// Shared chrome for InlineAlert (rounded card) and AppBanner (full width).
/// Internal to the kit.
class ToneBar extends StatelessWidget {
  const ToneBar({
    super.key,
    required this.message,
    required this.tone,
    this.actionLabel,
    this.onAction,
    this.banner = false,
  });

  final String message;
  final StatusTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool banner;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = toneColorsOf(context, tone);
    final action = actionLabel;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: banner ? double.infinity : null,
        padding: EdgeInsets.symmetric(
          horizontal: t.spacing.md,
          vertical: banner ? t.spacing.sm : t.spacing.md,
        ),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: banner ? null : BorderRadius.circular(t.radius.md),
          border: banner
              ? Border(
                  bottom: BorderSide(color: t.color.border.subtle, width: t.borderWidth.hairline),
                )
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(colors.icon ?? Icons.info_outline, size: 18, color: colors.foreground),
            SizedBox(width: t.spacing.sm),
            Expanded(
              child: Text(message, style: kitTextStyle(t, t.typography.body, colors.foreground)),
            ),
            if (action != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: colors.foreground),
                child: Text(action),
              ),
          ],
        ),
      ),
    );
  }
}
