import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/features/app_feature.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode_toggle.dart';

final _usersProvider = FutureProvider<List<Map>>((ref) async {
  final res = await ref.watch(dioProvider).get('/users', queryParameters: {'limit': 100});
  return (res.data['data'] as List).cast<Map>();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(_usersProvider);
    final t = context.tokens;

    return Scaffold(
      appBar: AppBar(title: const Text('Users'), actions: const [ThemeModeToggle()]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createUser(context, ref),
        icon: const Icon(Icons.person_add),
        label: const Text('Create User'),
      ),
      body: users.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) => ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final u = items[i];
            final isActive = u['isActive'] == true;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: isActive
                    ? t.color.background.accent.withValues(alpha: 0.15)
                    : t.color.content.muted.withValues(alpha: 0.15),
                child: Text(
                  (u['username'] as String).characters.first.toUpperCase(),
                  style: TextStyle(
                    color: isActive ? t.color.background.accent : t.color.content.muted,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(u['username'] as String),
              subtitle: Text(
                '${u['email']}  ·  ${u['role']['name']}',
                style: TextStyle(color: t.color.content.secondary),
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  isActive ? Icons.check_circle : Icons.block,
                  size: 18,
                  color: isActive ? t.color.background.success : t.color.content.muted,
                ),
                const SizedBox(width: 4),
                _UserMenu(user: u, onChanged: () => ref.invalidate(_usersProvider)),
              ]),
            );
          },
        ),
      ),
    );
  }

  Future<void> _createUser(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _UserFormDialog(),
    );
    if (created == true) ref.invalidate(_usersProvider);
  }
}

// ---------------------------------------------------------------------------
// Per-user popup menu
// ---------------------------------------------------------------------------

class _UserMenu extends ConsumerWidget {
  const _UserMenu({required this.user, required this.onChanged});
  final Map user;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = user['isActive'] == true;
    return PopupMenuButton<_Action>(
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => _handle(context, ref, action),
      itemBuilder: (_) => [
        const PopupMenuItem(value: _Action.features,       child: _MenuItem(Icons.tune,           'Manage Features')),
        const PopupMenuItem(value: _Action.resetPassword,  child: _MenuItem(Icons.lock_reset,     'Reset Password')),
        PopupMenuItem(
          value: _Action.toggleActive,
          child: _MenuItem(
            isActive ? Icons.block : Icons.check_circle_outline,
            isActive ? 'Deactivate' : 'Activate',
          ),
        ),
      ],
    );
  }

  Future<void> _handle(BuildContext context, WidgetRef ref, _Action action) async {
    switch (action) {
      case _Action.features:
        await showDialog(
          context: context,
          builder: (_) => _FeatureDialog(userId: user['id'] as String, username: user['username'] as String),
        );

      case _Action.resetPassword:
        final done = await showDialog<bool>(
          context: context,
          builder: (_) => _ResetPasswordDialog(userId: user['id'] as String, username: user['username'] as String),
        );
        if (done == true && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Password reset for ${user['username']}')),
          );
        }

      case _Action.toggleActive:
        try {
          await ref.read(dioProvider).patch(
            '/users/${user['id']}',
            data: {'isActive': !(user['isActive'] as bool)},
          );
          onChanged();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
          }
        }
    }
  }
}

enum _Action { features, resetPassword, toggleActive }

class _MenuItem extends StatelessWidget {
  const _MenuItem(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(label),
      ]);
}

// ---------------------------------------------------------------------------
// Reset-password dialog
// ---------------------------------------------------------------------------

class _ResetPasswordDialog extends ConsumerStatefulWidget {
  const _ResetPasswordDialog({required this.userId, required this.username});
  final String userId;
  final String username;
  @override
  ConsumerState<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends ConsumerState<_ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).patch(
        '/users/${widget.userId}/reset-password',
        data: {'newPassword': _pw.text},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reset password — ${widget.username}'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _pw,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'New password',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              validator: (v) => v != _pw.text ? 'Passwords do not match' : null,
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Reset')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Create-user dialog
// ---------------------------------------------------------------------------

class _UserFormDialog extends ConsumerStatefulWidget {
  const _UserFormDialog();
  @override
  ConsumerState<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _role = 'USER';
  bool _obscure = true;
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).post('/users', data: {
        'username': _username.text.trim(),
        'email': _email.text.trim(),
        'password': _password.text,
        'roleName': _role,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: context.tokens.spacing.step(3));
    return AlertDialog(
      title: const Text('Create User'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (v) => (v == null || v.trim().length < 3) ? 'Min 3 characters' : null,
            ),
            gap,
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => (v == null || !v.contains('@')) ? 'Invalid email' : null,
            ),
            gap,
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
            ),
            gap,
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'USER', child: Text('Cashier (USER)')),
                DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
              ],
              onChanged: (v) => setState(() => _role = v!),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Create')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Feature-toggle dialog
// ---------------------------------------------------------------------------

class _FeatureDialog extends ConsumerStatefulWidget {
  const _FeatureDialog({required this.userId, required this.username});
  final String userId;
  final String username;
  @override
  ConsumerState<_FeatureDialog> createState() => _FeatureDialogState();
}

class _FeatureDialogState extends ConsumerState<_FeatureDialog> {
  bool _loading = true;
  bool _saving = false;
  Set<AppFeature> _granted = {};

  static const _labels = {
    AppFeature.dashboard:   ('Dashboard',            Icons.dashboard),
    AppFeature.products:    ('Products',             Icons.inventory_2),
    AppFeature.tax:         ('Tax Settings',         Icons.percent),
    AppFeature.users:       ('User Management',      Icons.people),
    AppFeature.orders:      ('Orders',               Icons.receipt_long),
    AppFeature.appearance:  ('Appearance / Themes',  Icons.palette),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(dioProvider).get('/users/${widget.userId}/features');
      final list = (res.data as List).cast<String>();
      setState(() {
        _granted = list.map(AppFeature.fromWire).whereType<AppFeature>().toSet();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).put(
        '/users/${widget.userId}/features',
        data: {'features': _granted.map((f) => f.wireValue).toList()},
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Features — ${widget.username}'),
      content: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          : SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: AppFeature.values.map((f) {
                  final info = _labels[f]!;
                  return CheckboxListTile(
                    secondary: Icon(info.$2),
                    title: Text(info.$1),
                    value: _granted.contains(f),
                    onChanged: (v) => setState(() {
                      if (v == true) { _granted.add(f); } else { _granted.remove(f); }
                    }),
                  );
                }).toList(),
              ),
            ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: (_loading || _saving) ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
