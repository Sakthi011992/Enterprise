import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../data/day_close_repository.dart';
import '../domain/cash_variance.dart';

const _cardWidth = 430.0;

/// Reports > Day close. X report is live and saves nothing. Z report closes the
/// business date with the counted cash.
class DayCloseScreen extends ConsumerStatefulWidget {
  const DayCloseScreen({super.key});

  @override
  ConsumerState<DayCloseScreen> createState() => _DayCloseScreenState();
}

class _DayCloseScreenState extends ConsumerState<DayCloseScreen> {
  final _counted = TextEditingController();
  String? _countedError;
  String? _error;
  bool _closing = false;

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(xReportProvider);
    ref.invalidate(dayClosesProvider);
  }

  Future<void> _closeDay(String expected) async {
    final counted = double.tryParse(_counted.text.trim());
    setState(() {
      _error = null;
      _countedError = (counted == null || counted < 0) ? 'Enter the cash you counted, such as 4250.00' : null;
    });
    if (_countedError != null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Close the day?',
      message: 'Expected cash is ₹$expected and you counted ₹${counted!.toStringAsFixed(2)}. '
          'Orders for this business date are locked after closing.',
      confirmLabel: 'Close day',
      destructive: true,
    );
    if (!ok) return;
    await _submit(counted!.toStringAsFixed(2), force: false);
  }

  Future<void> _submit(String counted, {required bool force}) async {
    setState(() => _closing = true);
    try {
      await ref.read(dayCloseRepositoryProvider).closeDay(cashCounted: counted, force: force);
      _counted.clear();
      _refresh();
      if (mounted) showAppToast(context, 'Day closed');
    } catch (e) {
      final err = ApiError.from(e);
      if (err.code == 'OPEN_ORDERS_EXIST' && !force) {
        final count = err.intDetail('count') ?? 0;
        if (!mounted) return;
        final ok = await showConfirmDialog(
          context,
          title: 'Orders still open',
          message: '$count ${count == 1 ? 'order is' : 'orders are'} still open. Close the day anyway?',
          confirmLabel: 'Close anyway',
          destructive: true,
        );
        if (ok) await _submit(counted, force: true);
      } else if (mounted) {
        setState(() => _error = err.code == 'DAY_ALREADY_CLOSED'
            ? 'This business date is already closed.'
            : err.message);
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final x = ref.watch(xReportProvider);
    final closes = ref.watch(dayClosesProvider);
    final canClose = can(ref, Perm.reportsView, AccessLevel.edit);
    final expected = x.valueOrNull?.cashExpected;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: ListView(
          children: [
            PageHeader(
              title: 'Day close',
              breadcrumb: 'Sales',
              actions: [
                AppButton(
                  label: 'Refresh',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.ghost,
                  onPressed: _refresh,
                ),
              ],
            ),
            if (_error != null) ...[
              SizedBox(height: t.spacing.sm),
              InlineAlert(message: _error!),
            ],
            SizedBox(height: t.spacing.md),
            Wrap(
              spacing: t.spacing.md,
              runSpacing: t.spacing.md,
              children: [
                SizedBox(
                  width: _cardWidth,
                  child: AppCard(
                    title: 'X report · live',
                    child: x.when(
                      loading: () => DelayedSkeleton(child: SkeletonList(rows: 6)),
                      error: (e, _) => ErrorState(
                        message: ApiError.from(e).message,
                        onRetry: () => ref.invalidate(xReportProvider),
                      ),
                      data: (s) => _XReportView(summary: s),
                    ),
                  ),
                ),
                SizedBox(
                  width: _cardWidth,
                  child: AppCard(
                    title: 'Z report · close the day',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Line(label: 'Expected cash', value: expected == null ? '…' : '₹$expected'),
                        SizedBox(height: t.spacing.sm),
                        AppTextField(
                          label: 'Cash counted',
                          controller: _counted,
                          keyboardType: TextInputType.number,
                          errorText: _countedError,
                          hint: '0.00',
                          prefix: const Padding(padding: EdgeInsets.only(left: 12), child: Text('₹')),
                          onChanged: (_) => setState(() {}),
                        ),
                        SizedBox(height: t.spacing.sm),
                        _VarianceText(expected: expected, counted: _counted.text),
                        SizedBox(height: t.spacing.md),
                        if (canClose)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: AppButton(
                              label: 'Close day',
                              variant: AppButtonVariant.primary,
                              loading: _closing,
                              onPressed: expected == null ? null : () => _closeDay(expected),
                            ),
                          )
                        else
                          Text(
                            'You can view the X report. Closing the day needs reports edit access.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: t.spacing.md),
            AppCard(
              title: 'Past day closes',
              child: SizedBox(
                height: 320,
                child: AppDataTable<DayCloseRow>(
                  columns: [
                    AppColumn<DayCloseRow>(
                      label: 'Business date',
                      cell: (r) => Text(r.businessDate),
                    ),
                    AppColumn<DayCloseRow>(
                      label: 'Kind',
                      width: 80,
                      cell: (r) => Text(r.kind),
                    ),
                    AppColumn<DayCloseRow>(
                      label: 'Expected',
                      numeric: true,
                      cell: (r) => Text(r.cashExpected == null ? '-' : '₹${r.cashExpected}'),
                    ),
                    AppColumn<DayCloseRow>(
                      label: 'Counted',
                      numeric: true,
                      cell: (r) => Text(r.cashCounted == null ? '-' : '₹${r.cashCounted}'),
                    ),
                    AppColumn<DayCloseRow>(
                      label: 'Variance',
                      cell: (r) => Text(
                        r.cashExpected == null || r.cashCounted == null
                            ? '-'
                            : varianceLabel(cashVarianceInPaise(
                                expected: r.cashExpected!,
                                counted: r.cashCounted!,
                              )),
                      ),
                    ),
                  ],
                  rows: closes.valueOrNull ?? const [],
                  loading: closes.isLoading && !closes.hasValue,
                  error: closes.hasError && !closes.hasValue ? ApiError.from(closes.error!).message : null,
                  onRetry: () => ref.invalidate(dayClosesProvider),
                  empty: EmptyState(
                    title: 'No day closes yet',
                    message: 'Closing the day saves a Z report here.',
                    icon: Icons.event_available_outlined,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VarianceText extends StatelessWidget {
  const _VarianceText({required this.expected, required this.counted});

  final String? expected;
  final String counted;

  @override
  Widget build(BuildContext context) {
    final value = double.tryParse(counted.trim());
    if (expected == null || value == null) {
      return Text('Enter the counted cash to see the variance.', style: Theme.of(context).textTheme.bodySmall);
    }
    final paise = cashVarianceInPaise(expected: expected!, counted: counted);
    final tone = paise == 0
        ? StatusTone.success
        : (paise > 0 ? StatusTone.info : StatusTone.danger);
    return Align(
      alignment: Alignment.centerLeft,
      child: StatusBadge(label: varianceLabel(paise), tone: tone),
    );
  }
}

class _XReportView extends StatelessWidget {
  const _XReportView({required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(summary.businessDate, style: text.bodySmall),
        SizedBox(height: t.spacing.sm),
        _Line(label: 'Gross', value: '₹${summary.gross}'),
        _Line(label: 'Discounts', value: '− ₹${summary.discounts}'),
        _Line(label: 'Service charge', value: '₹${summary.serviceCharge}'),
        for (final tax in summary.tax)
          _Line(label: '${tax.name} ${tax.rate}%', value: '₹${tax.amount}'),
        _Line(label: 'Round-off', value: '₹${summary.roundOff}'),
        _Line(label: 'Net', value: '₹${summary.net}', strong: true),
        _Line(label: 'Tips', value: '₹${summary.tips}'),
        SizedBox(height: t.spacing.sm),
        Text('Orders', style: text.labelLarge),
        _Line(
          label: 'Paid · void · open',
          value: '${summary.paid} · ${summary.voidCount} · ${summary.openCount}',
        ),
        SizedBox(height: t.spacing.sm),
        Text('By payment', style: text.labelLarge),
        if (summary.byPayment.isEmpty) Text('No payments yet', style: text.bodySmall),
        for (final p in summary.byPayment)
          _Line(label: '${p.label} (${p.count})', value: '₹${p.amount}'),
        SizedBox(height: t.spacing.sm),
        Text('By order type', style: text.labelLarge),
        for (final ty in summary.byType)
          _Line(label: '${ty.label} (${ty.count})', value: '₹${ty.amount}'),
        SizedBox(height: t.spacing.sm),
        _Line(
          label: 'Voids (${summary.voids.count})',
          value: '₹${summary.voids.amount}',
        ),
        _Line(
          label: 'Refunds (${summary.refunds.count})',
          value: '₹${summary.refunds.amount}',
        ),
        if (summary.discountsByStaff.isNotEmpty) ...[
          SizedBox(height: t.spacing.sm),
          Text('Discounts by staff', style: text.labelLarge),
          for (final s in summary.discountsByStaff)
            _Line(label: s.label, value: '₹${s.amount}'),
        ],
        SizedBox(height: t.spacing.sm),
        _Line(label: 'Cash expected', value: '₹${summary.cashExpected}', strong: true),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = strong
        ? Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.spacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
