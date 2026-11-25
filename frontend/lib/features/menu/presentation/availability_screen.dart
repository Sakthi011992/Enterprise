import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/providers.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/ui/ui.dart';
import '../../inventory/presentation/log_wastage_sheet.dart';
import '../../pos/presentation/dialogs/dialog_frame.dart';
import '../../pos/presentation/pos_order_controller.dart';
import '../data/menu_repository.dart';

/// One product on the availability board.
class AvailabilityItem {
  const AvailabilityItem({
    required this.id,
    required this.name,
    this.categoryName,
    this.station,
    this.is86 = false,
    this.auto86 = false,
  });

  final String id;
  final String name;
  final String? categoryName;

  /// `Category.station` (KITCHEN, BAR, GRILL, TANDOOR), or null.
  final String? station;
  final bool is86;

  /// True when stock ran out and the server 86'd the item (PLAN 1.4).
  final bool auto86;
}

/// Loads products and categories, and joins the station onto each product.
final availabilityProvider = FutureProvider.autoDispose<List<AvailabilityItem>>((ref) async {
  final dio = ref.watch(dioProvider);
  // The products list is paged (max 100 per page).
  final productRows = <Map<String, dynamic>>[];
  for (var page = 1; page <= 20; page++) {
    final res = await dio.get<dynamic>('/products', queryParameters: {'limit': 100, 'page': page});
    productRows.addAll(_rows(res.data));
    final meta = res.data is Map ? (res.data as Map)['meta'] : null;
    final totalPages = meta is Map ? (meta['totalPages'] as num?)?.toInt() ?? 1 : 1;
    if (page >= totalPages) break;
  }
  final categoriesRes = await dio.get<dynamic>('/categories');
  final stationByCategory = <String, String?>{};
  final categoryName = <String, String>{};
  for (final c in _rows(categoriesRes.data)) {
    final id = c['id'] as String?;
    if (id == null) continue;
    stationByCategory[id] = c['station'] as String?;
    categoryName[id] = (c['name'] as String?) ?? '';
  }
  return [
    for (final p in productRows)
      if (p['isActive'] != false)
        AvailabilityItem(
          id: p['id'] as String,
          name: (p['name'] as String?) ?? '',
          categoryName: categoryName[p['categoryId']],
          station: stationByCategory[p['categoryId']],
          is86: p['is86'] as bool? ?? false,
          auto86: p['auto86'] as bool? ?? false,
        ),
  ];
});

List<Map<String, dynamic>> _rows(dynamic body) {
  final raw = body is Map ? body['data'] : body;
  return [
    for (final row in (raw as List?) ?? const [])
      if (row is Map) Map<String, dynamic>.from(row),
  ];
}

/// `/menu/availability`: tonight's items with Available and Sold out, filtered
/// by station, plus the kitchen wastage entry. Design: TabletOps chef board.
class AvailabilityScreen extends ConsumerStatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  ConsumerState<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends ConsumerState<AvailabilityScreen> {
  static const _allStations = '__all__';

  String _station = _allStations;
  final Set<String> _busy = {};
  String? _error;

  void _refresh() => ref.invalidate(availabilityProvider);

  Future<void> _set86(AvailabilityItem item, bool is86) async {
    setState(() {
      _busy.add(item.id);
      _error = null;
    });
    try {
      await ref.read(menuRepositoryProvider).set86(item.id, is86);
      // POS and the QR menu read the same flag, so refresh the POS menu too.
      ref.invalidate(posMenuProvider);
    } catch (e) {
      if (mounted) setState(() => _error = ApiError.from(e).message);
    } finally {
      if (mounted) {
        setState(() => _busy.remove(item.id));
        _refresh();
      }
    }
  }

