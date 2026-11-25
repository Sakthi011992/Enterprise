import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_billing/core/auth/permission_keys.dart';
import 'package:pos_billing/core/auth/permissions.dart';
import 'package:pos_billing/core/auth/session.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/core/ui/ui.dart';
import 'package:pos_billing/features/personas/data/admin_api.dart';

import '../data/users_repository.dart';
import 'user_create_dialog.dart';
import 'user_edit_panel.dart';

/// Users, with each user's outlets and personas. Needs admin.users VIEW; editing needs EDIT.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String _query = '';
  String? _selectedId;

  List<AppUser> _filter(List<AppUser> users) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return users;
    return users.where((u) {
      return u.label.toLowerCase().contains(q) ||
          u.username.toLowerCase().contains(q) ||
          (u.email ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _createUser() async {
    final id = await showCreateUserDialog(context);
    if (id == null || !mounted) return;
    ref.invalidate(usersListProvider);
    setState(() => _selectedId = id);
    showAppToast(context, 'User created');
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = can(ref, Perm.adminUsers, AccessLevel.edit);
    final users = ref.watch(usersListProvider);
    final t = context.tokens;
    final all = users.valueOrNull ?? const <AppUser>[];
    final visible = _filter(all);

    AppUser? selected;
    for (final u in all) {
      if (u.id == _selectedId) selected = u;
    }

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Users',
              breadcrumb: 'People & money',
              actions: [
                if (canEdit)
                  AppButton(
                    label: 'New user',
                    icon: Icons.person_add_alt,
                    variant: AppButtonVariant.primary,
                    onPressed: _createUser,
                  ),
              ],
            ),
            SizedBox(height: t.spacing.md),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: AppDataTable<AppUser>(
                        columns: [
                          AppColumn<AppUser>(
                            label: 'Name',
                            cell: (u) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(u.label, style: Theme.of(context).textTheme.titleMedium),
                                Text(
                                  u.email ?? 'No email',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          AppColumn<AppUser>(label: 'Username', cell: (u) => Text(u.username)),
                          AppColumn<AppUser>(
                            label: 'Outlets and personas',
                            width: 280,
                            cell: (u) => _OutletChips(user: u),
                          ),
                          AppColumn<AppUser>(
                            label: 'PIN',
                            cell: (u) => StatusBadge(
                              label: u.hasPin ? 'PIN set' : 'No PIN',
                              tone: u.hasPin ? StatusTone.success : StatusTone.neutral,
                            ),
                          ),
                          AppColumn<AppUser>(
                            label: 'Status',
                            cell: (u) => StatusBadge(
                              label: u.isActive ? 'Active' : 'Inactive',
                              tone: u.isActive ? StatusTone.success : StatusTone.neutral,
                            ),
                          ),
                        ],
                        rows: visible,
                        searchHint: 'Search name, username or email',
                        onSearch: (v) => setState(() => _query = v),
                        selected: selected == null ? null : {selected},
                        loading: users.isLoading && !users.hasValue,
                        error: users.hasError && !users.hasValue
                            ? AdminApiError.from(users.error!).friendly
                            : null,
                        onRetry: () => ref.invalidate(usersListProvider),
                        onRowTap: (u) => setState(() => _selectedId = u.id),
                        empty: all.isEmpty
                            ? EmptyState(
                                title: 'No users yet',
                                message: 'Add the people who sign in to this venue.',
                                icon: Icons.people_outline,
                                actionLabel: canEdit ? 'New user' : null,
                                onAction: canEdit ? _createUser : null,
                              )
                            : const EmptyState(
                                title: 'No matches',
                                message: 'Try another name, username or email.',
                                icon: Icons.search_off,
                              ),
                      ),
                    ),
                  ),
                  if (selected != null) ...[
                    SizedBox(width: t.spacing.md),
                    SizedBox(
                      width: 380,
                      child: SingleChildScrollView(
                        child: UserEditPanel(
                          key: ValueKey(selected.id),
                          user: selected,
                          readOnly: !canEdit,
                          onClose: () => setState(() => _selectedId = null),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One chip per outlet: "Outlet: Persona". Flags a user with no outlet, who cannot sign in.
class _OutletChips extends StatelessWidget {
  const _OutletChips({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (user.outlets.isEmpty) {
      return const StatusBadge(label: 'No outlet', tone: StatusTone.warning);
    }
    return Wrap(
      spacing: t.spacing.xs,
      runSpacing: t.spacing.xs,
      children: [
        for (final o in user.outlets)
          StatusBadge(
            label: '${o.outletName}: ${o.personaName}',
            tone: o.isDefault ? StatusTone.info : StatusTone.neutral,
          ),
      ],
    );
  }
}
