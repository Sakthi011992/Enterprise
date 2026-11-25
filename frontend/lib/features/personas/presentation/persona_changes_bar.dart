import 'package:flutter/material.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/core/ui/ui.dart';

/// Unsaved-changes bar under the matrix. Hidden entirely in read-only mode.
class PersonaChangesBar extends StatelessWidget {
  const PersonaChangesBar({
    super.key,
    required this.changeCount,
    required this.affectedUsers,
    required this.readOnly,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final int changeCount;
  final int affectedUsers;
  final bool readOnly;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    if (readOnly || changeCount == 0) return const SizedBox.shrink();
    final t = context.tokens;
    final changes = changeCount == 1 ? 'permission' : 'permissions';
    final users = affectedUsers == 1 ? 'user' : 'users';
    return Container(
      margin: EdgeInsets.only(top: t.spacing.md),
      padding: EdgeInsets.all(t.spacing.md),
      decoration: BoxDecoration(
        color: t.color.background.raised,
        borderRadius: BorderRadius.circular(t.radius.md),
        border: Border.all(color: t.color.border.accent, width: t.borderWidth.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'You changed $changeCount $changes. They apply to all $affectedUsers $users the next time they sign in.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          SizedBox(width: t.spacing.md),
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.ghost,
            onPressed: saving ? null : onCancel,
          ),
          SizedBox(width: t.spacing.sm),
          AppButton(
            label: saving ? 'Saving…' : 'Save',
            variant: AppButtonVariant.primary,
            loading: saving,
            onPressed: saving ? null : onSave,
          ),
        ],
      ),
    );
  }
}