  Future<void> _logWastage() async {
    final logged = await showLogWastageSheet(context);
    if (logged && mounted) showAppToast(context, 'Kitchen wastage logged.');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    ref.listen(realtimeEventProvider(RealtimeEvents.menuItem86), (_, __) => _refresh());

    final canEdit = can(ref, Perm.menuMark86, AccessLevel.edit);
    final items = ref.watch(availabilityProvider);

    return DensityScope(
      density: AppDensity.pos,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: "Tonight's availability",
                actions: [
                  AppButton(
                    label: 'Log kitchen wastage',
                    variant: AppButtonVariant.secondary,
                    onPressed: _logWastage,
                  ),
                ],
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: t.spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const InlineAlert(
                      message:
                          'Turning an item off hides it on POS, QR menu, kiosk and delivery apps at once.',
                      tone: StatusTone.info,
                    ),
                    if (_error != null) ...[
                      SizedBox(height: t.spacing.sm),
                      InlineAlert(message: _error!),
                    ],
                    SizedBox(height: t.spacing.sm),
                    Wrap(
                      spacing: t.spacing.sm,
                      runSpacing: t.spacing.sm,
                      children: _stationChips(items.valueOrNull ?? const []),
                    ),
                    SizedBox(height: t.spacing.sm),
                  ],
                ),
              ),
              Expanded(
                child: items.when(
                  loading: () => const DelayedSkeleton(child: SkeletonList()),
                  error: (e, _) => ErrorState(message: ApiError.from(e).message, onRetry: _refresh),
                  data: (all) {
                    final visible = [
                      for (final item in all)
                        if (_station == _allStations || item.station == _station) item,
                    ];
                    if (visible.isEmpty) {
                      return const EmptyState(
                        title: 'No items here',
                        message: 'Products in this station show here.',
                      );
                    }
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 900;
                        final cardWidth = wide
                            ? (constraints.maxWidth - t.spacing.md * 3) / 2
                            : constraints.maxWidth - t.spacing.md * 2;
                        return SingleChildScrollView(
                          padding: EdgeInsets.all(t.spacing.md),
                          child: Wrap(
                            spacing: t.spacing.md,
                            runSpacing: t.spacing.md,
                            children: [
                              for (final item in visible)
                                SizedBox(
                                  width: cardWidth,
                                  child: _ItemRow(
                                    item: item,
                                    busy: _busy.contains(item.id),
                                    canEdit: canEdit,
                                    onChanged: (v) => _set86(item, !v),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stationChips(List<AvailabilityItem> items) {
    final stations = <String>{
      for (final i in items)
        if (i.station != null && i.station!.isNotEmpty) i.station!,
    }.toList()
      ..sort();
    return [
      PosChoiceChip(
        label: 'All',
        selected: _station == _allStations,
        minHeight: 44,
        onTap: () => setState(() => _station = _allStations),
      ),
      for (final s in stations)
        PosChoiceChip(
          label: _stationLabel(s),
          selected: _station == s,
          minHeight: 44,
          onTap: () => setState(() => _station = s),
        ),
    ];
  }

  static String _stationLabel(String station) => switch (station) {
        'KITCHEN' => 'Kitchen',
        'BAR' => 'Bar',
        'GRILL' => 'Grill',
        'TANDOOR' => 'Tandoor',
        _ => station[0] + station.substring(1).toLowerCase(),
      };
}

/// One product: name, station, the Available / Sold out switch and an auto badge.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.busy,
    required this.canEdit,
    required this.onChanged,
  });

  final AvailabilityItem item;
  final bool busy;
  final bool canEdit;

  /// Receives the new "available" value.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final available = !item.is86;
    final subtitle = [
      if (item.categoryName != null && item.categoryName!.isNotEmpty) item.categoryName!,
      if (item.station != null) _AvailabilityScreenState._stationLabel(item.station!),
    ].join(' · ');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.auto86) ...[
                const StatusBadge(label: 'Auto', tone: StatusTone.warning),
                SizedBox(width: t.spacing.xs),
              ],
              StatusBadge(
                label: available ? 'Available' : 'Sold out',
                tone: available ? StatusTone.success : StatusTone.danger,
              ),
            ],
          ),
          if (subtitle.isNotEmpty)
            Text(subtitle, style: TextStyle(color: t.color.content.secondary)),
          SizedBox(height: t.spacing.sm),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(value: true, label: Text('Available')),
              ButtonSegment<bool>(value: false, label: Text('Sold out')),
            ],
            selected: {available},
            onSelectionChanged: (!canEdit || busy)
                ? null
                : (selection) => onChanged(selection.first),
          ),
        ],
      ),
    );
  }
}
