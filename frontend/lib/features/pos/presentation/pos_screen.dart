import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/ui/ui.dart';
import '../../tabs/presentation/open_tab_dialog.dart';
import '../data/offline_queue.dart';
import '../data/pos_models.dart';
import '../data/pos_repository.dart';
import '../data/product_usage.dart';
import 'dialogs/dialog_frame.dart';
import 'dialogs/discount_dialog.dart';
import 'dialogs/modifier_sheet.dart';
import 'dialogs/transfer_dialog.dart';
import 'dialogs/void_dialog.dart';
import 'pos_format.dart';
import 'pos_order_controller.dart';
import 'pos_product_grid.dart';
import 'pos_ticket_panel.dart';

/// Route prefix for an order that is still in the offline queue.
const offlineOrderPrefix = 'offline-';

/// Category key for the combos view. Favourites use a null key.
const _combosKey = '__combos__';

/// Wide enough for the side ticket. At or below this width the ticket moves into
/// a bottom sheet (PLAN 1.7, tablet ≤ 1024 px).
const wideLayoutMinWidth = 1025.0;

/// `/pos` (quick start and tables) and `/pos/:orderId` (order workspace).
class PosScreen extends ConsumerWidget {
  const PosScreen({super.key, this.orderId, this.tableId});

  /// An order to open, or null for the quick start.
  final String? orderId;

  /// Quick start only: pre-selects Dine-in and opens this table's guest prompt
  /// once the tables load (`/pos?tableId=...`, wired by the router).
  final String? tableId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An 86 change on any till or the kitchen shows here without a reload.
    ref.listen(realtimeEventProvider(RealtimeEvents.menuItem86), (_, __) {
      ref.invalidate(posMenuProvider);
    });
    final id = orderId;
    final Widget body;
    if (id == null) {
      body = _QuickStart(tableId: tableId);
    } else if (id.startsWith(offlineOrderPrefix)) {
      body = _OfflinePending(offlineId: id.substring(offlineOrderPrefix.length));
    } else {
      body = _OrderWorkspace(orderId: id);
    }
    return DensityScope(
      density: AppDensity.pos,
      child: Scaffold(body: SafeArea(child: body)),
    );
  }
}

/// Creates an order. Offline, the request goes to the queue and the user
/// lands on the pending screen. The `offlineId` is set before the first
/// attempt, so a retry never makes a second order.
Future<void> startPosOrder(BuildContext context, WidgetRef ref, CreateOrder body) async {
  final request = body.offlineId == null ? body.withOfflineId(generateOfflineId()) : body;
  try {
    final order = await ref.read(posRepositoryProvider).createOrder(request);
    if (context.mounted) context.go('/pos/${order.id}');
  } catch (e) {
    final err = ApiError.from(e);
    if (!context.mounted) return;
    if (err.isNetwork) {
      final queue = await ref.read(offlineOrderQueueProvider.future);
      final id = await queue.enqueue(request);
      if (context.mounted) context.go('/pos/$offlineOrderPrefix$id');
      return;
    }
    final message = err.code == 'TABLE_OCCUPIED'
        ? 'That table was just taken. Pick another.'
        : err.message;
    showAppToast(context, message);
  }
}

// --- quick start -------------------------------------------------------------

class _QuickStart extends ConsumerStatefulWidget {
  const _QuickStart({this.tableId});

  final String? tableId;

  @override
  ConsumerState<_QuickStart> createState() => _QuickStartState();
}

class _QuickStartState extends ConsumerState<_QuickStart> {
  String _type = OrderTypes.dineIn;
  bool _busy = false;

  /// Table from the route, until its guest prompt has been opened once.
  String? _pendingTableId;

