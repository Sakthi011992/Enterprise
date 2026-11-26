import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/token_ext.dart';
import '../../../core/ui/ui.dart';

final _dashboardProvider = FutureProvider<Map>((ref) async {
  final dio = ref.watch(dioProvider);
  final results = await Future.wait([
    dio.get('/reports/dashboard'),
    dio.get('/reports/top-products', queryParameters: {'limit': 5}),
    dio.get('/reports/recent-orders', queryParameters: {'limit': 5}),
  ]);
  return {
    'summary': results[0].data,
    'top': (results[1].data as List).cast<Map>(),
    'recent': (results[2].data as List).cast<Map>(),
  };
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_dashboardProvider);
    return Scaffold(
      backgroundColor: context.tokens.color.background.canvas,
      // Page header in the body (28/700 Manrope); dark mode lives in the shell's top bar.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.tokens.spacing.lg,
              context.tokens.spacing.lg,
              context.tokens.spacing.lg,
              0,
            ),
            child: PageHeader(
              title: 'Dashboard',
              breadcrumb: 'Overview',
              actions: [
                AppButton(
                  label: 'Refresh',
                  icon: Icons.refresh,
                  onPressed: () => ref.invalidate(_dashboardProvider),
                ),
              ],
            ),
          ),
          Expanded(child: _body(context, data)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, AsyncValue<Map> data) {
    return data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (d) {
          final s = d['summary'] as Map;
          final today = s['today'] as Map;
          final monthly = s['monthly'] as Map;
          final top = d['top'] as List;
          final recent = d['recent'] as List;
          final t = context.tokens;
          final ext = context.ext;
          final text = Theme.of(context).textTheme;
          final labelStyle = text.labelSmall?.copyWith(color: t.color.content.secondary);
          return ListView(
            padding: EdgeInsets.all(t.spacing.lg),
            children: [
              _panel(
                context,
                child: LayoutBuilder(builder: (context, c) {
                  final hero = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Today Revenue', style: text.bodySmall?.copyWith(color: t.color.content.secondary)),
                    SizedBox(height: t.spacing.xs),
                    Text(
                      '₹${today['revenue']}',
                      style: AppFonts.apply(
                        t.typography.displayFamily,
                        TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: t.color.content.primary,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ),
                  ]);
                  final others = [
                    _metric(context, 'Today Orders', '${today['ordersCount']}'),
                    _metric(context, 'Today Tax', '₹${today['taxCollected']}'),
                    _metric(context, 'Month Revenue', '₹${monthly['revenue']}'),
                    _metric(context, 'Month Tax', '₹${monthly['taxCollected']}'),
                  ];
                  if (c.maxWidth < 720) {
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      hero,
                      SizedBox(height: t.spacing.md),
                      Wrap(spacing: t.spacing.lg, runSpacing: t.spacing.md, children: others),
                    ]);
                  }
                  return IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(flex: 2, child: hero),
                      for (final m in others) ...[
                        VerticalDivider(width: t.spacing.lg * 2, color: t.color.border.subtle),
                        Expanded(child: m),
                      ],
                    ]),
                  );
                }),
              ),
              SizedBox(height: t.spacing.lg),
              _panel(
                context,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Top Selling Products', style: text.titleMedium),
                  SizedBox(height: t.spacing.sm),
                  Container(
                    color: ext.subtleFill,
                    padding: EdgeInsets.symmetric(horizontal: t.spacing.sm, vertical: t.spacing.xs),
                    child: Row(children: [
                      Expanded(child: Text('Product', style: labelStyle)),
                      Text('Sold · Revenue', style: labelStyle),
                    ]),
                  ),
                  ...top.map((p) => _row(
                        context,
                        Row(children: [
                          Expanded(child: Text(p['productName'] as String)),
                          Text('${p['quantitySold']} sold · ₹${p['revenue']}'),
                        ]),
                      )),
                ]),
              ),
              SizedBox(height: t.spacing.lg),
              _panel(
                context,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Recent Orders', style: text.titleMedium),
                  SizedBox(height: t.spacing.sm),
                  ...recent.map((o) => _row(
                        context,
                        Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text((o['invoiceNumber'] ?? o['orderNumber'] ?? '—') as String),
                              Text(o['status'] as String,
                                  style: text.bodySmall?.copyWith(color: t.color.content.muted)),
                            ]),
                          ),
                          Text('₹${o['grandTotal']}'),
                        ]),
                      )),
                ]),
              ),
            ],
          );
        },
      );
  }

  Widget _row(BuildContext context, Widget child) {
    final t = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.spacing.sm, vertical: t.spacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.color.border.subtle)),
      ),
      child: child,
    );
  }

  Widget _panel(BuildContext context, {required Widget child}) {
    final t = context.tokens;
    return Container(
      padding: EdgeInsets.all(t.spacing.lg),
      decoration: BoxDecoration(
        color: t.color.background.raised,
        borderRadius: BorderRadius.circular(t.radius.lg),
        border: Border.all(color: t.color.border.standard),
        boxShadow: context.ext.cardShadow,
      ),
      child: child,
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    final t = context.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: t.color.content.secondary)),
      SizedBox(height: t.spacing.xs),
      Text(
        value,
        overflow: TextOverflow.ellipsis,
        style: AppFonts.apply(
          t.typography.displayFamily,
          TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: t.color.content.primary,
            fontFeatures: kTabularFigures,
          ),
        ),
      ),
    ]);
  }
}
