import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ui.dart';
import '../data/guest_requests_providers.dart';

/// Nav id of the Guest orders page (nav_registry.dart).
const guestOrdersNavId = 'guest-orders';

/// Guest orders icon with the live count of pending rounds and unacknowledged
/// service requests. Used by the phone footer tab.
class GuestOrdersTabIcon extends ConsumerWidget {
  const GuestOrdersTabIcon({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(guestLiveProvider);
    final count = ref.watch(guestBadgeCountProvider);
    final t = context.tokens;
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: t.color.background.danger,
      textColor: t.color.content.onAccent,
      label: Text(count > 99 ? '99+' : '$count', key: const ValueKey('guest-orders-badge')),
      child: Icon(icon),
    );
  }
}
