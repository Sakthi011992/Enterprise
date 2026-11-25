import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/ui/ui.dart';
import '../../data/pos_models.dart';
import '../../data/pos_repository.dart';
import '../pos_format.dart';
import '../pos_order_controller.dart';
import 'dialog_frame.dart';

/// Asks a manager for their PIN at this device. On success the server creates
/// and approves the request in one call (`POST /approvals/pin`). Resolves to
/// the approved [ApprovalView], or null when dismissed.
Future<ApprovalView?> showManagerPinDialog(
  BuildContext context, {
  required String type,
  String? orderId,
  required Map<String, dynamic> payload,
  required String reason,
  String title = 'Manager approval',
}) {
  return showDialog<ApprovalView>(
    context: context,
    builder: (_) => ManagerPinDialog(
      type: type,
      orderId: orderId,
      payload: payload,
      reason: reason,
      title: title,
    ),
  );
}

/// Maps a PIN error from `POST /approvals/pin` to the words staff see.
String managerPinErrorMessage(ApiError e) {
  switch (e.code) {
    case 'PIN_INVALID':
      final left = e.intDetail('attemptsLeft');
      return left == null
          ? 'Wrong PIN.'
          : 'Wrong PIN. $left ${left == 1 ? 'try' : 'tries'} left before a lock.';
    case 'PIN_LOCKED':
      final until = e.stringDetail('lockedUntil');
      final parsed = until == null ? null : DateTime.tryParse(until);
      return parsed == null
          ? 'Too many wrong PINs. Try again later.'
          : 'Too many wrong PINs. Try again after ${formatClock(parsed.toLocal())}.';
    case 'APPROVER_NOT_ALLOWED':
      return "That person can't approve this. Pick another manager.";
    default:
      return e.message;
  }
}

class ManagerPinDialog extends ConsumerStatefulWidget {
  const ManagerPinDialog({
    super.key,
    required this.type,
    this.orderId,
    required this.payload,
    required this.reason,
    required this.title,
  });

  final String type;
  final String? orderId;
  final Map<String, dynamic> payload;
  final String reason;
  final String title;

  @override
  ConsumerState<ManagerPinDialog> createState() => _ManagerPinDialogState();
}

class _ManagerPinDialogState extends ConsumerState<ManagerPinDialog> {
  String? _managerId;
  String? _error;
  bool _busy = false;

  Future<void> _submit(String pin) async {
    final managerId = _managerId;
    if (managerId == null) {
      setState(() => _error = 'Pick a manager first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final approval = await ref.read(posRepositoryProvider).approveWithPin(
            PinApprovalRequest(
              type: widget.type,
              orderId: widget.orderId,
              payload: widget.payload,
              reason: widget.reason,
              managerUserId: managerId,
              pin: pin,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(approval);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = managerPinErrorMessage(ApiError.from(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(managerStaffProvider);
    final t = context.tokens;
    return PosDialogFrame(
      title: widget.title,
      subtitle: widget.reason,
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: staff.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => InlineAlert(message: ApiError.from(e).message),
        data: (members) {
          if (members.isEmpty) {
            return const InlineAlert(message: 'No staff are set up at this outlet.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSelect<String>(
                label: 'Manager',
                value: _managerId,
                items: [
                  for (final m in members)
                    AppSelectItem(m.userId, '${m.displayName} · ${m.personaName}'),
                ],
                onChanged: (v) => setState(() {
                  _managerId = v;
                  _error = null;
                }),
              ),
              SizedBox(height: t.spacing.md),
              Text('Enter the manager PIN', style: TextStyle(color: t.color.content.secondary)),
              SizedBox(height: t.spacing.sm),
              Center(
                child: PinPad(
                  length: 4,
                  enabled: !_busy && _managerId != null,
                  errorText: _error,
                  onCompleted: _submit,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
