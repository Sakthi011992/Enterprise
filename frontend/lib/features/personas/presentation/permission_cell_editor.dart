import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_billing/core/auth/session.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/core/ui/ui.dart';

import '../data/persona_models.dart';

/// Opens the editor for one matrix cell. Resolves to the new grant, or null if cancelled.
Future<PersonaGrant?> showPermissionCellEditor(
  BuildContext context, {
  required CatalogEntry entry,
  required PersonaGrant current,
}) {
  return showDialog<PersonaGrant>(
    context: context,
    builder: (_) => _PermissionCellEditor(entry: entry, current: current),
  );
}

/// Keeps digits and one decimal point, and caps the value at [max] when given.
String sanitizeLimitInput(String raw, {double? max}) {
  var text = raw.replaceAll(RegExp(r'[^0-9.]'), '');
  final parts = text.split('.');
  if (parts.length > 2) text = '${parts.first}.${parts.sublist(1).join()}';
  if (max != null) {
    final value = double.tryParse(text);
    if (value != null && value > max) text = formatNumber(max);
  }
  return text;
}

class _PermissionCellEditor extends StatefulWidget {
  const _PermissionCellEditor({required this.entry, required this.current});

  final CatalogEntry entry;
  final PersonaGrant current;

  @override
  State<_PermissionCellEditor> createState() => _PermissionCellEditorState();
}

class _PermissionCellEditorState extends State<_PermissionCellEditor> {
  late AccessLevel _level = widget.current.level;
  late final TextEditingController _limit = TextEditingController(
    text: widget.current.limit == null ? '' : formatNumber(widget.current.limit!),
  );
  String? _limitError;

  String? get _unit => widget.entry.limitUnit;

  /// Only the percent unit has a natural ceiling; rupee limits are open-ended.
  double? get _max => _unit == 'percent' ? 100 : null;

  bool get _needsLimit => _level == AccessLevel.limited && _unit != null;

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  void _onLimitChanged(String raw) {
    final cleaned = sanitizeLimitInput(raw, max: _max);
    if (cleaned != raw) {
      _limit.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
    setState(() => _limitError = null);
  }

  void _apply() {
    num? limit;
    if (_needsLimit) {
      final parsed = double.tryParse(_limit.text);
      if (parsed == null || parsed <= 0) {
        setState(() => _limitError = 'Enter a limit above 0');
        return;
      }
      limit = parsed % 1 == 0 ? parsed.toInt() : parsed;
    }
    Navigator.of(context).pop(PersonaGrant(key: widget.entry.key, level: _level, limit: limit));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final unit = _unit;
    final levels = <AppSelectItem<AccessLevel>>[
      for (final level in AccessLevel.values) AppSelectItem(level, levelLabel(level)),
    ];
    return AlertDialog(
      title: Text(widget.entry.label),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.entry.description != null) ...[
              Text(widget.entry.description!, style: Theme.of(context).textTheme.bodySmall),
              SizedBox(height: t.spacing.md),
            ],
            AppSelect<AccessLevel>(
              label: 'Access',
              value: _level,
              items: levels,
              onChanged: (v) {
                if (v != null) setState(() => _level = v);
              },
            ),
            if (_needsLimit) ...[
              SizedBox(height: t.spacing.md),
              AppTextField(
                label: unit == 'percent' ? 'Limit (%)' : 'Limit (₹)',
                controller: _limit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                helperText: unit == 'percent' ? 'Up to 100%' : 'Up to this amount',
                errorText: _limitError,
                onChanged: _onLimitChanged,
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Apply',
          variant: AppButtonVariant.primary,
          onPressed: _apply,
        ),
      ],
    );
  }
}
