import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode_toggle.dart';
import '../../../core/ui/ui.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _paymentConfigProvider = FutureProvider<List<Map>>((ref) async {
  final res = await ref.watch(dioProvider).get('/payments/methods/default/config');
  return (res.data as List).cast<Map>();
});

final _loginMethodsProvider = FutureProvider<List<Map>>((ref) async {
  final res = await ref.watch(dioProvider).get('/auth/login-methods/config');
  return (res.data as List).cast<Map>();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Settings',
              actions: [
                AppButton(
                  label: 'Feature configuration › Guest ordering',
                  icon: Icons.qr_code_2,
                  onPressed: () => context.go('/settings/guest-ordering'),
                ),
                const ThemeModeToggle(),
              ],
            ),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Payment Methods'),
                Tab(text: 'Login Methods'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [
                  _PaymentMethodsTab(),
                  _LoginMethodsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment Methods Tab
// ---------------------------------------------------------------------------

const _paymentLabels = {
  'CASH': ('Cash', Icons.money),
  'UPI': ('UPI / QR', Icons.qr_code),
  'CARD': ('Card', Icons.credit_card),
};

class _PaymentMethodsTab extends ConsumerWidget {
  const _PaymentMethodsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(_paymentConfigProvider);
    final t = context.tokens;
    return config.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (methods) => ListView(
        padding: EdgeInsets.all(t.spacing.md),
        children: [
          Text(
            'Enable or disable payment methods for all checkout flows.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: t.color.content.secondary),
          ),
          SizedBox(height: t.spacing.md),
          Card(
            child: Column(
              children: methods.map((m) {
                final method = m['method'] as String;
                final enabled = m['enabled'] as bool;
                final info = _paymentLabels[method];
                return SwitchListTile(
                  secondary: Icon(info?.$2 ?? Icons.payment),
                  title: Text(info?.$1 ?? method),
                  subtitle: Text(enabled ? 'Enabled' : 'Disabled'),
                  value: enabled,
                  onChanged: (v) => _toggle(context, ref, method, v),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, String method, bool enabled) async {
    try {
      await ref.read(dioProvider).post(
        '/payments/methods/default/config',
        data: {'method': method, 'enabled': enabled},
      );
      ref.invalidate(_paymentConfigProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Login Methods Tab
// ---------------------------------------------------------------------------

const _loginLabels = {
  'STATIC': ('Username & Password', Icons.person, 'Standard login form'),
  'GOOGLE': ('Google Sign-In', Icons.g_mobiledata, 'OAuth 2.0 via Google ID token'),
};

class _LoginMethodsTab extends ConsumerWidget {
  const _LoginMethodsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(_loginMethodsProvider);
    final t = context.tokens;
    return config.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (methods) => ListView(
        padding: EdgeInsets.all(t.spacing.md),
        children: [
          Text(
            'Choose which login methods are available on the login screen.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: t.color.content.secondary),
          ),
          SizedBox(height: t.spacing.md),
          Card(
            child: Column(
              children: methods.map((m) {
                final method = m['method'] as String;
                final enabled = m['enabled'] as bool;
                final info = _loginLabels[method];
                return SwitchListTile(
                  secondary: Icon(info?.$2 ?? Icons.login),
                  title: Text(info?.$1 ?? method),
                  subtitle: Text(info?.$3 ?? ''),
                  value: enabled,
                  onChanged: (v) => _toggle(context, ref, method, v),
                );
              }).toList(),
            ),
          ),
          SizedBox(height: t.spacing.md),
          Card(
            color: t.color.background.surface,
            child: Padding(
              padding: EdgeInsets.all(t.spacing.md),
              child: Row(children: [
                Icon(Icons.info_outline, size: 18, color: t.color.content.secondary),
                SizedBox(width: t.spacing.sm),
                Expanded(
                  child: Text(
                    'Keep at least one method enabled. Disabling all login methods will lock out users.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: t.color.content.secondary),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, String method, bool enabled) async {
    try {
      await ref.read(dioProvider).post(
        '/auth/login-methods/config/$method',
        data: {'enabled': enabled},
      );
      ref.invalidate(_loginMethodsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}
