import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/core/ui/ui.dart';
import 'package:pos_billing/features/outlets/data/outlets_repository.dart';
import 'package:pos_billing/features/personas/data/admin_api.dart';
import 'package:pos_billing/features/personas/data/persona_models.dart';
import 'package:pos_billing/features/personas/data/personas_repository.dart';

import '../data/users_repository.dart';
import 'user_legacy_features.dart';
import 'user_secret_dialog.dart';

/// Side panel for one user: details, outlet access, PIN, password and legacy grants.
/// Create it with `ValueKey(user.id)` so the form resets when the selection changes.
class UserEditPanel extends ConsumerStatefulWidget {
  const UserEditPanel({
    super.key,
    required this.user,
    required this.readOnly,
    required this.onClose,
  });

  final AppUser user;

  /// True when the viewer has admin.users VIEW only.
  final bool readOnly;
  final VoidCallback onClose;

  @override
  ConsumerState<UserEditPanel> createState() => _UserEditPanelState();
}

/// One editable row of outlet access.
class _OutletRowDraft {
  _OutletRowDraft({
    this.outletId,
    this.outletName,
    this.personaId,
    this.personaName,
    this.isDefault = false,
  });

  String? outletId;
  String? outletName;
  String? personaId;
  String? personaName;
  bool isDefault;
}

