import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../kds/data/kds_models.dart';

/// "QR · Deepa" for a ticket whose order came from a guest QR round, else
/// null. The guest name comes from the order, or from the ticket lines.
String? kdsQrLabel(KdsTicket ticket) {
  final order = ticket.order;
  final fromLines = <String>{
    for (final i in ticket.items)
      if (i.guestName != null && i.guestName!.isNotEmpty) i.guestName!,
  };
  if (!order.isGuestQr && fromLines.isEmpty) return null;
  final name = order.guestName ?? (fromLines.isEmpty ? null : fromLines.join(', '));
  return name == null || name.isEmpty ? 'QR' : 'QR · $name';
}

/// Read-only chip in the KDS ticket header for QR orders.
class KdsQrLabel extends StatelessWidget {
  const KdsQrLabel({super.key, required this.ticket});

  final KdsTicket ticket;

  @override
  Widget build(BuildContext context) {
    final label = kdsQrLabel(ticket);
    if (label == null) return const SizedBox.shrink();
    final t = context.tokens;
    final ext = context.ext;
    return Container(
      margin: EdgeInsets.only(right: t.spacing.sm),
      padding: EdgeInsets.symmetric(horizontal: t.spacing.sm, vertical: 2),
      decoration: BoxDecoration(color: ext.accentSubtle, borderRadius: BorderRadius.circular(t.radius.pill)),
      child: Text(label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ext.onAccentSubtle)),
    );
  }
}
