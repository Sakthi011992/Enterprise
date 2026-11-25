import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/token_ext.dart';
import 'field_frame.dart';
import 'ui_style.dart';

/// Text input with the label above and the error or helper text below.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.errorText,
    this.helperText,
    this.obscure = false,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.prefix,
    this.suffix,
    this.autofocus = false,
    this.autofillHints,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? errorText;
  final String? helperText;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefix;
  final Widget? suffix;
  final bool autofocus;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    final err = errorText;
    return FieldFrame(
      label: label,
      errorText: err,
      helperText: helperText,
      minHeight: ext.controlHeight(ext.defaultControlSize),
      child: Semantics(
        textField: true,
        label: label,
        child: TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          autofocus: autofocus,
          autofillHints: autofillHints,
          style: kitTextStyle(t, t.typography.body, t.color.content.primary),
          decoration: kitInputDecoration(
            t,
            ext,
            hint: hint,
            prefix: prefix,
            suffix: suffix,
            hasError: err != null && err.isNotEmpty,
          ),
        ),
      ),
    );
  }
}
