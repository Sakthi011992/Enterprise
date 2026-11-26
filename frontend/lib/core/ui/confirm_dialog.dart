import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_button.dart';
import 'ui_style.dart';

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
    builder: (dialogContext) {
      final t = dialogContext.tokens;
      return AlertDialog(
      backgroundColor: t.color.background.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius.lg),
        side: BorderSide(color: t.color.border.standard, width: t.borderWidth.hairline),
      ),
      titlePadding: EdgeInsets.fromLTRB(t.spacing.lg, t.spacing.lg, t.spacing.lg, t.spacing.xs),
      contentPadding: EdgeInsets.fromLTRB(t.spacing.lg, 0, t.spacing.lg, t.spacing.md),
      actionsPadding: EdgeInsets.fromLTRB(t.spacing.lg, 0, t.spacing.lg, t.spacing.lg),
      title: Text(
        title,
        style: kitTextStyle(t, t.typography.title, t.color.content.primary, display: true),
      ),
      content: Text(
        message,
        style: kitTextStyle(t, t.typography.body, t.color.content.secondary),
      ),
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
    );
    },
  );
  return result ?? false;
}
