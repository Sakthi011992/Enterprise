/// Pure KDS rules: colour thresholds, age text, error copy. No widgets here, so
/// the tests can call them directly.
library;

import '../../../core/auth/api_error.dart';
import '../data/kds_models.dart';

/// Colour of a ticket by age. Design: green under 5 min, amber 5-10 min, red
/// over 10 min.
enum TicketColour { green, amber, red }

TicketColour colourForAge(Duration age) {
  if (age < const Duration(minutes: 5)) return TicketColour.green;
  if (age <= const Duration(minutes: 10)) return TicketColour.amber;
  return TicketColour.red;
}

/// Colour of a ticket at [now] (server time). The clock stops at [readyAt]
/// once the ticket is READY, as the plan says.
TicketColour ticketColourAt({
  required DateTime createdAt,
  DateTime? readyAt,
  required DateTime now,
}) {
  final end = readyAt ?? now;
  return colourForAge(end.difference(createdAt));
}

/// Parses the server's `colour` string. Unknown values fall back to green.
TicketColour colourFromWire(String wire) => switch (wire) {
      'amber' => TicketColour.amber,
      'red' => TicketColour.red,
      _ => TicketColour.green,
    };

/// Age timer text: "0:42", "1:10", "11:20". Minutes are not padded, seconds are.
String formatTicketAge(Duration age) {
  final total = age.isNegative ? 0 : age.inSeconds;
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Waiting text on a READY card: "Ready 1 min", "Ready 3 min".
String readyForLabel(Duration sinceReady) {
  final minutes = sinceReady.isNegative ? 0 : sinceReady.inMinutes;
  return minutes < 1 ? 'Ready just now' : 'Ready $minutes min';
}

/// Average ticket time line: "Avg ticket time today 4:52".
String avgTicketLabel(int seconds) => 'Avg ticket time today ${formatTicketAge(Duration(seconds: seconds))}';

/// Words for a KDS failure. Unknown codes show the server message.
String kdsErrorMessage(ApiError e) {
  switch (e.code) {
    case 'KDS_BAD_STATE':
      return 'That ticket has already moved on. The board has been refreshed.';
    case 'RECALL_TOO_LATE':
      return "Too late to recall. Served tickets can be recalled for 30 minutes.";
    case 'PERMISSION_DENIED':
      return "You don't have permission to change tickets on this display.";
    default:
      return e.message;
  }
}

/// Column a ticket sits in on the board.
enum KdsColumn { newTickets, preparing, ready }

KdsColumn columnFor(KdsTicket ticket) {
  if (ticket.isPreparing) return KdsColumn.preparing;
  if (ticket.isReady) return KdsColumn.ready;
  return KdsColumn.newTickets;
}

/// Actions a ticket card offers, by status. Start and Bump from NEW, Bump from
/// PREPARING, Recall and Served from READY.
List<KdsAction> actionsFor(KdsTicket ticket) {
  if (ticket.isNew) return const [KdsAction.start, KdsAction.bump];
  if (ticket.isPreparing) return const [KdsAction.bump];
  if (ticket.isReady) return const [KdsAction.recall, KdsAction.served];
  return const [];
}

enum KdsAction { start, bump, recall, served }

/// The READY ticket bumped most recently, for "Recall last". Null when none.
KdsTicket? lastBumped(Iterable<KdsTicket> tickets) {
  KdsTicket? best;
  for (final t in tickets) {
    if (!t.isReady || t.readyAt == null) continue;
    if (best == null || t.readyAt!.isAfter(best.readyAt!)) best = t;
  }
  return best;
}
