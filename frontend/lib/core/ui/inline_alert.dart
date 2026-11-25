import 'package:flutter/material.dart';

import 'status_tone.dart';
import 'tone_bar.dart';

/// Rounded message inside a page or a form. Defaults to the danger tone.
class InlineAlert extends StatelessWidget {
  const InlineAlert({
    super.key,
    required this.message,
    this.tone = StatusTone.danger,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final StatusTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ToneBar(
        message: message,
        tone: tone,
        actionLabel: actionLabel,
        onAction: onAction,
      );
}
