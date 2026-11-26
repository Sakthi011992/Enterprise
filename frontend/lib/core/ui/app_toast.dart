import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui_style.dart';

/// Shows a floating snackbar on ink (inverse) with an accent action. Does
/// nothing when there is no ScaffoldMessenger above [context]. The optional
/// action (for example "Undo") runs [onAction].
void showAppToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final t = context.tokens;
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.color.background.inverse,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius.md)),
      content: Text(
        message,
        style: kitTextStyle(t, t.typography.body, t.color.content.onInverse),
      ),
      action: actionLabel == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              textColor: t.color.border.accent,
              onPressed: onAction ?? () {},
            ),
    ),
  );
}
