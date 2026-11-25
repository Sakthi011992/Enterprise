import 'package:flutter/material.dart';

import 'app_button.dart';

/// Asks a yes/no question in a dialog. Resolves to true only when the confirm
/// button is pressed. Dismissing the dialog counts as false.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        AppButton(
          label: confirmLabel,
          variant: destructive ? AppButtonVariant.danger : AppButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}
