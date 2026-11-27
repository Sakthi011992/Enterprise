import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/token_ext.dart';
import '../../../core/theme/theme_mode_toggle.dart';

/// Split sign-in layout: ink brand panel on the left (wide screens), form card on the right.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final form = Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(t.spacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) ...[
                Icon(Icons.point_of_sale, size: 44, color: t.color.background.accent),
                SizedBox(height: t.spacing.sm),
                Text(
                  'POS Billing',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                SizedBox(height: t.spacing.lg),
              ],
              Container(
                padding: EdgeInsets.all(t.spacing.lg),
                decoration: BoxDecoration(
                  color: t.color.background.raised,
                  borderRadius: BorderRadius.circular(t.radius.lg),
                  border: Border.all(color: t.color.border.standard),
                  boxShadow: ext.raisedShadow,
                ),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );

    // No app bar: the ink panel runs edge to edge; the theme toggle floats top-right.
    return Scaffold(
      backgroundColor: t.color.background.canvas,
      body: Stack(
        children: [
          Positioned.fill(
            child: wide
                ? Row(
                    children: [
                      const Expanded(flex: 5, child: _BrandPanel()),
                      Expanded(flex: 6, child: form),
                    ],
                  )
                : form,
          ),
          Positioned(
            top: t.spacing.sm,
            right: t.spacing.sm,
            child: const SafeArea(child: ThemeModeToggle()),
          ),
        ],
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final headingFamily = t.typography.displayFamily;
    return ClipRect(
      child: Container(
        color: t.color.background.inverse,
        child: Stack(
          children: [
            Positioned(
              left: -120,
              top: -120,
              child: _glow(t.color.background.accent.withValues(alpha: 0.18), 380),
            ),
            Positioned(
              right: -140,
              bottom: -140,
              child: _glow(t.color.background.accent.withValues(alpha: 0.12), 460),
            ),
            Padding(
              padding: EdgeInsets.all(t.spacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.point_of_sale, color: t.color.background.accent, size: 28),
                      SizedBox(width: t.spacing.sm),
                      Text(
                        'POS Billing',
                        style: AppFonts.apply(
                          headingFamily,
                          TextStyle(
                            color: t.color.content.onInverse,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    'Run the bar, the floor and the books from one place.',
                    style: AppFonts.apply(
                      headingFamily,
                      TextStyle(
                        color: t.color.content.onInverse,
                        fontSize: 44,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
