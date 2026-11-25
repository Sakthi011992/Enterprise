import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/realtime/offline_poller.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/ui/ui.dart';
import '../../pos/presentation/dialogs/dialog_frame.dart';
import '../data/kds_models.dart';
import '../data/kds_repository.dart';
import '../domain/kds_rules.dart';
import 'kds_providers.dart';

/// `/kds`: the kitchen and bar display. New, Preparing and Ready to serve
/// columns, with Start, Bump, Recall and Served on each ticket. Design: KDS
/// board. `initialStation` preselects a station (`/kds?station=BAR`).
class KdsScreen extends ConsumerStatefulWidget {
  const KdsScreen({super.key, this.initialStation});

  /// Station code to show first, such as `BAR`. Null means all stations.
  final String? initialStation;

  @override
  ConsumerState<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends ConsumerState<KdsScreen> {
  static const _all = 'ALL';

  late String _station;
  bool _fullScreen = false;
  Timer? _ticker;
  Timer? _debounce;
  late final OfflinePoller _poller;
  late final ValueListenable<bool> _connected;

  @override
  void initState() {
    super.initState();
    _station = widget.initialStation?.toUpperCase() ?? _all;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    final client = ref.read(realtimeClientProvider);
    _connected = client.connected;
    _connected.addListener(_onConnectedChanged);
    _poller = OfflinePoller(
      connected: _connected,
      interval: const Duration(seconds: 5),
      refresh: () async => _refresh(),
    )..start();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _debounce?.cancel();
    _poller.stop();
    _connected.removeListener(_onConnectedChanged);
    if (_fullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _onConnectedChanged() {
    if (_connected.value) _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(kdsBoardProvider(_station));
  }

  /// Several events can arrive in a burst. One refresh covers them.
  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _refresh);
  }

  void _selectStation(String station) {
    setState(() => _station = station);
  }

  void _toggleFullScreen() {
    setState(() => _fullScreen = !_fullScreen);
    SystemChrome.setEnabledSystemUIMode(
      _fullScreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  Future<void> _act(KdsTicket ticket, KdsAction action) async {
    final repo = ref.read(kdsRepositoryProvider);
    try {
      final call = switch (action) {
        KdsAction.start => repo.start(ticket.id),
        KdsAction.bump => repo.bump(ticket.id),
        KdsAction.recall => repo.recall(ticket.id),
        KdsAction.served => repo.served(ticket.id),
      };
      await call;
    } catch (e) {
      if (mounted) showAppToast(context, kdsErrorMessage(ApiError.from(e)));
    }
    _refresh();
  }

  void _recallLast(KdsBoard? board) {
    final last = lastBumped(board?.tickets ?? const []);
    if (last == null) {
      showAppToast(context, 'Nothing to recall.');
      return;
    }
    _act(last, KdsAction.recall);
  }

  static String _actionLabel(KdsAction a) => switch (a) {
        KdsAction.start => 'Start',
        KdsAction.bump => 'Bump',
        KdsAction.recall => 'Recall',
        KdsAction.served => 'Served',
      };

  static AppButtonVariant _actionVariant(KdsAction a) => switch (a) {
        KdsAction.start => AppButtonVariant.secondary,
        KdsAction.bump => AppButtonVariant.primary,
        KdsAction.recall => AppButtonVariant.ghost,
        KdsAction.served => AppButtonVariant.primary,
      };

  static Color _tone(BuildContext context, TicketColour colour) {
    final t = context.tokens;
    return switch (colour) {
      TicketColour.green => t.color.background.success,
      TicketColour.amber => t.color.background.warning,
      TicketColour.red => t.color.background.danger,
    };
  }

  /// Age on a New or Preparing ticket, "Ready 1 min" on a READY one.
  static String _ageText(KdsTicket ticket, DateTime now) {
    final readyAt = ticket.readyAt;
    if (ticket.isReady && readyAt != null) {
      return readyForLabel(now.difference(readyAt));
    }
    final createdAt = ticket.createdAt;
    final age = createdAt == null
        ? Duration(seconds: ticket.ageSeconds)
        : now.difference(createdAt);
    return formatTicketAge(age);
  }

  Widget _itemLine(BuildContext context, KdsItem item) {
    final t = context.tokens;
    final details = [
      if (item.modifiers.isNotEmpty) item.modifiers.join(' · '),
      if (item.seat != null) 'seat ${item.seat}',
      if (item.note != null && item.note!.isNotEmpty) item.note!,
    ];
    final color = item.voided ? t.color.content.muted : t.color.content.primary;
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.voided ? '${item.headline} · cancelled' : item.headline,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              decoration: item.voided ? TextDecoration.lineThrough : null,
            ),
          ),
          if (details.isNotEmpty)
            Text(details.join(' · '), style: TextStyle(color: t.color.content.secondary)),
        ],
      ),
    );
  }

  Widget _ticketCard(BuildContext context, KdsTicket ticket, DateTime now, bool canAct) {
    final t = context.tokens;
    final colour = ticketColourAt(
      createdAt: ticket.createdAt ?? now,
      readyAt: ticket.readyAt,
      now: now,
    );
    final place = ticket.order.placeLabel;
    final waiter = ticket.order.waiterName;
    return Container(
      margin: EdgeInsets.only(bottom: t.spacing.sm),
      decoration: BoxDecoration(
        color: t.color.background.raised,
        borderRadius: BorderRadius.circular(t.radius.lg),
        border: Border.all(color: t.color.border.subtle, width: t.borderWidth.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: _tone(context, colour)),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(t.spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${ticket.label} · $place',
                            style: Theme.of(context).textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _ageText(ticket, now),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    if (ticket.isReady && waiter != null && waiter.isNotEmpty)
                      Text(
                        'Waiter $waiter notified',
                        style: TextStyle(color: t.color.content.secondary),
                      ),
                    SizedBox(height: t.spacing.sm),
                    for (final item in ticket.items) _itemLine(context, item),
                    SizedBox(height: t.spacing.xs),
                    Wrap(
                      spacing: t.spacing.sm,
                      runSpacing: t.spacing.sm,
                      children: [
                        for (final action in actionsFor(ticket))
                          AppButton(
                            label: _actionLabel(action),
                            variant: _actionVariant(action),
                            size: AppControlSize.md,
                            onPressed: canAct ? () => _act(ticket, action) : null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _columnHeader(BuildContext context, String title, int count) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.spacing.xs, t.spacing.xs, t.spacing.xs, t.spacing.sm),
      child: Text(
        '$title · $count',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  List<Widget> _columnChildren(
    BuildContext context,
    String title,
    List<KdsTicket> tickets,
    DateTime now,
    bool canAct,
  ) {
    return [
      _columnHeader(context, title, tickets.length),
      if (tickets.isEmpty)
        Padding(
          padding: EdgeInsets.all(context.tokens.spacing.md),
          child: Text(
            'Nothing here',
            style: TextStyle(color: context.tokens.color.content.muted),
          ),
        ),
      for (final ticket in tickets) _ticketCard(context, ticket, now, canAct),
    ];
  }

  Widget _board(BuildContext context, KdsBoard board, bool canAct) {
    final t = context.tokens;
    final now = DateTime.now().add(board.clockOffset);
    final newTickets = board.withStatus(KdsStatuses.newTicket);
    final preparing = board.withStatus(KdsStatuses.preparing);
    final ready = board.withStatus(KdsStatuses.ready);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1024 && !_fullScreen;
        final columnsWide = constraints.maxWidth >= 600;

        Widget columns;
        if (columnsWide) {
          columns = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (title, tickets) in [
                ('New', newTickets),
                ('Preparing', preparing),
                ('Ready to serve', ready),
              ])
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: t.spacing.xs),
                    children: _columnChildren(context, title, tickets, now, canAct),
                  ),
                ),
            ],
          );
        } else {
          columns = ListView(
            padding: EdgeInsets.all(t.spacing.sm),
            children: [
              ..._columnChildren(context, 'New', newTickets, now, canAct),
              ..._columnChildren(context, 'Preparing', preparing, now, canAct),
              ..._columnChildren(context, 'Ready to serve', ready, now, canAct),
            ],
          );
        }

        if (!wide) return columns;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: columns),
            SizedBox(
              width: 260,
              child: _allDayPanel(context, board),
            ),
          ],
        );
      },
    );
  }

  Widget _allDayPanel(BuildContext context, KdsBoard board) {
    final t = context.tokens;
    return Container(
      margin: EdgeInsets.all(t.spacing.sm),
      padding: EdgeInsets.all(t.spacing.md),
      decoration: BoxDecoration(
        color: t.color.background.raised,
        borderRadius: BorderRadius.circular(t.radius.lg),
        border: Border.all(color: t.color.border.subtle, width: t.borderWidth.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('All day', style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: t.spacing.sm),
          Expanded(
            child: board.allDay.isEmpty
                ? Text('Nothing sold yet', style: TextStyle(color: t.color.content.muted))
                : ListView(
                    children: [
                      for (final row in board.allDay)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: t.spacing.xs),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  row.variantName == null || row.variantName!.isEmpty
                                      ? row.name
                                      : '${row.name} ${row.variantName}',
                                ),
                              ),
                              Text('${row.quantity}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          SizedBox(height: t.spacing.sm),
          Text(
            avgTicketLabel(board.avgTicketSeconds),
            style: TextStyle(color: t.color.content.secondary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    ref.listen(realtimeEventProvider(RealtimeEvents.kdsTicketCreated), (_, __) => _scheduleRefresh());
    ref.listen(realtimeEventProvider(RealtimeEvents.kdsTicketUpdated), (_, __) => _scheduleRefresh());

    final canView = can(ref, Perm.kdsBump, AccessLevel.view);
    final canAct = can(ref, Perm.kdsBump, AccessLevel.edit);
    final stations = ref.watch(kdsStationsProvider);
    final board = ref.watch(kdsBoardProvider(_station));

    if (!canView) {
      return DensityScope(
        density: AppDensity.pos,
        child: const Scaffold(
          body: SafeArea(
            child: EmptyState(title: "You can't open the kitchen display on this device."),
          ),
        ),
      );
    }

    final stationList = stations.valueOrNull ?? const <KdsStation>[];
    return DensityScope(
      density: AppDensity.pos,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_fullScreen)
                PageHeader(
                  title: 'Kitchen & bar display',
                  actions: [
                    AppButton(
                      label: 'Recall last',
                      variant: AppButtonVariant.ghost,
                      onPressed: canAct ? () => _recallLast(board.valueOrNull) : null,
                    ),
                  ],
                ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: t.spacing.md),
                child: Wrap(
                  spacing: t.spacing.sm,
                  runSpacing: t.spacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PosChoiceChip(
                      label: 'All',
                      selected: _station == _all,
                      minHeight: 44,
                      onTap: () => _selectStation(_all),
                    ),
                    for (final s in stationList)
                      PosChoiceChip(
                        label: s.label,
                        selected: _station == s.station,
                        minHeight: 44,
                        onTap: () => _selectStation(s.station),
                      ),
                    Text(
                      'Green under 5 min · amber 5–10 · red over 10',
                      style: TextStyle(color: t.color.content.secondary),
                    ),
                    AppIconButton(
                      icon: _fullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      tooltip: _fullScreen ? 'Exit full screen' : 'Full screen',
                      onPressed: _toggleFullScreen,
                    ),
                  ],
                ),
              ),
              SizedBox(height: t.spacing.sm),
              Expanded(
                child: board.when(
                  loading: () => const DelayedSkeleton(child: SkeletonList()),
                  error: (e, _) => ErrorState(
                    message: ApiError.from(e).message,
                    onRetry: _refresh,
                  ),
                  data: (data) => _board(context, data, canAct),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
