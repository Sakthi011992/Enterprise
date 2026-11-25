import 'package:flutter/material.dart';
import 'package:pos_billing/core/ui/ui.dart';

/// Asks for a persona name. Resolves to the trimmed name, or null if cancelled.
Future<String?> showPersonaNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PersonaNameDialog(title: title, confirmLabel: confirmLabel, initial: initial),
  );
}

class _PersonaNameDialog extends StatefulWidget {
  const _PersonaNameDialog({required this.title, required this.confirmLabel, required this.initial});

  final String title;
  final String confirmLabel;
  final String initial;

  @override
  State<_PersonaNameDialog> createState() => _PersonaNameDialogState();
}

class _PersonaNameDialogState extends State<_PersonaNameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: AppTextField(
          label: 'Persona name',
          controller: _controller,
          errorText: _error,
          autofocus: true,
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: widget.confirmLabel,
          variant: AppButtonVariant.primary,
          onPressed: _submit,
        ),
      ],
    );
  }
}
