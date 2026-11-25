import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/core/ui/ui.dart';
import 'package:pos_billing/features/personas/data/admin_api.dart';

/// Set a 4-digit staff PIN. [onSubmit] makes the call; errors such as PIN_TOO_SIMPLE show in the dialog.
/// Resolves to true when the PIN was saved.
Future<bool> showSetPinDialog(
  BuildContext context, {
  required Future<void> Function(String pin) onSubmit,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _SecretDialog(
      title: 'Set PIN',
      firstLabel: 'New PIN',
      confirmLabel: 'Repeat PIN',
      helper: 'Four digits. Staff type this on the shared tablet.',
      submitLabel: 'Set PIN',
      obscure: true,
      numeric: true,
      sanitize: (raw) {
        final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
        return digits.length > 4 ? digits.substring(0, 4) : digits;
      },
      validate: (v) => v.length == 4 ? null : 'Enter exactly 4 digits',
      onSubmit: onSubmit,
    ),
  );
  return saved == true;
}

/// Admin reset of a user's password (min 6 characters, per the admin API).
Future<bool> showResetPasswordDialog(
  BuildContext context, {
  required Future<void> Function(String password) onSubmit,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _SecretDialog(
      title: 'Reset password',
      firstLabel: 'New password',
      confirmLabel: 'Repeat new password',
      helper: 'At least 6 characters. The user is signed out everywhere.',
      submitLabel: 'Reset password',
      obscure: true,
      numeric: false,
      sanitize: (raw) => raw,
      validate: (v) => v.length >= 6 ? null : 'Use at least 6 characters',
      onSubmit: onSubmit,
    ),
  );
  return saved == true;
}

class _SecretDialog extends StatefulWidget {
  const _SecretDialog({
    required this.title,
    required this.firstLabel,
    required this.confirmLabel,
    required this.helper,
    required this.submitLabel,
    required this.obscure,
    required this.numeric,
    required this.sanitize,
    required this.validate,
    required this.onSubmit,
  });

  final String title;
  final String firstLabel;
  final String confirmLabel;
  final String helper;
  final String submitLabel;
  final bool obscure;
  final bool numeric;
  final String Function(String raw) sanitize;
  final String? Function(String value) validate;
  final Future<void> Function(String value) onSubmit;

  @override
  State<_SecretDialog> createState() => _SecretDialogState();
}

class _SecretDialogState extends State<_SecretDialog> {
  final _first = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _first.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Applies the sanitiser as the person types, keeping the caret at the end.
  void _onChanged(TextEditingController c, String raw) {
    final cleaned = widget.sanitize(raw);
    if (cleaned != raw) {
      c.value = TextEditingValue(text: cleaned, selection: TextSelection.collapsed(offset: cleaned.length));
    }
    setState(() => _error = null);
  }

  Future<void> _submit() async {
    final value = _first.text;
    final problem = widget.validate(value) ?? (_confirm.text == value ? null : 'The two entries do not match');
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(value);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = AdminApiError.from(e).friendly;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: context.tokens.spacing.md);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              InlineAlert(message: _error!),
              gap,
            ],
            AppTextField(
              label: widget.firstLabel,
              controller: _first,
              obscure: widget.obscure,
              autofocus: true,
              keyboardType: widget.numeric ? TextInputType.number : null,
              helperText: widget.helper,
              onChanged: (v) => _onChanged(_first, v),
            ),
            gap,
            AppTextField(
              label: widget.confirmLabel,
              controller: _confirm,
              obscure: widget.obscure,
              keyboardType: widget.numeric ? TextInputType.number : null,
              onChanged: (v) => _onChanged(_confirm, v),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: _saving ? 'Saving…' : widget.submitLabel,
          variant: AppButtonVariant.primary,
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}
