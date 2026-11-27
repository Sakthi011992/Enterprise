import 'package:flutter/material.dart';

import '../theme/token_ext.dart';

/// Meaning of a status. Always paired with a word in the UI, never colour alone.
enum StatusTone { success, warning, danger, neutral, info }

/// Background, text and icon for one tone.
class ToneColors {
  const ToneColors({
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final Color background;
  final Color foreground;
  final IconData? icon;
}

/// Resolves a tone against the current brightness.
ToneColors toneColorsOf(BuildContext context, StatusTone tone) {
  final ext = context.ext;
  return switch (tone) {
    StatusTone.success => ToneColors(
        background: ext.successSubtle,
        foreground: ext.onSuccessSubtle,
        icon: Icons.check_circle_outline,
      ),
    StatusTone.warning => ToneColors(
        background: ext.warningSubtle,
        foreground: ext.onWarningSubtle,
        icon: Icons.warning_amber_outlined,
      ),
    StatusTone.danger => ToneColors(
        background: ext.dangerSubtle,
        foreground: ext.onDangerSubtle,
        icon: Icons.error_outline,
      ),
    StatusTone.neutral => ToneColors(
        background: ext.neutralSubtle,
        foreground: ext.onNeutralSubtle,
        icon: null,
      ),
    StatusTone.info => ToneColors(
        background: ext.infoSubtle,
        foreground: ext.onInfoSubtle,
        icon: Icons.info_outline,
      ),
  };
}
