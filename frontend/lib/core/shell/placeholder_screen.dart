import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../ui/ui.dart';

/// Stand-in page for nav items that ship in a later phase.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.all(t.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: title),
          Expanded(
            child: EmptyState(
              title: 'Coming in a later phase',
              message: '$title will appear here once it is built.',
              icon: Icons.schedule_outlined,
            ),
          ),
        ],
      ),
    );
  }
}
