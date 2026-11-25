import 'package:flutter/material.dart';

import '../theme/theme_tokens.dart';
import '../theme/token_ext.dart';

// Internal helpers for kit widgets. Not exported from ui.dart.

/// Text style built from a token type style. Font family follows the token set.
TextStyle kitTextStyle(
  ThemeTokens t,
  TypeStyleToken s,
  Color color, {
  bool display = false,
  bool mono = false,
}) {
  final family = display
      ? t.typography.displayFamily
      : mono
          ? t.typography.monoFamily
          : t.typography.bodyFamily;
  return TextStyle(
    fontFamily: family,
    fontSize: s.size,
    fontWeight: s.fontWeight,
    height: s.height,
    letterSpacing: s.letterSpacing,
    color: color,
  );
}

/// Input decoration shared by AppTextField and AppSelect. The border turns to
/// the danger colour when [hasError] is set, so error state is not colour alone
/// (FieldFrame also prints the message and an icon).
InputDecoration kitInputDecoration(
  ThemeTokens t,
  ExtTokens ext, {
  String? hint,
  Widget? prefix,
  Widget? suffix,
  bool hasError = false,
}) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.radius.md),
        borderSide: BorderSide(color: color, width: width),
      );

  final idle = hasError
      ? border(t.color.background.danger, t.borderWidth.thick)
      : border(t.color.border.standard, t.borderWidth.hairline);

  return InputDecoration(
    hintText: hint,
    hintStyle: kitTextStyle(t, t.typography.body, t.color.content.muted),
    filled: true,
    fillColor: t.color.background.surface,
    prefixIcon: prefix,
    suffixIcon: suffix,
    contentPadding: EdgeInsets.symmetric(
      horizontal: t.spacing.md,
      vertical: t.spacing.sm,
    ),
    border: idle,
    enabledBorder: idle,
    focusedBorder: border(t.color.border.focus, t.borderWidth.thick),
    errorBorder: border(t.color.background.danger, t.borderWidth.hairline),
    focusedErrorBorder: border(t.color.background.danger, t.borderWidth.thick),
  );
}