class _UserEditPanelState extends ConsumerState<UserEditPanel> {
  late final TextEditingController _displayName =
      TextEditingController(text: widget.user.displayName ?? '');
  late final TextEditingController _email = TextEditingController(text: widget.user.email ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.user.phone ?? '');
  late bool _active = widget.user.isActive;
  late final List<_OutletRowDraft> _rows = [
    for (final o in widget.user.outlets)
      _OutletRowDraft(
        outletId: o.outletId,
        outletName: o.outletName,
        personaId: o.personaId,
        personaName: o.personaName,
        isDefault: o.isDefault,
      ),
  ];
  String? _emailError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// Runs one write, shows a toast on success or the friendly error, then reloads the list.
  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(usersListProvider);
      if (mounted) showAppToast(context, success);
    } catch (e) {
      if (mounted) setState(() => _error = AdminApiError.from(e).friendly);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDetails() async {
    final email = _email.text.trim();
    if (email.isNotEmpty && !email.contains('@')) {
      setState(() => _emailError = 'Enter an email address');
      return;
    }
    setState(() => _emailError = null);
    final displayName = _displayName.text.trim();
    final phone = _phone.text.trim();
    final body = <String, dynamic>{
      'displayName': displayName.isEmpty ? null : displayName,
      'phone': phone.isEmpty ? null : phone,
      'isActive': _active,
      if (email.isNotEmpty) 'email': email,
    };
    await _run(() => ref.read(usersRepositoryProvider).update(widget.user.id, body), 'User saved');
  }

  Future<void> _saveOutlets() async {
    if (_rows.isEmpty) {
      setState(() => _error = 'Add at least one outlet. Without one the user cannot sign in.');
      return;
    }
    if (_rows.any((r) => r.outletId == null || r.personaId == null)) {
      setState(() => _error = 'Choose an outlet and a persona on every row, or remove the empty row.');
      return;
    }
    final outletIds = _rows.map((r) => r.outletId).toSet();
    if (outletIds.length != _rows.length) {
      setState(() => _error = 'Each outlet can appear only once.');
      return;
    }
    if (!_rows.any((r) => r.isDefault)) _rows.first.isDefault = true;
    final items = [
      for (final r in _rows)
        OutletAssignmentInput(outletId: r.outletId!, personaId: r.personaId!, isDefault: r.isDefault),
    ];
    await _run(
      () => ref.read(usersRepositoryProvider).setOutlets(widget.user.id, items),
      'Outlet access saved',
    );
  }

  Future<void> _setPin() async {
    final saved = await showSetPinDialog(
      context,
      onSubmit: (pin) => ref.read(usersRepositoryProvider).setPin(widget.user.id, pin),
    );
    if (!saved || !mounted) return;
    ref.invalidate(usersListProvider);
    showAppToast(context, 'PIN set for ${widget.user.label}');
  }

  Future<void> _resetPassword() async {
    final saved = await showResetPasswordDialog(
      context,
      onSubmit: (password) =>
          ref.read(usersRepositoryProvider).resetPassword(widget.user.id, password),
    );
    if (!saved || !mounted) return;
    showAppToast(context, 'Password reset for ${widget.user.username}');
  }

  void _addRow() => setState(() => _rows.add(_OutletRowDraft(isDefault: _rows.isEmpty)));

  void _removeRow(int index) => setState(() {
        final removed = _rows.removeAt(index);
        if (removed.isDefault && _rows.isNotEmpty) _rows.first.isDefault = true;
      });

  void _makeDefault(int index) => setState(() {
        for (final r in _rows) {
          r.isDefault = false;
        }
        _rows[index].isDefault = true;
      });

  void _setOutlet(int index, String? id, List<Outlet> outlets) => setState(() {
        final row = _rows[index];
        row.outletId = id;
        row.outletName = _outletName(outlets, id);
      });

  void _setPersona(int index, String? id, List<Persona> personas) => setState(() {
        final row = _rows[index];
        row.personaId = id;
        row.personaName = _personaName(personas, id);
      });

  static String? _outletName(List<Outlet> outlets, String? id) {
    for (final o in outlets) {
      if (o.id == id) return o.name;
    }
    return null;
  }

  static String? _personaName(List<Persona> personas, String? id) {
    for (final p in personas) {
      if (p.id == id) return p.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final gap = SizedBox(height: t.spacing.md);
    final outlets = ref.watch(outletsListProvider).valueOrNull ?? const <Outlet>[];
    final personas = ref.watch(personaListProvider).valueOrNull ?? const <Persona>[];
    final user = widget.user;

    return AppCard(
      title: user.label,
      actions: [
        AppIconButton(icon: Icons.close, tooltip: 'Close details', onPressed: widget.onClose),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('@${user.username}', style: textTheme.bodySmall),
          gap,
          if (_error != null) ...[
            InlineAlert(message: _error!),
            gap,
          ],
          if (widget.readOnly)
            ..._readOnlyDetails(context)
          else ...[
            AppTextField(label: 'Display name', controller: _displayName),
            gap,
            AppTextField(
              label: 'Email',
              controller: _email,
              errorText: _emailError,
              keyboardType: TextInputType.emailAddress,
            ),
            gap,
            AppTextField(label: 'Phone', controller: _phone, keyboardType: TextInputType.phone),
            gap,
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Inactive users cannot sign in.'),
              value: _active,
              onChanged: _busy ? null : (v) => setState(() => _active = v),
            ),
            gap,
            AppButton(
              label: _busy ? 'Saving…' : 'Save details',
              variant: AppButtonVariant.primary,
              loading: _busy,
              onPressed: _busy ? null : _saveDetails,
            ),
            gap,
            const Divider(),
            gap,
            Text('Outlet access', style: textTheme.titleSmall),
            SizedBox(height: t.spacing.xs),
            Text(
              'Each outlet needs a persona. Exactly one outlet is the default.',
              style: textTheme.bodySmall,
            ),
            SizedBox(height: t.spacing.sm),
            for (var i = 0; i < _rows.length; i++) ...[
              _OutletRowEditor(
                row: _rows[i],
                outlets: outlets,
                personas: personas,
                usedOutletIds: {
                  for (var j = 0; j < _rows.length; j++)
                    if (j != i && _rows[j].outletId != null) _rows[j].outletId!,
                },
                onOutlet: (id) => _setOutlet(i, id, outlets),
                onPersona: (id) => _setPersona(i, id, personas),
                onDefault: () => _makeDefault(i),
                onRemove: () => _removeRow(i),
              ),
              SizedBox(height: t.spacing.md),
            ],
            Row(
              children: [
                AppButton(
                  label: 'Add outlet',
                  icon: Icons.add,
                  onPressed: _busy ? null : _addRow,
                ),
                const Spacer(),
                AppButton(
                  label: 'Save outlets',
                  variant: AppButtonVariant.primary,
                  onPressed: _busy ? null : _saveOutlets,
                ),
              ],
            ),
            gap,
            const Divider(),
            gap,
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Set PIN',
                    icon: Icons.dialpad,
                    onPressed: _busy ? null : _setPin,
                  ),
                ),
                SizedBox(width: t.spacing.sm),
                Expanded(
                  child: AppButton(
                    label: 'Reset password',
                    icon: Icons.lock_reset,
                    onPressed: _busy ? null : _resetPassword,
                  ),
                ),
              ],
            ),
            SizedBox(height: t.spacing.xs),
            Text(
              user.hasPin
                  ? 'A PIN is set. Staff use it on a shared tablet.'
                  : 'No PIN yet. Set one for shared-tablet sign-in.',
              style: textTheme.bodySmall,
            ),
          ],
          gap,
          const Divider(),
          gap,
          UserLegacyFeatures(userId: user.id, readOnly: widget.readOnly),
        ],
      ),
    );
  }

  List<Widget> _readOnlyDetails(BuildContext context) {
    final t = context.tokens;
    final user = widget.user;
    return [
      _ReadOnlyLine(label: 'Display name', value: user.displayName ?? '—'),
      _ReadOnlyLine(label: 'Email', value: user.email ?? '—'),
      _ReadOnlyLine(label: 'Phone', value: user.phone ?? '—'),
      _ReadOnlyLine(label: 'Status', value: user.isActive ? 'Active' : 'Inactive'),
      _ReadOnlyLine(label: 'PIN', value: user.hasPin ? 'Set' : 'Not set'),
      SizedBox(height: t.spacing.sm),
      Text('Outlet access', style: Theme.of(context).textTheme.titleSmall),
      SizedBox(height: t.spacing.xs),
      if (user.outlets.isEmpty)
        Text('No outlets. This user cannot sign in.', style: Theme.of(context).textTheme.bodySmall),
      for (final o in user.outlets)
        _ReadOnlyLine(
          label: o.isDefault ? '${o.outletName} (default)' : o.outletName,
          value: o.personaName,
        ),
    ];
  }
}

