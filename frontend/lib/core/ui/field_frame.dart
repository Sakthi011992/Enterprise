import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/theme_tokens.dart';
import '../theme/token_ext.dart';
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
        Text(label, style: kitTextStyle(t, t.typography.label, t.color.content.primary)),
        SizedBox(height: t.spacing.xs),
        _FocusGlow(
          hasError: err != null && err.isNotEmpty,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: child,
          ),
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

/// Soft glow around a field while any descendant has focus.
class _FocusGlow extends StatefulWidget {
  const _FocusGlow({required this.child, required this.hasError});

  final Widget child;
  final bool hasError;

  @override
  State<_FocusGlow> createState() => _FocusGlowState();
}

class _FocusGlowState extends State<_FocusGlow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(t.radius.md),
          boxShadow: _focused && !widget.hasError
              ? [BoxShadow(color: ext.focusRing, spreadRadius: 3)]
              : const [],
        ),
        child: widget.child,
      ),
    );
  }
}

/// Input decoration for the kit's fields: white fill, strong border, accent
/// focus, danger border on error. [fill] overrides the background colour.
InputDecoration fieldDecoration(
  ThemeTokens t,
  ExtTokens ext, {
  String? hint,
  Widget? prefix,
  Widget? suffix,
  bool hasError = false,
  Color? fill,
}) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radius.md),
        borderSide: BorderSide(color: color, width: width),
      );
  final idle = hasError
      ? border(ext.dangerBorder, t.borderWidth.hairline)
      : border(t.color.border.strong, t.borderWidth.hairline);
  final focused = border(hasError ? ext.dangerBorder : t.color.border.accent, t.borderWidth.thick);
  return InputDecoration(
    hintText: hint,
    hintStyle: kitTextStyle(t, t.typography.body, t.color.content.muted),
    filled: true,
    fillColor: fill ?? t.color.background.surface,
    prefixIcon: prefix,
    suffixIcon: suffix,
    contentPadding: EdgeInsets.symmetric(horizontal: t.spacing.md, vertical: t.spacing.sm),
    border: idle,
    enabledBorder: idle,
    focusedBorder: focused,
    errorBorder: border(ext.dangerBorder, t.borderWidth.hairline),
    focusedErrorBorder: focused,
  );
}
