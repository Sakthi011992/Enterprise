import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/token_ext.dart';
import 'field_frame.dart';
import 'ui_style.dart';

/// One option for [AppSelect]: a value and its visible label.
class AppSelectItem<T> {
  const AppSelectItem(this.value, this.label);

  final T value;
  final String label;
}

/// Dropdown with the same label, border and error treatment as AppTextField.
class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final T? value;
  final List<AppSelectItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    final err = errorText;
    return FieldFrame(
      label: label,
      errorText: err,
      minHeight: ext.controlHeight(ext.defaultControlSize),
      child: Semantics(
        label: label,
        child: DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          dropdownColor: t.color.background.raised,
          style: kitTextStyle(t, t.typography.body, t.color.content.primary),
          decoration: fieldDecoration(
            t,
            ext,
            hasError: err != null && err.isNotEmpty,
          ),
          items: [
            for (final item in items)
              DropdownMenuItem<T>(
                value: item.value,
                child: Text(item.label),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
