import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'ui_style.dart';

/// Icon-only button with a tooltip (used as its accessible name). A
/// [badgeCount] above zero shows a danger badge with the count ("99+" above 99).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.badgeCount,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final button = IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
    );
    final count = badgeCount ?? 0;
    if (count <= 0) return button;
    return Badge(
      label: Text(
        count > 99 ? '99+' : '$count',
        style: kitTextStyle(t, t.typography.caption, t.color.content.onAccent),
      ),
      backgroundColor: t.color.background.danger,
      textColor: t.color.content.onAccent,
      child: button,
    );
  }
}
