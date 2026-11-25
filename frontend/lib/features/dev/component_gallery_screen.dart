import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_mode_toggle.dart';
import '../../core/theme/theme_providers.dart';
import '../../core/theme/theme_tokens.dart';
import '../../core/ui/ui.dart';
import '../../core/ui/ui_style.dart';

/// Debug-only page that shows every kit widget in each variant and state, in
/// light and dark, at three densities. Mounted at /dev/components.
class ComponentGalleryScreen extends ConsumerWidget {
  const ComponentGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appTokens = ref.watch(themeControllerProvider).tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Component gallery'),
        actions: const [ThemeModeToggle()],
      ),
      body: appTokens == null
          ? const SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: GallerySections(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ModePanel(modeLabel: 'Light', brightness: Brightness.light, appTokens: appTokens),
                const SizedBox(height: 24),
                _ModePanel(modeLabel: 'Dark', brightness: Brightness.dark, appTokens: appTokens),
              ],
            ),
    );
  }
}

/// Renders the sections with the given brightness, so light and dark can sit
/// side by side even when the app is in one mode.
class _ModePanel extends StatelessWidget {
  const _ModePanel({
    required this.modeLabel,
    required this.brightness,
    required this.appTokens,
  });

  final String modeLabel;
  final Brightness brightness;
  final AppThemeTokens appTokens;

