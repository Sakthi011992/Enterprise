import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/ui/ui.dart';
import '../../floor/data/floor_repository.dart';
import '../data/guest_requests_providers.dart';
import '../data/guest_requests_repository.dart';

/// Floor plan table card additions: "QR · N new round(s)", "Bill asked" and,
/// for a seated table in Table PIN mode, the PIN chip.
class TableGuestBadges extends ConsumerWidget {
  const TableGuestBadges({super.key, required this.tableId, required this.status});

  final String tableId;
  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(guestLiveProvider);
    final t = context.tokens;
    final ext = context.ext;
    final info = ref.watch(tableGuestInfoProvider(tableId));
    final seated = status == TableStatus.occupied || status == TableStatus.billPrinted;
    final pin = seated ? ref.watch(guestPinProvider(tableId)).valueOrNull : null;

    final chips = <Widget>[
      if (info.newRounds > 0)
        _chip(context, 'QR · ${info.newRounds} new round${info.newRounds == 1 ? '' : 's'}',
            ext.accentSubtle, ext.onAccentSubtle),
      if (info.billAsked) _chip(context, 'Bill asked', ext.warningSubtle, ext.onWarningSubtle),
      if (pin != null)
        Container(
          key: const ValueKey('guest-pin'),
          padding: EdgeInsets.symmetric(horizontal: t.spacing.xs + 2, vertical: 1),
          decoration: BoxDecoration(
            color: t.color.background.raised,
            borderRadius: BorderRadius.circular(t.radius.sm),
            border: Border.all(color: t.color.border.strong, width: t.borderWidth.hairline),
          ),
          child: Text(
            pin,
            semanticsLabel: 'Guest PIN $pin',
            style: TextStyle(
              fontFamily: t.typography.monoFamily,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              fontSize: 12,
              color: t.color.content.primary,
            ),
          ),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: t.spacing.xs, runSpacing: 2, children: chips);
  }

  Widget _chip(BuildContext context, String label, Color bg, Color fg) {
    final t = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.spacing.xs + 2, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(t.radius.pill)),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

/// Floor setup: Print QR sheet for the area, and Rotate QR per table.
class FloorQrActions extends ConsumerStatefulWidget {
  const FloorQrActions({super.key, required this.area, required this.tables});

  final FloorArea area;
  final List<FloorTable> tables;

  @override
  ConsumerState<FloorQrActions> createState() => _FloorQrActionsState();
}

class _FloorQrActionsState extends ConsumerState<FloorQrActions> {
  String? _busy;

  Future<void> _rotate(FloorTable table) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Rotate QR for ${table.name}?',
      message: 'The printed QR code stops working and any open guest session on '
          '${table.name} is closed. Print a new QR card for the table.',
      confirmLabel: 'Rotate QR',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _busy = table.id);
    try {
      await ref.read(guestRequestsRepositoryProvider).rotateQr(table.id);
      if (mounted) showAppToast(context, 'New QR code for ${table.name}. Print it from the QR sheet.');
    } catch (e) {
      if (mounted) showAppToast(context, ApiError.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _print() async {
    setState(() => _busy = 'sheet');
    try {
      final bytes = await ref.read(guestRequestsRepositoryProvider).qrSheet(areaId: widget.area.id);
      final name = 'qr-sheet-${widget.area.name.toLowerCase().replaceAll(RegExp(r'\s+'), '-')}.pdf';
      await FilePicker.platform.saveFile(
        dialogTitle: 'Save QR sheet',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
    } catch (e) {
      if (mounted) showAppToast(context, ApiError.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return AppCard(
      title: 'Table QR codes · ${widget.area.name}',
      actions: [
        AppButton(
          label: 'Print QR sheet',
          icon: Icons.print_outlined,
          size: AppControlSize.sm,
          loading: _busy == 'sheet',
          onPressed: _busy == null ? _print : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Rotate a table\'s QR if its card is lost or copied. Routing and verification are set '
              'in Feature configuration › Guest ordering.', style: text.bodySmall),
          SizedBox(height: t.spacing.sm),
          if (widget.tables.isEmpty)
            Text('No tables in this area yet.', style: text.bodySmall)
          else
            Wrap(
              spacing: t.spacing.sm,
              runSpacing: t.spacing.sm,
              children: [
                for (final table in widget.tables)
                  AppButton(
                    key: ValueKey('rotate-${table.id}'),
                    label: 'Rotate QR · ${table.name}',
                    icon: Icons.autorenew,
                    size: AppControlSize.sm,
                    variant: AppButtonVariant.ghost,
                    loading: _busy == table.id,
                    onPressed: _busy == null ? () => _rotate(table) : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
