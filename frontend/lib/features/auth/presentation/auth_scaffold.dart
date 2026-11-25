import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode_toggle.dart';

/// Centred single column used by every sign-in screen.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        actions: const [ThemeModeToggle()],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(t.spacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.point_of_sale, size: 56, color: t.color.background.accent),
                SizedBox(height: t.spacing.sm),
                Text(
                  'POS Billing',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                SizedBox(height: t.spacing.xl),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