/// One outlet + persona row with a default toggle and a remove button.
class _OutletRowEditor extends StatelessWidget {
  const _OutletRowEditor({
    required this.row,
    required this.outlets,
    required this.personas,
    required this.usedOutletIds,
    required this.onOutlet,
    required this.onPersona,
    required this.onDefault,
    required this.onRemove,
  });

  final _OutletRowDraft row;
  final List<Outlet> outlets;
  final List<Persona> personas;

  /// Outlets already picked by the other rows. They are hidden from this select.
  final Set<String> usedOutletIds;
  final ValueChanged<String?> onOutlet;
  final ValueChanged<String?> onPersona;
  final VoidCallback onDefault;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final outletId = row.outletId;
    final personaId = row.personaId;

    // The current value must always be an item, or the dropdown asserts.
    final outletItems = <AppSelectItem<String>>[
      for (final o in outlets)
        if (o.id == outletId || !usedOutletIds.contains(o.id)) AppSelectItem(o.id, o.name),
      if (outletId != null && !outlets.any((o) => o.id == outletId))
        AppSelectItem(outletId, row.outletName ?? outletId),
    ];
    final personaItems = <AppSelectItem<String>>[
      for (final p in personas) AppSelectItem(p.id, p.name),
      if (personaId != null && !personas.any((p) => p.id == personaId))
        AppSelectItem(personaId, row.personaName ?? personaId),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppSelect<String>(
                label: 'Outlet',
                value: outletId,
                items: outletItems,
                onChanged: onOutlet,
              ),
            ),
            SizedBox(width: t.spacing.sm),
            Expanded(
              child: AppSelect<String>(
                label: 'Persona',
                value: personaId,
                items: personaItems,
                onChanged: onPersona,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Semantics(
              label: 'Default outlet',
              checked: row.isDefault,
              inMutuallyExclusiveGroup: true,
              child: InkWell(
                onTap: row.isDefault ? null : onDefault,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: t.spacing.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        row.isDefault ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 18,
                        color: row.isDefault ? t.color.background.accent : t.color.content.muted,
                      ),
                      SizedBox(width: t.spacing.xs),
                      Text('Default outlet', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            AppIconButton(icon: Icons.close, tooltip: 'Remove this outlet', onPressed: onRemove),
          ],
        ),
      ],
    );
  }
}

class _ReadOnlyLine extends StatelessWidget {
  const _ReadOnlyLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.labelSmall),
          Text(value, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}
