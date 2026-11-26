import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/ui.dart';
import 'notifications.dart';

/// Opens the notifications panel as a dialog.
Future<void> showNotificationsPanel(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final t = context.tokens;
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 460,
          height: 520,
          decoration: BoxDecoration(
            color: t.color.background.raised,
            borderRadius: BorderRadius.circular(t.radius.lg),
            border: Border.all(color: t.color.border.standard),
            boxShadow: context.ext.raisedShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: const Material(
              color: Colors.transparent, child: NotificationsPanel()),
        ),
      );
    },
  );
}

/// Tabs: All, Approvals, Alerts. Approve/Decline stay disabled until Phase 2.
class NotificationsPanel extends ConsumerWidget {
  const NotificationsPanel({super.key});

  static const _alertTypes = {'alert', 'device', 'stock'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final list = ref.watch(notificationListProvider);

    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                t.spacing.md, t.spacing.md, t.spacing.sm, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('Notifications',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                AppButton(
                  label: 'Mark all read',
                  variant: AppButtonVariant.ghost,
                  onPressed:
                      list.hasValue && list.requireValue.any((n) => !n.isRead)
                          ? () => _markAll(ref)
                          : null,
                ),
              ],
            ),
          ),
          const TabBar(tabs: [
            Tab(text: 'All'),
            Tab(text: 'Approvals'),
            Tab(text: 'Alerts')
          ]),
          Expanded(
            child: list.when(
              loading: () => const DelayedSkeleton(child: SkeletonList()),
              error: (e, _) => ErrorState(
                message: 'Your notifications did not load. Try again.',
                onRetry: () => ref.invalidate(notificationListProvider),
              ),
              data: (items) => TabBarView(
                children: [
                  _NotificationList(items: items, ref: ref),
                  _NotificationList(
                    items: items.where((n) => n.type == 'approval').toList(),
                    ref: ref,
                  ),
                  _NotificationList(
                    items: items
                        .where((n) => _alertTypes.contains(n.type))
                        .toList(),
                    ref: ref,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markAll(WidgetRef ref) async {
    await ref.read(notificationsRepositoryProvider).markAllRead();
    ref.invalidate(notificationListProvider);
    ref.read(notificationsProvider.notifier).refresh();
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({required this.items, required this.ref});

  final List<AppNotification> items;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyState(
          title: 'Nothing here yet', message: 'You are all caught up.');
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, _) =>
          Divider(height: 1, color: context.tokens.color.border.subtle),
      itemBuilder: (context, i) => _NotificationTile(item: items[i], ref: ref),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.ref});

  final AppNotification item;
  final WidgetRef ref;

  StatusTone get _tone => switch (item.type) {
        'approval' => StatusTone.info,
        'alert' => StatusTone.danger,
        'device' || 'stock' => StatusTone.warning,
        _ => StatusTone.neutral,
      };

  Future<void> _markRead() async {
    await ref.read(notificationsRepositoryProvider).markRead(item.id);
    ref.invalidate(notificationListProvider);
    ref.read(notificationsProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isApproval = item.type == 'approval';
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: t.spacing.md, vertical: t.spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(label: item.type, tone: _tone),
              SizedBox(width: t.spacing.sm),
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: item.isRead ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (item.body != null && item.body!.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: t.spacing.xs),
              child: Text(item.body!,
                  style: TextStyle(color: t.color.content.secondary)),
            ),
          SizedBox(height: t.spacing.xs),
          if (isApproval)
            Row(
              children: [
                Tooltip(
                  message: 'Approvals arrive in Phase 2',
                  child: AppButton(
                      label: 'Approve', variant: AppButtonVariant.primary),
                ),
                SizedBox(width: t.spacing.sm),
                Tooltip(
                  message: 'Approvals arrive in Phase 2',
                  child: AppButton(
                      label: 'Decline', variant: AppButtonVariant.danger),
                ),
              ],
            )
          else if (!item.isRead)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                label: 'Mark read',
                variant: AppButtonVariant.ghost,
                onPressed: _markRead,
              ),
            ),
        ],
      ),
    );
  }
}
