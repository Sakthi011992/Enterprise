import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../data/inventory_models.dart';
import '../data/inventory_repository.dart';
import '../data/json_read.dart';
import '../data/offline_count_queue.dart';
import '../data/stock_format.dart';
import '../domain/count_rules.dart';
import 'inventory_messages.dart';
import 'widgets/qty_stepper.dart';

/// Stock count (MobileStock board): one card per item, bottles stepper and an
/// "open" field, Saved offline / Not counted / Check again status, outlier
/// warning, Save & exit, and Submit when online. Every change is stored on the
/// phone first (see [OfflineCountQueue]), so counting works without a network.
class StockCountScreen extends ConsumerStatefulWidget {
  const StockCountScreen({super.key, this.initialCountId});

  /// Opens this count directly, for example from the stock counts tab.
  final String? initialCountId;

  @override
  ConsumerState<StockCountScreen> createState() => _StockCountScreenState();
}

/// Editable state of one count line.
class _Draft {
  _Draft(this.line) : open = TextEditingController();

  final CountLine line;
  final TextEditingController open;
  int bottles = 0;
  bool counted = false;
  String? note;
  bool confirmed = false;

  num get value => parseStockInput(bottles, num.tryParse(open.text.trim()) ?? 0, line.packSize);

  void dispose() => open.dispose();
}

class _StockCountScreenState extends ConsumerState<StockCountScreen> {
  static const _flushDelay = Duration(milliseconds: 800);

