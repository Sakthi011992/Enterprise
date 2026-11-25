import 'package:flutter/material.dart';

import 'status_tone.dart';
import 'tone_bar.dart';

/// Full-width strip above page content. Defaults to the warning tone.
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.message,
    this.tone = StatusTone.warning,
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
        banner: true,
      );
}
