import 'package:flutter/material.dart';

/// Shows a floating snackbar. Does nothing when there is no ScaffoldMessenger
/// above [context]. The optional action (for example "Undo") runs [onAction].
void showAppToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
}
