import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_billing/core/auth/permission_keys.dart';
import 'package:pos_billing/core/auth/permissions.dart';
import 'package:pos_billing/core/auth/session.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/core/ui/ui.dart';
import 'package:pos_billing/features/personas/data/admin_api.dart';

import '../data/outlets_repository.dart';

/// Settings > Outlets. Lists outlets; create and edit happen in a dialog.
class OutletsScreen extends ConsumerWidget {
  const OutletsScreen({super.key});

  Future<void> _openForm(BuildContext context, WidgetRef ref, Outlet? outlet) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _OutletFormDialog(outlet: outlet),
    );
    if (saved != true) return;
    ref.invalidate(outletsListProvider);
    if (context.mounted) {
      showAppToast(context, outlet == null ? 'Outlet created' : 'Outlet saved');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = can(ref, Perm.adminSettings, AccessLevel.edit);
    final outlets = ref.watch(outletsListProvider);
    final t = context.tokens;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Outlets',
              breadcrumb: 'Settings',
              actions: [
                if (canEdit)
                  AppButton(
                    label: 'New outlet',
                    icon: Icons.add,
                    variant: AppButtonVariant.primary,
                    onPressed: () => _openForm(context, ref, null),
                  ),
              ],
            ),
            SizedBox(height: t.spacing.md),
            Expanded(
              child: SingleChildScrollView(
                child: AppDataTable<Outlet>(
                  columns: [
                    AppColumn<Outlet>(
                      label: 'Name',
                      cell: (o) => Text(o.name, style: Theme.of(context).textTheme.titleMedium),
                    ),
                    AppColumn<Outlet>(label: 'Code', cell: (o) => Text(o.code)),
                    AppColumn<Outlet>(label: 'Address', cell: (o) => Text(o.address ?? '—')),
                    AppColumn<Outlet>(label: 'Timezone', cell: (o) => Text(o.timezone)),
                    AppColumn<Outlet>(
                      label: 'Status',
                      cell: (o) => StatusBadge(
                        label: o.isActive ? 'Active' : 'Inactive',
                        tone: o.isActive ? StatusTone.success : StatusTone.neutral,
                      ),
                    ),
                  ],
                  rows: outlets.valueOrNull ?? const <Outlet>[],
                  loading: outlets.isLoading && !outlets.hasValue,
                  error: outlets.hasError && !outlets.hasValue
                      ? AdminApiError.from(outlets.error!).friendly
                      : null,
                  onRetry: () => ref.invalidate(outletsListProvider),
                  onRowTap: canEdit ? (o) => _openForm(context, ref, o) : null,
                  empty: EmptyState(
                    title: 'No outlets yet',
                    message: 'Add your first outlet to assign staff and devices to it.',
                    actionLabel: canEdit ? 'New outlet' : null,
                    onAction: canEdit ? () => _openForm(context, ref, null) : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutletFormDialog extends ConsumerStatefulWidget {
  const _OutletFormDialog({this.outlet});

  final Outlet? outlet;

  @override
  ConsumerState<_OutletFormDialog> createState() => _OutletFormDialogState();
}

class _OutletFormDialogState extends ConsumerState<_OutletFormDialog> {
  late final _name = TextEditingController(text: widget.outlet?.name ?? '');
  late final _code = TextEditingController(text: widget.outlet?.code ?? '');
  late final _address = TextEditingController(text: widget.outlet?.address ?? '');
  late final _timezone = TextEditingController(text: widget.outlet?.timezone ?? 'Asia/Kolkata');
  late bool _active = widget.outlet?.isActive ?? true;
  String? _nameError;
  String? _codeError;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _address.dispose();
    _timezone.dispose();
    super.dispose();
  }

  bool _validate() {
    final nameOk = _name.text.trim().isNotEmpty;
    final code = _code.text.trim();
    final codeOk = RegExp(r'^[A-Za-z0-9-]{2,10}$').hasMatch(code);
    setState(() {
      _nameError = nameOk ? null : 'Enter a name';
      _codeError = codeOk ? null : '2 to 10 letters, digits or dashes';
    });
    return nameOk && codeOk;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final address = _address.text.trim();
    final repo = ref.read(outletsRepositoryProvider);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'code': _code.text.trim().toUpperCase(),
      'address': address.isEmpty ? null : address,
      'timezone': _timezone.text.trim().isEmpty ? 'Asia/Kolkata' : _timezone.text.trim(),
    };
    try {
      if (widget.outlet == null) {
        await repo.create(body);
      } else {
        await repo.update(widget.outlet!.id, {...body, 'isActive': _active});
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = AdminApiError.from(e).friendly;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = SizedBox(height: t.spacing.md);
    final isNew = widget.outlet == null;
    return AlertDialog(
      title: Text(isNew ? 'New outlet' : 'Edit ${widget.outlet!.name}'),
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
              AppTextField(label: 'Name', controller: _name, errorText: _nameError),
              gap,
              AppTextField(
                label: 'Code',
                controller: _code,
                errorText: _codeError,
                helperText: 'Short code shown on bills, for example MAIN',
              ),
              gap,
              AppTextField(label: 'Address', controller: _address),
              gap,
              AppTextField(label: 'Timezone', controller: _timezone),
              if (!isNew) ...[
                gap,
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text('Inactive outlets stop taking orders.'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: _saving ? 'Saving…' : 'Save',
          variant: AppButtonVariant.primary,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