  @override
  void initState() {
    super.initState();
    _pendingTableId = widget.tableId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openPendingTable(ref.read(posTablesProvider).valueOrNull);
    });
  }

  /// Opens the guest prompt for the pending table, once. Does nothing when the
  /// table is not in the list yet or is not free.
  void _openPendingTable(List<TableView>? tables) {
    final wanted = _pendingTableId;
    if (wanted == null || tables == null) return;
    TableView? match;
    for (final table in tables) {
      if (table.id == wanted) match = table;
    }
    _pendingTableId = null;
    if (match == null) return;
    setState(() => _type = OrderTypes.dineIn);
    _onTable(match);
  }

  Future<void> _startNonTable() async {
    setState(() => _busy = true);
    await startPosOrder(context, ref, CreateOrder(type: _type));
    if (mounted) setState(() => _busy = false);
  }

  /// Opens a bar tab. The tab's BAR_COUNTER order is the one we go to.
  Future<void> _openTab() async {
    final tab = await showOpenTabDialog(context);
    if (tab == null || !mounted) return;
    context.go('/pos/${tab.orderId}');
  }

  Future<void> _onTable(TableView table) async {
    final order = table.order;
    if (order != null) {
      context.go('/pos/${order.id}');
      return;
    }
    if (!table.isFree) {
      showAppToast(context, '${table.name} is ${tableStatusLabel(table.status).toLowerCase()}.');
      return;
    }
    final covers = await _askCovers(context, table);
    if (covers == null || !mounted) return;
    setState(() => _busy = true);
    await startPosOrder(
      context,
      ref,
      CreateOrder(type: OrderTypes.dineIn, tableId: table.id, covers: covers),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canStart = can(ref, Perm.salesOrdersTake, AccessLevel.edit);
    if (_pendingTableId != null) {
      ref.listen<AsyncValue<List<TableView>>>(posTablesProvider, (_, next) {
        _openPendingTable(next.valueOrNull);
      });
    }
    return Padding(
      padding: EdgeInsets.all(t.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Start an order', style: Theme.of(context).textTheme.headlineSmall),
              ),
              AppIconButton(
                icon: Icons.refresh,
                tooltip: 'Refresh tables',
                onPressed: () => ref.invalidate(posTablesProvider),
              ),
            ],
          ),
          SizedBox(height: t.spacing.sm),
          const _SyncBanner(offline: false),
          Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.sm,
            children: [
              for (final type in OrderTypes.all)
                PosChoiceChip(
                  label: OrderTypes.label(type),
                  selected: _type == type,
                  minHeight: 52,
                  onTap: _busy ? null : () => setState(() => _type = type),
                ),
            ],
          ),
          SizedBox(height: t.spacing.md),
          Expanded(
            child: _type == OrderTypes.dineIn
                ? _TablesGrid(
                    enabled: canStart && !_busy,
                    onTable: _onTable,
                  )
                : Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: t.spacing.sm,
                      runSpacing: t.spacing.sm,
                      children: [
                        AppButton(
                          label: 'Start ${OrderTypes.label(_type).toLowerCase()} order',
                          variant: AppButtonVariant.primary,
                          loading: _busy,
                          onPressed: (canStart && !_busy) ? _startNonTable : null,
                        ),
                        if (_type == OrderTypes.barCounter &&
                            can(ref, Perm.salesTabOpen, AccessLevel.limited))
                          AppButton(
                            label: 'Open tab',
                            icon: Icons.local_bar_outlined,
                            variant: AppButtonVariant.secondary,
                            onPressed: (canStart && !_busy) ? _openTab : null,
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TablesGrid extends ConsumerWidget {
  const _TablesGrid({required this.enabled, required this.onTable});

  final bool enabled;
  final ValueChanged<TableView> onTable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final tables = ref.watch(posTablesProvider);
    return tables.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        message: ApiError.from(e).message,
        onRetry: () => ref.invalidate(posTablesProvider),
      ),
      data: (list) {
        final visible = [for (final table in list) if (table.mergedIntoId == null) table];
        if (visible.isEmpty) {
          return const EmptyState(
            title: 'No tables yet',
            message: 'Set up areas and tables in Floor setup, or start a takeaway order.',
            icon: Icons.table_restaurant_outlined,
          );
        }
        return SingleChildScrollView(
          child: Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.sm,
            children: [
              for (final table in visible)
                _TableTile(
                  table: table,
                  onTap: enabled ? () => onTable(table) : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({required this.table, this.onTap});

  final TableView table;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final order = table.order;
    final tone = switch (table.status) {
      'FREE' => StatusTone.success,
      'RESERVED' => StatusTone.info,
      'OCCUPIED' => StatusTone.warning,
      'BILL_PRINTED' => StatusTone.warning,
      _ => StatusTone.neutral,
    };
    return Semantics(
      button: true,
      label: '${table.name}, ${table.seats} seats, ${tableStatusLabel(table.status)}',
      child: Material(
        color: t.color.background.raised,
        borderRadius: BorderRadius.circular(t.radius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radius.lg),
          onTap: onTap,
          child: Container(
            width: 150,
            constraints: const BoxConstraints(minHeight: 110),
            padding: EdgeInsets.all(t.spacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius.lg),
              border: Border.all(color: t.color.border.default, width: t.borderWidth.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  table.name,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: t.color.content.primary,
                  ),
                ),
                Text(
                  '${table.seats} seats',
                  style: TextStyle(color: t.color.content.secondary, fontSize: 13),
                ),
                const Spacer(),
                StatusBadge(label: tableStatusLabel(table.status), tone: tone),
                if (order != null) ...[
                  SizedBox(height: t.spacing.xs),
                  Text(
                    '#${order.orderNumber} · ${formatWire(order.grandTotal)}',
                    style: TextStyle(color: t.color.content.secondary, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<int?> _askCovers(BuildContext context, TableView table) {
  return showDialog<int>(
    context: context,
    builder: (dialogContext) {
      final seats = table.seats < 1 ? 1 : table.seats;
      return PosDialogFrame(
        title: 'How many guests at ${table.name}?',
        subtitle: 'The table seats $seats.',
        width: 420,
        actions: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var n = 1; n <= seats; n++)
              PosChoiceChip(
                label: '$n',
                selected: false,
                minHeight: 52,
                onTap: () => Navigator.of(dialogContext).pop(n),
              ),
          ],
        ),
      );
    },
  );
}

// --- offline sync --------------------------------------------------------------

/// Banner for queued orders: "Offline — 2 orders will sync".
class _SyncBanner extends ConsumerWidget {
  const _SyncBanner({required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(offlinePendingCountProvider).valueOrNull ?? 0;
    if (count == 0 && !offline) return const SizedBox.shrink();
    final noun = count == 1 ? 'order' : 'orders';
    final message = offline
        ? 'Offline — $count $noun will sync'
        : '$count $noun waiting to sync';
    return Padding(
      padding: EdgeInsets.only(bottom: context.tokens.spacing.sm),
      child: AppBanner(message: message, tone: StatusTone.warning),
    );
  }
}

/// Shown at `/pos/offline-<id>` until the queued order reaches the server.
class _OfflinePending extends ConsumerStatefulWidget {
  const _OfflinePending({required this.offlineId});

  final String offlineId;

  @override
  ConsumerState<_OfflinePending> createState() => _OfflinePendingState();
}

class _OfflinePendingState extends ConsumerState<_OfflinePending> {
  OfflineOrderQueue? _queue;
  StreamSubscription<(String, OrderView)>? _sub;
  OfflineQueueEntry? _entry;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final queue = await ref.read(offlineOrderQueueProvider.future);
    if (!mounted) return;
    _queue = queue;
    _sub = queue.synced.listen((event) {
      if (event.$1 == widget.offlineId && mounted) {
        context.go('/pos/${event.$2.id}');
      }
    });
    _refresh();
  }

  void _refresh() {
    final queue = _queue;
    if (queue == null) return;
    OfflineQueueEntry? found;
    for (final e in queue.entries) {
      if (e.offlineId == widget.offlineId) found = e;
    }
    setState(() => _entry = found);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    final queue = _queue;
    if (queue == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await queue.flush();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result.stillPending > 0
          ? 'Still offline. It will sync when the connection is back.'
          : null;
    });
    _refresh();
  }

  Future<void> _discard() async {
    final queue = _queue;
    if (queue == null) return;
    await queue.discard(widget.offlineId);
    if (mounted) context.go('/pos');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final entry = _entry;
    final request = entry?.request;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(t.spacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: t.color.content.secondary),
              SizedBox(height: t.spacing.md),
              Text(
                entry == null ? 'Not in the sync queue any more' : 'This order is waiting to sync',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: t.spacing.sm),
              if (request != null)
                Text(
                  [
                    OrderTypes.label(request.type),
                    if (request.covers != null) '${request.covers} guests',
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.color.content.secondary),
                )
              else
                Text(
                  'It may have synced already. Check Orders for it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: t.color.content.secondary),
                ),
              if (entry != null && entry.isRejected) ...[
                SizedBox(height: t.spacing.md),
                InlineAlert(message: 'The server did not accept this order: ${entry.lastError}'),
              ],
              if (_message != null) ...[
                SizedBox(height: t.spacing.md),
                InlineAlert(message: _message!, tone: StatusTone.warning),
              ],
              SizedBox(height: t.spacing.lg),
              if (entry != null)
                AppButton(
                  label: 'Try again now',
                  variant: AppButtonVariant.primary,
                  loading: _busy,
                  onPressed: _busy ? null : _retry,
                ),
              if (entry != null && entry.isRejected) ...[
                SizedBox(height: t.spacing.sm),
                AppButton(
                  label: 'Discard this order',
                  variant: AppButtonVariant.danger,
                  onPressed: _busy ? null : _discard,
                ),
              ],
              SizedBox(height: t.spacing.sm),
              AppButton(
                label: 'Back to tables',
                variant: AppButtonVariant.ghost,
                onPressed: () => context.go('/pos'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- order workspace ---------------------------------------------------------

class _OrderWorkspace extends ConsumerStatefulWidget {
  const _OrderWorkspace({required this.orderId});

  final String orderId;

  @override
  ConsumerState<_OrderWorkspace> createState() => _OrderWorkspaceState();
}

class _OrderWorkspaceState extends ConsumerState<_OrderWorkspace> {
  /// null = Favourites. [_combosKey] = combos.
  String? _category;
  String _search = '';

  PosOrderController get _ctrl => ref.read(posOrderProvider(widget.orderId).notifier);

  OrderView? get _order => ref.read(posOrderProvider(widget.orderId)).order;

  Future<void> _tapProduct(PosMenu menu, PosProduct product, {PosVariant? variant}) async {
    final order = _order;
    if (order == null) return;
    final chosen = variant ?? product.defaultVariant;
    final usage = ref.read(productUsageProvider).valueOrNull;
    usage?.record(product.id);
    setState(() {});

    final groups = menu.groupsFor(product);
    if (groups.isEmpty) {
      final name = chosen != null && product.variants.length > 1
          ? '${product.name} ${chosen.name}'
          : product.name;
      await _ctrl.addLine(
        AddItem(productId: product.id, variantId: chosen?.id),
        name: name,
      );
      return;
    }
    final sel = await showModifierSheet(
      context,
      product: product,
      variant: chosen,
      groups: groups,
      covers: order.covers,
    );
    if (sel == null || !mounted) return;
    await _ctrl.addLine(
      AddItem(
        productId: product.id,
        variantId: sel.variantId,
        quantity: sel.quantity,
        seat: sel.seat,
        note: sel.note,
        modifierOptionIds: sel.optionIds,
      ),
      name: product.name,
      seat: sel.seat,
    );
  }

  Future<void> _tapCombo(PosCombo combo) =>
      _ctrl.addLine(AddItem(comboId: combo.id), name: combo.name);

  Future<void> _send() async {
    final result = await _ctrl.send();
    if (result == null || !mounted) return;
    final sent = result.tickets.map((t) => '${t.kind} ${t.station} #${t.seq}').join(', ');
    showAppToast(context, result.tickets.isEmpty ? 'Nothing new to send.' : 'Sent: $sent');
  }

  Future<void> _hold() async {
    final order = _order;
    if (order == null) return;
    await _ctrl.setHold(held: !order.isHeld);
  }

  Future<void> _discount() async {
    final order = _order;
    if (order == null) return;
    final updated = await showDiscountDialog(context, order: order);
    if (updated == null || !mounted) return;
    _ctrl.replaceOrder(updated);
    showAppToast(context, 'Discount applied.');
  }

  Future<void> _void() async {
    final order = _order;
    if (order == null) return;
    final updated = await showVoidDialog(context, order: order);
    if (updated == null || !mounted) return;
    _ctrl.replaceOrder(updated);
  }

  Future<void> _transfer() async {
    final order = _order;
    if (order == null) return;
    final updated = await showTransferDialog(context, order: order);
    if (updated == null || !mounted) return;
    _ctrl.replaceOrder(updated);
    showAppToast(context, 'Order updated.');
  }

  Future<void> _bill() async {
    final updated = await _ctrl.printBill();
    if (updated == null || !mounted) return;
    showAppToast(context, 'Bill sent to the receipt printer.');
  }

  Future<void> _closeTable() async {
    final updated = await _ctrl.closeTable();
    if (updated == null || !mounted) return;
    showAppToast(context, 'Table closed.');
    context.go('/pos');
  }

  PosTicketActions get _actions => PosTicketActions(
        onQuantity: (item, qty) => _ctrl.setQuantity(item, qty),
        onSeat: (item) => _ctrl.setSeat(item, nextSeat(item.seat, _order?.covers ?? 1)),
        onSend: _send,
        onHold: _hold,
        onSplit: () => context.go('/pos/${widget.orderId}/pay'),
        onDiscount: _discount,
        onTransfer: _transfer,
        onVoid: _void,
        onPrintBill: _bill,
        onPay: () => context.go('/pos/${widget.orderId}/pay'),
        onCloseTable: _closeTable,
      );

  void _openTicketSheet() {
    final height = MediaQuery.of(context).size.height * 0.88;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SizedBox(
        height: height,
        child: PosTicketPanel(orderId: widget.orderId, actions: _actions),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posOrderProvider(widget.orderId));
    final order = state.order;
    if (order == null) {
      if (state.error != null && !state.loading) {
        return Padding(
          padding: EdgeInsets.all(context.tokens.spacing.md),
          child: ErrorState(
            message: state.error!,
            onRetry: () => _ctrl.load(),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final menu = ref.watch(posMenuProvider).valueOrNull ?? const PosMenu();
    final menuError = ref.watch(posMenuProvider).error;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= wideLayoutMinWidth;
        final main = _WorkspaceMain(
          order: order,
          menu: menu,
          menuError: menuError == null ? null : ApiError.from(menuError).message,
          state: state,
          wide: wide,
          category: _category,
          search: _search,
          onCategory: (c) => setState(() => _category = c),
          onSearch: (s) => setState(() => _search = s),
          onProduct: (p) => _tapProduct(menu, p),
          onVariant: (p, v) => _tapProduct(menu, p, variant: v),
          onCombo: _tapCombo,
          onBack: () => context.go('/pos'),
          onDismissError: _ctrl.clearError,
          onOpenTicket: _openTicketSheet,
        );
        if (!wide) return main;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: main),
            SizedBox(
              width: 380,
              child: PosTicketPanel(orderId: widget.orderId, actions: _actions),
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceMain extends ConsumerWidget {
  const _WorkspaceMain({
    required this.order,
    required this.menu,
    required this.menuError,
    required this.state,
    required this.wide,
    required this.category,
    required this.search,
    required this.onCategory,
    required this.onSearch,
    required this.onProduct,
    required this.onVariant,
    required this.onCombo,
    required this.onBack,
    required this.onDismissError,
    required this.onOpenTicket,
  });

  final OrderView order;
  final PosMenu menu;
  final String? menuError;
  final PosOrderState state;
  final bool wide;
  final String? category;
  final String search;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String> onSearch;
  final ValueChanged<PosProduct> onProduct;
  final void Function(PosProduct, PosVariant) onVariant;
  final ValueChanged<PosCombo> onCombo;
  final VoidCallback onBack;
  final VoidCallback onDismissError;
  final VoidCallback onOpenTicket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final usage = ref.watch(productUsageProvider).valueOrNull;
    final favourites = usage?.topIds() ?? const <String>[];
    final products = _productsFor(menu, favourites, search);
    final combos = [
      for (final c in menu.combos)
        if (search.isEmpty || c.name.toLowerCase().contains(search.toLowerCase())) c,
    ];
    final showCombos = category == _combosKey && search.isEmpty;
    final lineCount = order.liveItems.length + state.pending.length;

    final rail = _CategoryRail(
      vertical: wide,
      menu: menu,
      selected: category,
      hasCombos: menu.combos.isNotEmpty,
      onSelect: onCategory,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(order: order, menu: menu, onBack: onBack),
        Padding(
          padding: EdgeInsets.fromLTRB(t.spacing.md, 0, t.spacing.md, t.spacing.sm),
          child: Column(
            children: [
              const _SyncBanner(offline: false),
              if (state.offline)
                const _SyncBanner(offline: true),
              if (state.error != null)
                AppBanner(
                  message: state.error!,
                  tone: StatusTone.danger,
                  actionLabel: 'Dismiss',
                  onAction: onDismissError,
                ),
              if (menuError != null)
                AppBanner(message: 'Menu did not load: $menuError', tone: StatusTone.danger),
            ],
          ),
        ),
        Expanded(
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 180, child: rail),
                    Expanded(child: _ProductArea(
                      search: search,
                      onSearch: onSearch,
                      grid: PosProductGrid(
                        products: products,
                        combos: combos,
                        showCombos: showCombos,
                        onProduct: onProduct,
                        onVariant: onVariant,
                        onCombo: onCombo,
                      ),
                    )),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    rail,
                    Expanded(child: _ProductArea(
                      search: search,
                      onSearch: onSearch,
                      grid: PosProductGrid(
                        products: products,
                        combos: combos,
                        showCombos: showCombos,
                        onProduct: onProduct,
                        onVariant: onVariant,
                        onCombo: onCombo,
                      ),
                    )),
                  ],
                ),
        ),
        if (!wide)
          Container(
            color: t.color.background.surface,
            padding: EdgeInsets.all(t.spacing.md),
            child: AppButton(
              label: lineCount == 0
                  ? 'View order'
                  : 'View order · ${lineCount == 1 ? '1 item' : '$lineCount items'} · '
                      '${formatWire(order.totals.grandTotal)}',
              variant: AppButtonVariant.primary,
              onPressed: onOpenTicket,
            ),
          ),
      ],
    );
  }

  /// Favourites (top used, or the first 12 when nothing has been tapped yet),
  /// one category, or a search across all products.
  List<PosProduct> _productsFor(PosMenu menu, List<String> favourites, String search) {
    if (search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      return [for (final p in menu.products) if (p.name.toLowerCase().contains(q)) p];
    }
    if (category == _combosKey) return const [];
    if (category == null) {
      final fav = [
        for (final id in favourites)
          if (menu.productById(id) != null) menu.productById(id)!,
      ];
      if (fav.isNotEmpty) return fav;
      return menu.products.take(ProductUsage.favouriteCount).toList();
    }
    return [for (final p in menu.products) if (p.categoryId == category) p];
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.order, required this.menu, required this.onBack});

  final OrderView order;
  final PosMenu menu;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final happy = menu.activeHappyHours;
    final endsAt = happy.isEmpty ? null : happy.first.endsAt;
    final place = order.table == null
        ? OrderTypes.label(order.type)
        : 'Table ${order.table!.name} · ${order.covers} covers';
    return Padding(
      padding: EdgeInsets.all(t.spacing.md),
      child: Wrap(
        spacing: t.spacing.sm,
        runSpacing: t.spacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          AppIconButton(icon: Icons.arrow_back, tooltip: 'Back to tables', onPressed: onBack),
          for (final type in OrderTypes.all)
            PosChoiceChip(
              label: OrderTypes.label(type),
              selected: order.type == type,
              minHeight: 44,
              onTap: null,
            ),
          if (happy.isNotEmpty)
            StatusBadge(
              label: endsAt == null
                  ? 'Happy hour on'
                  : 'Happy hour ends ${formatClock(endsAt.toLocal())}',
              tone: StatusTone.warning,
            ),
          StatusBadge(label: place, tone: StatusTone.neutral),
          if (order.waiter != null)
            StatusBadge(label: 'Waiter: ${order.waiter!.name}', tone: StatusTone.neutral),
        ],
      ),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.vertical,
    required this.menu,
    required this.selected,
    required this.hasCombos,
    required this.onSelect,
  });

  final bool vertical;
  final PosMenu menu;
  final String? selected;
  final bool hasCombos;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final items = <Widget>[
      _RailItem(
        label: 'Favourites',
        selected: selected == null,
        onTap: () => onSelect(null),
        vertical: vertical,
      ),
      for (final c in menu.categories)
        _RailItem(
          label: c.name,
          color: parseHexColor(c.color),
          selected: selected == c.id,
          onTap: () => onSelect(c.id),
          vertical: vertical,
        ),
      if (hasCombos)
        _RailItem(
          label: 'Combos & buckets',
          selected: selected == _combosKey,
          onTap: () => onSelect(_combosKey),
          vertical: vertical,
        ),
    ];
    if (vertical) {
      return ListView(
        padding: EdgeInsets.all(t.spacing.sm),
        children: items,
      );
    }
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: t.spacing.md, vertical: t.spacing.xs),
        children: [
          for (final item in items)
            Padding(padding: EdgeInsets.only(right: t.spacing.sm), child: item),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.vertical,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool vertical;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dot = color;
    return Material(
      color: selected ? t.color.background.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(t.radius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radius.md),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          width: vertical ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: t.spacing.md, vertical: t.spacing.sm),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: vertical ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                SizedBox(width: t.spacing.sm),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? t.color.content.primary : t.color.content.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductArea extends StatelessWidget {
  const _ProductArea({required this.search, required this.onSearch, required this.grid});

  final String search;
  final ValueChanged<String> onSearch;
  final Widget grid;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.spacing.md, t.spacing.xs, t.spacing.md, 0),
          child: AppTextField(
            label: 'Search menu',
            hint: 'Type a product name',
            onChanged: onSearch,
            controller: null,
          ),
        ),
        Expanded(child: grid),
      ],
    );
  }
}
