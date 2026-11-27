import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../data/guest_models.dart';

/// Quick reasons; the waiter can also type their own.
const rejectReasonPresets = ['Item not available', 'Kitchen is closing', 'Please order at the bar'];

/// Asks why a round is rejected. Resolves to the trimmed reason, or null when
/// cancelled. A reason is required: the guest sees it.
Future<String?> showRejectReasonDialog(BuildContext context, {required GuestRequest request}) =>
    showDialog<String>(
      context: context,
      builder: (_) => RejectReasonDialog(request: request),
    );

class RejectReasonDialog extends StatefulWidget {
  const RejectReasonDialog({super.key, required this.request});

  final GuestRequest request;

  @override
  State<RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<RejectReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _reason.text.trim();
    if (value.isEmpty) {
      setState(() => _error = '${widget.request.guestName} sees this reason. Enter one to reject.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = widget.request;
    return AlertDialog(
      backgroundColor: t.color.background.raised,
      surfaceTintColor: Colors.transparent,
      title: Text('Reject ${r.tableName} · ${r.guestName}?'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: t.spacing.sm,
              runSpacing: t.spacing.xs,
              children: [
                for (final p in rejectReasonPresets)
                  ActionChip(
                    label: Text(p),
                    onPressed: () => setState(() {
                      _reason.text = p;
                      _error = null;
                    }),
                  ),
              ],
            ),
            SizedBox(height: t.spacing.sm),
            AppTextField(
              label: 'Reason the guest sees',
              controller: _reason,
              errorText: _error,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        AppButton(label: 'Cancel', variant: AppButtonVariant.ghost, onPressed: () => Navigator.of(context).pop()),
        AppButton(label: 'Reject round', variant: AppButtonVariant.danger, onPressed: _submit),
      ],
    );
  }
}