  @override
  Widget build(BuildContext context) {
    final modeTokens = appTokens.forBrightness(brightness);
    return TokenTheme(
      tokens: modeTokens,
      child: Theme(
        data: AppTheme.from(modeTokens, brightness),
        child: Builder(
          builder: (inner) {
            final t = inner.tokens;
            return Container(
              color: t.color.background.canvas,
              padding: EdgeInsets.all(t.spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$modeLabel mode', style: Theme.of(inner).textTheme.titleLarge),
                  SizedBox(height: t.spacing.md),
                  const GallerySections(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class GallerySections extends StatefulWidget {
  const GallerySections({super.key});

  @override
  State<GallerySections> createState() => _GallerySectionsState();
}

const _sampleItems = <String>['Masala dosa', 'Filter coffee', 'Lime soda'];

class _GallerySectionsState extends State<GallerySections> {
  String? _outlet = 'main';
  String? _pinError;
  Set<String> _selected = {};

  Widget _label(BuildContext context, String text) {
    final t = context.tokens;
    return Text(
      text,
      style: kitTextStyle(t, t.typography.label, t.color.content.secondary),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: t.spacing.sm),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = SizedBox(height: t.spacing.sm);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _section(context, 'Buttons', [
          for (final density in AppDensity.values)
            DensityScope(
              density: density,
              child: Padding(
                padding: EdgeInsets.only(bottom: t.spacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _label(context, density.name),
                    SizedBox(height: t.spacing.xs),
                    Wrap(
                      spacing: t.spacing.sm,
                      runSpacing: t.spacing.sm,
                      children: [
                        for (final variant in AppButtonVariant.values)
                          AppButton(label: variant.name, variant: variant, onPressed: () {}),
                        AppButton(
                          label: 'Loading',
                          variant: AppButtonVariant.primary,
                          loading: true,
                          onPressed: () {},
                        ),
                        const AppButton(label: 'Disabled', variant: AppButtonVariant.primary),
                        AppButton(label: 'With icon', icon: Icons.add, onPressed: () {}),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ]),
        _section(context, 'Icon buttons', [
          Wrap(
            spacing: t.spacing.sm,
            children: [
              AppIconButton(icon: Icons.notifications_outlined, tooltip: 'Notifications', badgeCount: 3, onPressed: () {}),
              AppIconButton(icon: Icons.notifications_outlined, tooltip: 'Notifications, 120 unread', badgeCount: 120, onPressed: () {}),
              AppIconButton(icon: Icons.refresh, tooltip: 'Refresh', onPressed: () {}),
              const AppIconButton(icon: Icons.delete_outline, tooltip: 'Delete (disabled)'),
            ],
          ),
        ]),
        _section(context, 'Text fields and selects', [
          Wrap(
            spacing: t.spacing.md,
            runSpacing: t.spacing.md,
            children: [
              const SizedBox(width: 280, child: AppTextField(label: 'Username', hint: 'e.g. priya')),
              const SizedBox(
                width: 280,
                child: AppTextField(label: 'Email', helperText: 'Used for password resets.'),
              ),
              const SizedBox(
                width: 280,
                child: AppTextField(label: 'Phone', errorText: 'Enter a 10-digit number.'),
              ),
              SizedBox(
                width: 280,
                child: AppTextField(
                  label: 'Password',
                  obscure: true,
                  prefix: const Icon(Icons.lock_outline),
                  suffix: const Icon(Icons.visibility_outlined),
                ),
              ),
              SizedBox(
                width: 280,
                child: AppSelect<String>(
                  label: 'Outlet',
                  value: _outlet,
                  items: [
                    AppSelectItem('main', 'Main outlet'),
                    AppSelectItem('branch', 'Branch, RS Puram'),
                  ],
                  onChanged: (v) => setState(() => _outlet = v),
                ),
              ),
            ],
          ),
        ]),
        _section(context, 'Status badges', [
          Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.sm,
            children: [
              for (final tone in StatusTone.values)
                StatusBadge(label: tone.name, tone: tone),
            ],
          ),
        ]),
        _section(context, 'Alerts and banners', [
          InlineAlert(
            message: 'Wrong username or password.',
            actionLabel: 'Retry',
            onAction: () {},
          ),
          gap,
          const InlineAlert(message: 'Saved.', tone: StatusTone.success),
          gap,
          const InlineAlert(message: 'Stock is running low.', tone: StatusTone.warning),
          gap,
          const InlineAlert(message: 'Nightly sync is scheduled.', tone: StatusTone.info),
          gap,
          const AppBanner(message: 'Offline. Changes will sync when you reconnect.'),
          gap,
          AppButton(
            label: 'Show toast',
            onPressed: () => showAppToast(
              context,
              'Order 1042 deleted',
              actionLabel: 'Undo',
              onAction: () {},
            ),
          ),
        ]),
        _section(context, 'States', [
          AppCard(
            title: 'Empty',
            child: SizedBox(
              width: 360,
              child: EmptyState(
                title: 'Nothing here yet',
                message: 'Add your first product to start billing.',
                actionLabel: 'Add product',
                onAction: () {},
              ),
            ),
          ),
          gap,
          AppCard(
            title: 'Error',
            child: SizedBox(
              width: 360,
              child: ErrorState(message: 'Network timed out.', onRetry: () {}),
            ),
          ),
          gap,
          AppCard(
            title: 'Skeleton',
            child: SizedBox(width: 360, child: SkeletonList(rows: 3)),
          ),
        ]),
        _section(context, 'Page header and card', [
          PageHeader(
            title: 'Products',
            breadcrumb: 'Menu & stock',
            actions: [
              AppButton(
                label: 'Add product',
                icon: Icons.add,
                variant: AppButtonVariant.primary,
                onPressed: () {},
              ),
            ],
          ),
          AppCard(
            title: 'Summary',
            actions: [
              AppButton(label: 'Edit', variant: AppButtonVariant.ghost, onPressed: () {}),
            ],
            child: const Text('Card body text.'),
          ),
        ]),
        _section(context, 'Data table', [
          AppDataTable<String>(
            columns: [
              AppColumn<String>(label: 'Item', cell: (row) => Text(row)),
              AppColumn<String>(
                label: 'Status',
                width: 140,
                cell: (row) => const StatusBadge(label: 'Active', tone: StatusTone.success),
              ),
            ],
            rows: _sampleItems,
            searchHint: 'Search items',
            onSearch: (_) {},
            selected: _selected,
            onSelectionChanged: (s) => setState(() => _selected = s),
            bulkActions: [
              AppButton(label: 'Deactivate', onPressed: () {}),
              AppButton(label: 'Delete', variant: AppButtonVariant.danger, onPressed: () {}),
            ],
            onRowTap: (_) {},
          ),
        ]),
        _section(context, 'Confirm dialog', [
          AppButton(
            label: 'Delete item',
            variant: AppButtonVariant.danger,
            onPressed: () async {
              final ok = await showConfirmDialog(
                context,
                title: 'Delete this item?',
                message: 'This cannot be undone.',
                confirmLabel: 'Delete',
                destructive: true,
              );
              if (!context.mounted) return;
              if (ok) showAppToast(context, 'Item deleted');
            },
          ),
        ]),
        _section(context, 'PIN pad', [
          SizedBox(
            width: 260,
            child: PinPad(
              length: 4,
              errorText: _pinError,
              onCompleted: (pin) => setState(() {
                _pinError = pin == '2580' ? null : 'Wrong PIN. 2 attempts left.';
              }),
            ),
          ),
        ]),
      ],
    );
  }
}
