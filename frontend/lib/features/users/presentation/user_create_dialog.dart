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

/// New user: account details plus one outlet and persona.
/// Resolves to the new user's id, or null when cancelled.
Future<String?> showCreateUserDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _CreateUserDialog(),
  );
}

class _CreateUserDialog extends ConsumerStatefulWidget {
  const _CreateUserDialog();

  @override
  ConsumerState<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<_CreateUserDialog> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  String? _outletId;
  String? _personaId;
  String? _usernameError;
  String? _emailError;
  String? _passwordError;
  String? _error;
  bool _saving = false;

  /// Set once the account exists. A later failure must not create it again.
  String? _createdId;

  @override
  void dispose() {
    for (final c in [_username, _displayName, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The outlet shown in the select: the chosen one, else the first available.
  String? _effectiveOutlet(List<Outlet> outlets) {
    if (_outletId != null && outlets.any((o) => o.id == _outletId)) return _outletId;
    return outlets.isEmpty ? null : outlets.first.id;
  }

  /// The persona shown in the select: the chosen one, else Cashier, else the first.
  String? _effectivePersona(List<Persona> personas) {
    if (_personaId != null && personas.any((p) => p.id == _personaId)) return _personaId;
    for (final p in personas) {
      if (p.key == 'cashier') return p.id;
    }
    return personas.isEmpty ? null : personas.first.id;
  }

  bool _validate() {
    final username = _username.text.trim();
    final email = _email.text.trim();
    setState(() {
      _usernameError = username.length >= 3 ? null : 'Use at least 3 characters';
      _emailError = email.contains('@') ? null : 'Enter an email address';
      _passwordError = _password.text.length >= 6 ? null : 'Use at least 6 characters';
    });
    return _usernameError == null && _emailError == null && _passwordError == null;
  }

  Future<void> _save(List<Outlet> outlets, List<Persona> personas) async {
    final createdId = _createdId;
    if (createdId != null) {
      Navigator.of(context).pop(createdId);
      return;
    }
    if (!_validate()) return;
    final outletId = _effectiveOutlet(outlets);
    final personaId = _effectivePersona(personas);
    if (outletId == null || personaId == null) {
      setState(() => _error = 'Choose an outlet and a persona.');
      return;
    }
    final persona = personas.firstWhere((p) => p.id == personaId);
    final repo = ref.read(usersRepositoryProvider);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await repo.create({
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'password': _password.text,
        // The legacy role still has to be sent. It also picks the persona when none is given.
        'roleName': persona.key == 'admin' ? 'ADMIN' : 'USER',
        if (_displayName.text.trim().isNotEmpty) 'displayName': _displayName.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      });
      _createdId = id;
      await repo.setOutlets(id, [
        OutletAssignmentInput(outletId: outletId, personaId: personaId, isDefault: true),
      ]);
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      final message = AdminApiError.from(e).friendly;
      setState(() {
        _saving = false;
        _error = _createdId == null
            ? message
            : 'The account was created, but its outlet access was not saved. $message '
                'Press Done, then assign an outlet from the user panel.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = SizedBox(height: t.spacing.md);
    final outlets = ref.watch(outletsListProvider).valueOrNull ?? const <Outlet>[];
    final personas = ref.watch(personaListProvider).valueOrNull ?? const <Persona>[];
    final created = _createdId != null;

    return AlertDialog(
      title: Text(created ? 'User created' : 'New user'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                InlineAlert(message: _error!),
                gap,
              ],
              AppTextField(
                label: 'Username',
                controller: _username,
                errorText: _usernameError,
                autofocus: true,
              ),
              gap,
              AppTextField(
                label: 'Display name',
                controller: _displayName,
                helperText: 'Shown in the app. Optional.',
              ),
              gap,
              AppTextField(
                label: 'Email',
                controller: _email,
                errorText: _emailError,
                keyboardType: TextInputType.emailAddress,
              ),
              gap,
              AppTextField(
                label: 'Phone',
                controller: _phone,
                keyboardType: TextInputType.phone,
              ),
              gap,
              AppTextField(
                label: 'Password',
                controller: _password,
                obscure: true,
                errorText: _passwordError,
                helperText: 'At least 6 characters',
              ),
              gap,
              AppSelect<String>(
                label: 'Outlet',
                value: _effectiveOutlet(outlets),
                items: [for (final o in outlets) AppSelectItem(o.id, o.name)],
                onChanged: (v) => setState(() => _outletId = v),
              ),
              gap,
              AppSelect<String>(
                label: 'Persona at this outlet',
                value: _effectivePersona(personas),
                items: [for (final p in personas) AppSelectItem(p.id, p.name)],
                onChanged: (v) => setState(() => _personaId = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: (_saving || created) ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: created ? 'Done' : (_saving ? 'Creating…' : 'Create user'),
          variant: AppButtonVariant.primary,
          loading: _saving,
          onPressed: _saving ? null : () => _save(outlets, personas),
        ),
      ],
    );
  }
}
