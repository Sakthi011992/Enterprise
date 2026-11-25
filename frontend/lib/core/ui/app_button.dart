import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/theme_tokens.dart';
import '../theme/token_ext.dart';
import 'ui_style.dart';

enum AppButtonVariant { primary, secondary, danger, ghost }

/// Token-driven button. Height comes from [size], or from the nearest
/// DensityScope when [size] is null. [loading] shows a spinner and blocks taps.
/// The focus ring uses `border.focus`.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.secondary,
    this.size,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppControlSize? size;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    final controlSize = size ?? ext.defaultControlSize;
    final height = ext.controlHeight(controlSize);
    final enabled = onPressed != null && !loading;
    final colors = _ButtonColors.of(t, variant);
    final radius = BorderRadius.circular(t.radius.md);
    final focusSide = BorderSide(color: t.color.border.focus, width: t.borderWidth.thick);

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll<Size?>(Size(0, height)),
      padding: WidgetStatePropertyAll<EdgeInsetsGeometry?>(
        EdgeInsets.symmetric(
          horizontal: controlSize == AppControlSize.sm ? t.spacing.md : t.spacing.lg,
        ),
      ),
      elevation: const WidgetStatePropertyAll<double?>(0),
      backgroundColor: WidgetStatePropertyAll<Color?>(colors.background),
      foregroundColor: WidgetStatePropertyAll<Color?>(colors.foreground),
      textStyle: WidgetStatePropertyAll<TextStyle?>(
        kitTextStyle(t, t.typography.label, colors.foreground),
      ),
      shape: WidgetStateProperty.resolveWith<OutlinedBorder?>(
        (states) => RoundedRectangleBorder(
          borderRadius: radius,
          side: states.contains(WidgetState.focused) ? focusSide : colors.side,
        ),
      ),
    );

    final Widget? leading = loading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: colors.foreground),
          )
        : (icon == null ? null : Icon(icon, size: 18));

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[
          leading,
          SizedBox(width: t.spacing.xs),
        ],
        Text(label),
      ],
    );

    final Widget button = switch (variant) {
      AppButtonVariant.primary || AppButtonVariant.danger => FilledButton(
          onPressed: enabled ? onPressed : null,
          style: style,
          child: content,
        ),
      AppButtonVariant.secondary => OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: style,
          child: content,
        ),
      AppButtonVariant.ghost => TextButton(
          onPressed: enabled ? onPressed : null,
          style: style,
          child: content,
        ),
    };

    return Opacity(opacity: onPressed == null ? 0.5 : 1.0, child: button);
  }
}

class _ButtonColors {
  const _ButtonColors({
    required this.background,
    required this.foreground,
    required this.side,
  });

  /// Null lets the Material default (transparent) apply.
  final Color? background;
  final Color foreground;
  final BorderSide side;

  static _ButtonColors of(ThemeTokens t, AppButtonVariant variant) {
    switch (variant) {
      case AppButtonVariant.primary:
        return _ButtonColors(
          background: t.color.background.accent,
          foreground: t.color.content.onAccent,
          side: BorderSide.none,
        );
      case AppButtonVariant.secondary:
        return _ButtonColors(
          background: t.color.background.raised,
          foreground: t.color.content.primary,
          side: BorderSide(color: t.color.border.standard, width: t.borderWidth.hairline),
        );
      case AppButtonVariant.danger:
        return _ButtonColors(
          background: t.color.background.danger,
          foreground: t.color.content.onAccent,
          side: BorderSide.none,
        );
      case AppButtonVariant.ghost:
        return _ButtonColors(
          background: null,
          foreground: t.color.content.primary,
          side: BorderSide.none,
        );
    }
  }
}
