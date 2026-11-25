import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/ui.dart';
import 'auth_scaffold.dart';

/// Shown after a password login when the user belongs to several outlets.
class OutletPickerScreen extends ConsumerWidget {
  const OutletPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final state = ref.watch(sessionProvider);
    final choice = state.pendingOutletChoice;

    if (choice == null) {
      return AuthScaffold(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EmptyState(title: 'No outlet to choose', message: 'Sign in again to continue.'),
            SizedBox(height: t.spacing.md),
            AppButton(
              label: 'Back to sign in',
              variant: AppButtonVariant.primary,
              onPressed: () => context.go('/login'),
            ),
          ],
        ),
      );
    }

    final outlets = choice.outlets;
    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose an outlet',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: t.spacing.xs),
          Text(
            'You work at more than one outlet. Pick where you are today.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.color.content.secondary),
          ),
          SizedBox(height: t.spacing.md),
          if (state.error != null) ...[
            InlineAlert(message: state.error!, tone: StatusTone.danger),
            SizedBox(height: t.spacing.md),
          ],
          if (state.loading) ...[
            const LinearProgressIndicator(),
            SizedBox(height: t.spacing.md),
          ],
          if (outlets.isEmpty)
            EmptyState(title: 'No outlets', message: 'Ask your admin to link you to an outlet.')
          else
            for (final outlet in outlets) ...[
              _OutletCard(
                outlet: outlet,
                enabled: !state.loading,
                onTap: () => ref.read(sessionProvider.notifier).selectOutlet(outlet.id),
              ),
              SizedBox(height: t.spacing.sm),
            ],
          SizedBox(height: t.spacing.sm),
          AppButton(
            label: 'Back to sign in',
            variant: AppButtonVariant.ghost,
            onPressed: () {
              ref.read(sessionProvider.notifier).cancelOutletChoice();
              context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}

class _OutletCard extends StatelessWidget {
  const _OutletCard({required this.outlet, required this.enabled, required this.onTap});

  final OutletAccess outlet;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radius.md),
        onTap: enabled ? onTap : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(outlet.name, style: Theme.of(context).textTheme.titleSmall),
                  Text(outlet.code, style: TextStyle(color: t.color.content.muted)),
                ],
              ),
            ),
            StatusBadge(label: outlet.persona.name),
            Icon(Icons.chevron_right, color: t.color.content.secondary),
          ],
        ),
      ),
    );
  }
}