  String? _locationId;
  CountView? _count;
  Map<String, _Draft> _drafts = {};
  Set<String> _pending = {};
  bool _loading = false;
  bool _busy = false;
  bool _offline = false;
  String? _error;
  Timer? _flushTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialCountId != null) _openById(widget.initialCountId!);
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    for (final d in _drafts.values) {
      d.dispose();
    }
    super.dispose();
  }

  // --- loading --------------------------------------------------------------

  Future<void> _openById(String id) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final view = await ref.read(inventoryRepositoryProvider).count(id);
      await _apply(view);
    } catch (e) {
      _fail(e);
    }
  }

  /// Picks the location; continues an open count there, or leaves "Start count".
  Future<void> _pickLocation(String locationId) async {
    setState(() {
      _locationId = locationId;
      _count = null;
      _error = null;
      _loading = true;
    });
    try {
      final open = await ref
          .read(inventoryRepositoryProvider)
          .counts(status: CountStatus.open, locationId: locationId);
      if (open.isNotEmpty) {
        final view = await ref.read(inventoryRepositoryProvider).count(open.first.id);
        await _apply(view);
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _start() async {
    final locationId = _locationId;
    if (locationId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final view = await ref.read(inventoryRepositoryProvider).startCount(locationId);
      await _apply(view);
    } on ApiError catch (e) {
      final existing = e.stringDetail('countId');
      if (e.code == 'COUNT_ALREADY_OPEN' && existing != null) {
        await _openById(existing);
      } else {
        _fail(e);
      }
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Loads a view and merges the phone's saved lines over the server values.
  Future<void> _apply(CountView view) async {
    final queue = await ref.read(offlineCountQueueProvider.future);
    final pendingLines = {for (final p in queue.linesFor(view.id)) p.stockItemId: p};
    for (final d in _drafts.values) {
      d.dispose();
    }
    final drafts = <String, _Draft>{};
    for (final line in view.lines) {
      final d = _Draft(line);
      final pending = pendingLines[line.stockItemId];
      final qtyText = pending != null ? pending.countedQty : line.countedQty;
      if (qtyText != null) {
        final v = num.tryParse(qtyText) ?? 0;
        if (line.packSize > 1) {
          final packs = (v / line.packSize).floor();
          d.bottles = packs;
          d.open.text = _text(v - packs * line.packSize);
        } else {
          d.open.text = _text(v);
        }
        d.counted = true;
      }
      d.note = pending?.note ?? line.note;
      d.confirmed = pending?.confirmedOutlier ?? line.confirmedOutlier;
      drafts[line.stockItemId] = d;
    }
    if (!mounted) return;
    setState(() {
      _count = view;
      _drafts = drafts;
      _pending = pendingLines.keys.toSet();
      _loading = false;
      _busy = false;
    });
    _flushSoon(view.id);
  }

  void _fail(Object e) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _busy = false;
      _error = inventoryErrorText(e);
      if (ApiError.from(e).isNetwork) _offline = true;
    });
  }

  static String _text(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(3);

  // --- saving ----------------------------------------------------------------

  /// Stores one line on the phone, then sends soon. Nothing waits on the network.
  Future<void> _persist(_Draft d) async {
    final count = _count;
    if (count == null) return;
    final queue = await ref.read(offlineCountQueueProvider.future);
    await queue.save(
      countId: count.id,
      stockItemId: d.line.stockItemId,
      countedQty: d.counted ? wireQty(d.value) : null,
      note: d.note,
      confirmedOutlier: d.confirmed,
    );
    if (!mounted) return;
    setState(() {
      _pending = {for (final p in queue.linesFor(count.id)) p.stockItemId};
    });
    _flushSoon(count.id);
  }

  void _flushSoon(String countId) {
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushDelay, () => _flushNow(countId));
  }

  /// Sends saved lines for this count. Updates the offline state and the
  /// pending set from what is still on the phone.
  Future<CountFlushResult> _flushNow(String countId) async {
    final queue = await ref.read(offlineCountQueueProvider.future);
    final result = await queue.flush(countId: countId);
    if (mounted) {
      setState(() {
        _offline = result.offline;
        _pending = {for (final p in queue.linesFor(countId)) p.stockItemId};
      });
    }
    return result;
  }

  void _edited(_Draft d, {bool valueChanged = true}) {
    setState(() {
      d.counted = true;
      if (valueChanged) d.confirmed = false;
    });
    _persist(d);
  }

  Future<void> _addNote(_Draft d) async {
    final controller = TextEditingController(text: d.note ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Note for ${d.line.name}'),
        content: AppTextField(label: 'Note', controller: controller, autofocus: true),
        actions: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          AppButton(
            label: 'Save note',
            variant: AppButtonVariant.primary,
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || !mounted) return;
    d.note = note.isEmpty ? null : note;
    setState(() {});
    _persist(d);
  }

  Future<void> _saveAndExit() async {
    final count = _count;
    if (count != null) await _flushNow(count.id);
    if (mounted) context.go('/inventory');
  }

  /// Sends the saved lines, then submits. Submit needs the server.
  Future<void> _submit() async {
    final count = _count;
    if (count == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final flushed = await _flushNow(count.id);
      if (flushed.offline) {
        setState(() => _error = "You're offline. Submit when you reconnect.");
        return;
      }
      if (_pending.isNotEmpty) {
        setState(() => _error =
            'Some counts are still saved on this phone. Keep counting until they sync.');
        return;
      }
      final view = await ref.read(inventoryRepositoryProvider).submitCount(count.id);
      if (!mounted) return;
      setState(() {
        _count = view;
        _offline = false;
      });
      showAppToast(context, 'Count submitted. A manager can post it.');
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _post() async {
    final count = _count;
    if (count == null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Post this count?',
      message: 'Stock will be adjusted to match what was counted. The difference is '
          'recorded in the variance report.',
      confirmLabel: 'Post count',
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final view = await ref.read(inventoryRepositoryProvider).postCount(count.id);
      if (!mounted) return;
      setState(() => _count = view);
      showAppToast(context, 'Count posted');
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.stockCount, AccessLevel.edit);
    final canPost = can(ref, Perm.stockCount, AccessLevel.approve);
    final locations = ref.watch(inventoryLocationsProvider).valueOrNull ?? const <LocationView>[];
    final rows = _locationId == null
        ? const <StockItemRow>[]
        : ref
                .watch(stockItemsProvider((locationId: _locationId, status: null, liquor: false)))
                .valueOrNull ??
            const <StockItemRow>[];
    final rowById = {for (final r in rows) r.id: r};
    final pendingCount = ref.watch(offlineCountPendingProvider).valueOrNull ?? 0;
    final count = _count;
    final open = count?.status == CountStatus.open;
    final lines = count?.lines ?? const <CountLine>[];
    final counted = [for (final d in _drafts.values) if (d.counted) d].length;

    return DensityScope(
      density: AppDensity.pos,
      child: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(t.spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Stock count',
                breadcrumb: 'Menu & stock',
                actions: [
                  if (count != null && open && canEdit)
                    AppButton(
                      label: 'Save & exit',
                      icon: Icons.save_outlined,
                      onPressed: _busy ? null : _saveAndExit,
                    ),
                  if (count != null && open && canEdit)
                    AppButton(
                      label: 'Submit count',
                      variant: AppButtonVariant.primary,
                      icon: Icons.cloud_upload_outlined,
                      loading: _busy,
                      onPressed: _offline || _busy ? null : _submit,
                    ),
                  if (count != null && count.status == CountStatus.submitted && canPost)
                    AppButton(
                      label: 'Post count',
                      variant: AppButtonVariant.primary,
                      loading: _busy,
                      onPressed: _busy ? null : _post,
                    ),
                ],
              ),
              SizedBox(height: t.spacing.sm),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: t.spacing.md,
                runSpacing: t.spacing.sm,
                children: [
                  SizedBox(
                    width: 280,
                    child: AppSelect<String>(
                      label: 'Location',
                      value: _locationId,
                      items: [for (final l in locations) AppSelectItem(l.id, l.name)],
                      onChanged: _busy
                          ? (_) {}
                          : (v) {
                              if (v != null) _pickLocation(v);
                            },
                    ),
                  ),
                  if (count != null)
                    Text(
                      '$counted of ${lines.length} items counted',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  if (count != null && count.status != CountStatus.open)
                    StatusBadge(label: _statusText(count.status), tone: StatusTone.info),
                ],
              ),
              SizedBox(height: t.spacing.sm),
              if (_offline)
                AppBanner(
                  tone: StatusTone.warning,
                  message: pendingCount > 0
                      ? "You're offline. $pendingCount counts are saved on this phone and will sync when you reconnect. Keep counting."
                      : "You're offline. Counts you save will sync when you reconnect. Keep counting.",
                ),
              if (_error != null) ...[
                SizedBox(height: t.spacing.sm),
                InlineAlert(message: _error!),
              ],
              SizedBox(height: t.spacing.sm),
              Expanded(child: _body(context, count, lines, rowById, canEdit && open, locations)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    CountView? count,
    List<CountLine> lines,
    Map<String, StockItemRow> rowById,
    bool editable,
    List<LocationView> locations,
  ) {
    if (_loading) return DelayedSkeleton(child: SkeletonList());
    if (count == null) {
      if (_locationId != null && !_busy) {
        return EmptyState(
          title: 'No count open here',
          message: 'Start a count to check every item at this location against the shelf.',
          icon: Icons.fact_check_outlined,
          actionLabel: 'Start count',
          onAction: _start,
        );
      }
      return const EmptyState(
        title: 'Pick a location',
        message: 'Choose the location you are counting. Your count is saved on this phone as you type.',
        icon: Icons.place_outlined,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 1024;
        final t = context.tokens;
        final cardWidth = twoColumns ? (constraints.maxWidth - t.spacing.md) / 2 : constraints.maxWidth;
        return SingleChildScrollView(
          child: Wrap(
            spacing: t.spacing.md,
            runSpacing: t.spacing.md,
            children: [
              for (final line in lines)
                if (_drafts[line.stockItemId] != null)
                  SizedBox(
                    width: cardWidth,
                    child: _lineCard(
                      context,
                      _drafts[line.stockItemId]!,
                      rowById[line.stockItemId],
                      editable,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _lineCard(BuildContext context, _Draft d, StockItemRow? row, bool editable) {
    final t = context.tokens;
    final line = d.line;
    final expectedDisplay = line.expectedDisplay ?? row?.onHandDisplay;
    final expectedQty = num.tryParse(line.expectedQty ?? '') ?? row?.onHandQty;
    final outlier = d.counted && expectedQty != null && isCountOutlier(expectedQty, d.value);
    final percent = outlier ? countDifferencePercent(expectedQty!, d.value) : null;
    final showWarning = outlier && !d.confirmed;

    final StatusBadge badge;
    if (_pending.contains(line.stockItemId)) {
      badge = const StatusBadge(label: 'Saved offline', tone: StatusTone.info);
    } else if (!d.counted) {
      badge = const StatusBadge(label: 'Not counted', tone: StatusTone.neutral);
    } else if (showWarning) {
      badge = const StatusBadge(label: 'Check again', tone: StatusTone.warning);
    } else {
      badge = const StatusBadge(label: 'Counted', tone: StatusTone.success);
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              badge,
            ],
          ),
          if (expectedDisplay != null && expectedDisplay.isNotEmpty) ...[
            SizedBox(height: t.spacing.xs),
            Text('Expected about $expectedDisplay', style: Theme.of(context).textTheme.bodySmall),
          ],
          SizedBox(height: t.spacing.sm),
          if (line.packSize > 1)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: t.spacing.md,
              runSpacing: t.spacing.sm,
              children: [
                QtyStepper(
                  value: d.bottles,
                  unitLabel: line.packName,
                  enabled: editable,
                  onChanged: (v) {
                    d.bottles = v;
                    _edited(d);
                  },
                ),
                SizedBox(
                  width: 160,
                  child: AppTextField(
                    label: '${line.baseUnit.toLowerCase()} open',
                    controller: d.open,
                    keyboardType: TextInputType.number,
                    onChanged: editable ? (_) => _edited(d) : null,
                  ),
                ),
              ],
            )
          else
            AppTextField(
              label: 'Quantity (${line.baseUnit.toLowerCase()})',
              controller: d.open,
              keyboardType: TextInputType.number,
              onChanged: editable ? (_) => _edited(d) : null,
            ),
          if (d.counted) ...[
            SizedBox(height: t.spacing.xs),
            Text(
              'Counted ${formatStockQty(d.value, line.baseUnit, line.packSize, line.packName)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (showWarning) ...[
            SizedBox(height: t.spacing.sm),
            InlineAlert(
              tone: StatusTone.warning,
              message: countOutlierMessage(
                expectedDisplay: expectedDisplay ?? 'the usual amount',
                percent: percent ?? 0,
              ),
            ),
            SizedBox(height: t.spacing.xs),
            Wrap(
              spacing: t.spacing.sm,
              children: [
                if (editable)
                  AppButton(
                    label: d.note == null ? 'Add note' : 'Edit note',
                    size: AppControlSize.sm,
                    onPressed: () => _addNote(d),
                  ),
                if (editable)
                  AppButton(
                    label: 'Count is correct',
                    size: AppControlSize.sm,
                    variant: AppButtonVariant.primary,
                    onPressed: () {
                      d.confirmed = true;
                      _edited(d, valueChanged: false);
                    },
                  ),
              ],
            ),
          ],
          if (d.note != null && d.note!.isNotEmpty) ...[
            SizedBox(height: t.spacing.xs),
            Text('Note: ${d.note}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  static String _statusText(String status) => switch (status) {
        CountStatus.submitted => 'Submitted',
        CountStatus.posted => 'Posted',
        CountStatus.cancelled => 'Cancelled',
        _ => 'Open',
      };
}
