import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

/// `/service/ready`: food and drink waiting for the waiter. Mine and All
/// toggle, overdue cards in red, and a Served button per ticket. Design:
/// MobileStaff "Ready alert & mark served".
class ReadyToServeScreen extends ConsumerStatefulWidget {
  const ReadyToServeScreen({super.key});

  @override
  ConsumerState<ReadyToServeScreen> createState() => _ReadyToServeScreenState();
}

class _ReadyToServeScreenState extends ConsumerState<ReadyToServeScreen> {
  bool _mine = true;
  Timer? _ticker;
  late final OfflinePoller _poller;
  late final ValueListenable<bool> _connected;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
    final client = ref.read(realtimeClientProvider);
    _connected = client.connected;
    _connected.addListener(_onConnectedChanged);
    _poller = OfflinePoller(
      connected: _connected,
      interval: const Duration(seconds: 10),
      refresh: () async => _refresh(),
    )..start();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _poller.stop();
    _connected.removeListener(_onConnectedChanged);
    super.dispose();
  }

  void _onConnectedChanged() {
    if (_connected.value) _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(readyItemsProvider(_mine));
  }

  Future<void> _served(ReadyItem item) async {
    try {
      await ref.read(kdsRepositoryProvider).served(item.ticketId);
    } catch (e) {
      if (mounted) showAppToast(context, kdsErrorMessage(ApiError.from(e)));
    }
    _refresh();
  }

  /// Minutes since the ticket became READY. Uses the device clock.
  static Duration _waiting(ReadyItem item) {
    final readyAt = item.readyAt;
    if (readyAt == null) return Duration(seconds: item.waitingSeconds);
    return DateTime.now().difference(readyAt);
  }

  static String _waitingText(Duration d) {
    final minutes = d.isNegative ? 0 : d.inMinutes;
    return minutes < 1 ? 'waiting under a minute' : 'waiting $minutes min';
  }

  static String _lineHeadline(ReadyLine line) {
    final variant = line.variantName;
    final base = variant == null || variant.isEmpty ? line.name : '${line.name} $variant';
    return '${line.quantity} × $base';
  }

  static bool _isOverdue(ReadyItem item) => item.overdue || _waiting(item).inMinutes > 5;

  Widget _card(BuildContext context, ReadyItem item, bool canServe) {
    final t = context.tokens;
    final overdue = _isOverdue(item);
    final waiting = _waiting(item);
    return Container(
      padding: EdgeInsets.all(t.spacing.md),
      decoration: BoxDecoration(
        color: t.color.background.raised,
        borderRadius: BorderRadius.circular(t.radius.lg),
        border: Border.all(
          color: overdue ? t.color.background.danger : t.color.border.subtle,
          width: overdue ? t.borderWidth.thick : t.borderWidth.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ready at the ${item.station.toLowerCase()} · ${item.placeLabel}',
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (overdue) const StatusBadge(label: 'Overdue', tone: StatusTone.danger),
            ],
          ),
          SizedBox(height: t.spacing.xs),
          Text(
            '${item.label} · ${_waitingText(waiting)}',
            style: TextStyle(
              color: overdue ? t.color.content.danger : t.color.content.secondary,
            ),
          ),
          SizedBox(height: t.spacing.sm),
          for (final line in item.items)
            Padding(
              padding: EdgeInsets.only(bottom: t.spacing.xs),
              child: Text(
                [
                  _lineHeadline(line),
                  if (line.seat != null) 'seat ${line.seat}',
                ].join(' · '),
                style: TextStyle(fontWeight: FontWeight.w600, color: t.color.content.primary),
              ),
            ),
          SizedBox(height: t.spacing.sm),
          AppButton(
            label: 'Served',
            variant: AppButtonVariant.primary,
            size: AppControlSize.lg,
            onPressed: canServe ? () => _served(item) : null,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    ref.listen(realtimeEventProvider(RealtimeEvents.kdsReady), (_, __) => _refresh());

    final canView = can(ref, Perm.kdsBump, AccessLevel.view) ||
        can(ref, Perm.salesOrdersTake, AccessLevel.view);
    final canServe = can(ref, Perm.salesOrdersTake, AccessLevel.edit) ||
        can(ref, Perm.kdsBump, AccessLevel.edit);
    final ready = ref.watch(readyItemsProvider(_mine));

    return DensityScope(
      density: AppDensity.pos,
      child: Scaffold(
        body: SafeArea(
          child: !canView
              ? const EmptyState(title: "You can't see ready orders on this device.")
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHeader(
                      title: 'Ready to serve',
                      actions: [
                        PosChoiceChip(
                          label: 'Mine',
                          selected: _mine,
                          minHeight: 44,
                          onTap: () => setState(() => _mine = true),
                        ),
                        PosChoiceChip(
                          label: 'All',
                          selected: !_mine,
                          minHeight: 44,
                          onTap: () => setState(() => _mine = false),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ready.when(
                        loading: () => const DelayedSkeleton(child: SkeletonList()),
                        error: (e, _) => ErrorState(
                          message: ApiError.from(e).message,
                          onRetry: _refresh,
                        ),
                        data: (items) {
                          if (items.isEmpty) {
                            return EmptyState(
                              title: _mine ? 'Nothing ready for you' : 'Nothing ready',
                              message: 'Ready orders appear here as the bar and kitchen bump them.',
                            );
                          }
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final cardWidth = constraints.maxWidth >= 600
                                  ? 340.0
                                  : constraints.maxWidth - t.spacing.md * 2;
                              return SingleChildScrollView(
                                padding: EdgeInsets.all(t.spacing.md),
                                child: Wrap(
                                  spacing: t.spacing.md,
                                  runSpacing: t.spacing.md,
                                  children: [
                                    for (final item in items)
                                      SizedBox(
                                        width: cardWidth,
                                        child: _card(context, item, canServe),
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
}
