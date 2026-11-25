import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/ui/ui.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/presentation/inventory_messages.dart';
import '../../inventory/presentation/widgets/qty_stepper.dart';
import '../../pos/presentation/pos_format.dart';
import '../data/procurement_models.dart';
import '../data/procurement_repository.dart';
import '../domain/grn_math.dart';

/// Storekeeper's "Request a reorder" (MobileStaff board). Below-par items, a
/// quantity in purchase units per line, and one draft PO per vendor on send.
class ReorderScreen extends ConsumerStatefulWidget {
  const ReorderScreen({super.key});

  @override
  ConsumerState<ReorderScreen> createState() => _ReorderScreenState();
}

class _ReorderScreenState extends ConsumerState<ReorderScreen> {
  String? _locationId;
  final Map<String, int> _qty = {};

  /// Rows as last built, so Send works on what is on screen.
  List<ReorderSuggestion> _current = const [];
  String? _error;
  bool _sending = false;
  Set<String> _missingVendor = {};

  static String _key(ReorderSuggestion s) => '${s.locationId}::${s.stockItemId}';

  /// Lines grouped by location, because one request takes one location.
  Map<String, List<ReorderSuggestion>> _byLocation(Iterable<ReorderSuggestion> rows) {
    final out = <String, List<ReorderSuggestion>>{};
    for (final r in rows) {
      out.putIfAbsent(r.locationId, () => []).add(r);
    }
    return out;
  }

  Future<void> _send() async {
    final chosen = [
      for (final r in _current)
        if ((_qty[_key(r)] ?? 0) > 0) r,
    ];
    final withoutVendor = chosen.where((r) => r.vendor == null).toList();
    if (withoutVendor.isNotEmpty) {
      setState(() {
        _missingVendor = {for (final r in withoutVendor) r.stockItemId};
        _error = 'Some items have no preferred vendor. Set a vendor on the item first.';
      });
      return;
    }
    if (chosen.isEmpty) {
      setState(() => _error = 'Pick a quantity for at least one item.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
      _missingVendor = {};
    });
    final repo = ref.read(procurementRepositoryProvider);
    var created = 0;
    try {
      for (final entry in _byLocation(chosen).entries) {
        final pos = await repo.reorderRequest(
          locationId: entry.key,
          lines: [
            for (final r in entry.value) (stockItemId: r.stockItemId, qty: _qty[_key(r)] ?? 0),
          ],
        );
        created += pos.length;
      }
      ref.invalidate(reorderSuggestionsProvider);
      ref.invalidate(purchaseOrdersProvider);
      if (mounted) {
        showAppToast(context, 'Sent for approval: $created draft POs');
        context.go('/procurement');
      }
    } catch (e) {
      final api = ApiError.from(e);
      final ids = (api.details?['stockItemIds'] as List?)?.map((x) => x.toString()).toSet() ?? {};
      if (mounted) {
        setState(() {
          _error = inventoryErrorText(e);
          _missingVendor = ids;
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locations = ref.watch(inventoryLocationsProvider).valueOrNull ?? const <LocationView>[];
    final async = ref.watch(reorderSuggestionsProvider(_locationId));
    final rows = async.valueOrNull ?? const <ReorderSuggestion>[];

    // Keep the quantities the user changed, and default new rows to the suggestion.
    _current = rows;
    for (final r in rows) {
      _qty.putIfAbsent(_key(r), () => r.suggestedQty);
    }

    var total = 0.0;
    final vendors = <String>{};
    for (final r in rows) {
      final q = _qty[_key(r)] ?? 0;
      if (q <= 0) continue;
      total += q * r.rate;
      vendors.add(r.vendor?.id ?? '-');
    }

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Request a reorder',
              breadcrumb: 'Procurement',
              actions: [
                AppButton(
                  label: 'Back to procurement',
                  icon: Icons.arrow_back,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => context.go('/procurement'),
                ),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: t.spacing.md,
              runSpacing: t.spacing.sm,
              children: [
                SizedBox(
                  width: 240,
                  child: AppSelect<String>(
                    label: 'Location',
                    value: _locationId ?? '',
                    items: [
                      const AppSelectItem('', 'All locations'),
                      for (final l in locations) AppSelectItem(l.id, l.name),
                    ],
                    onChanged: (v) => setState(() => _locationId = (v == null || v.isEmpty) ? null : v),
                  ),
                ),
                Text(
                  'Below par · ${rows.length} items',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            SizedBox(height: t.spacing.xs),
            Text(
              'Suggested amounts bring each item back to par',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: t.spacing.sm),
            if (_error != null) ...[
              InlineAlert(message: _error!),
              SizedBox(height: t.spacing.sm),
            ],
            Expanded(
              child: async.when(
                loading: () => DelayedSkeleton(child: SkeletonList()),
                error: (e, _) => ErrorState(
                  message: ApiError.from(e).message,
                  onRetry: () => ref.invalidate(reorderSuggestionsProvider(_locationId)),
                ),
                data: (_) => rows.isEmpty
                    ? const EmptyState(
                        title: 'Nothing below par',
                        message: 'Every item is at or above its par level.',
                        icon: Icons.check_circle_outline,
                      )
                    : ListView(
                        children: [
                          for (final r in rows)
                            Padding(
                              padding: EdgeInsets.only(bottom: t.spacing.sm),
                              child: _row(context, r),
                            ),
                        ],
                      ),
              ),
            ),
            SizedBox(height: t.spacing.sm),
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      vendors.isEmpty
                          ? 'Nothing selected yet.'
                          : 'Creates ${vendors.length} draft POs (one per vendor), '
                              '${formatRupees(total)} total. A manager approves before they\'re sent.',
                    ),
                  ),
                  SizedBox(width: t.spacing.md),
                  AppButton(
                    label: 'Send for approval',
                    variant: AppButtonVariant.primary,
                    loading: _sending,
                    onPressed: _sending || vendors.isEmpty ? null : _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, ReorderSuggestion r) {
    final t = context.tokens;
    final qty = _qty[_key(r)] ?? 0;
    final missing = _missingVendor.contains(r.stockItemId) || r.vendor == null;
    final unit = unitWord(r.purchaseUnitName);
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.name, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${r.onHandDisplay} / ${r.parDisplay} · ${r.locationName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  r.vendor == null ? 'No preferred vendor' : r.vendor!.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: missing ? t.color.content.danger : null,
                      ),
                ),
              ],
            ),
          ),
          QtyStepper(
            value: qty,
            unitLabel: unit,
            enabled: !_sending,
            onChanged: (v) => setState(() => _qty[_key(r)] = v),
          ),
          SizedBox(width: t.spacing.sm),
          SizedBox(
            width: 110,
            child: Text(
              formatRupees(qty * r.rate),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
