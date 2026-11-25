import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/auth/permission_keys.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/ui/ui.dart';
import '../../../inventory/presentation/inventory_messages.dart';
import '../../data/procurement_models.dart';
import '../../data/procurement_repository.dart';

/// Procurement > Vendors. Create and edit; editing needs `stock.purchaseOrders` EDIT.
class VendorsTab extends ConsumerWidget {
  const VendorsTab({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, VendorView? existing) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _VendorDialog(existing: existing),
    );
    if (saved == true) ref.invalidate(procurementVendorsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.stockPurchaseOrders, AccessLevel.edit);
    final async = ref.watch(procurementVendorsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canEdit)
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'New vendor',
              icon: Icons.add,
              variant: AppButtonVariant.primary,
              onPressed: () => _edit(context, ref, null),
            ),
          ),
        SizedBox(height: t.spacing.sm),
        Expanded(
          child: AppDataTable<VendorView>(
            columns: [
              AppColumn<VendorView>(label: 'Vendor', cell: (r) => Text(r.name)),
              AppColumn<VendorView>(label: 'Contact', cell: (r) => Text(r.contactName ?? r.phone ?? '-')),
              AppColumn<VendorView>(label: 'GSTIN', cell: (r) => Text(r.gstin ?? '-')),
              AppColumn<VendorView>(label: 'Terms', cell: (r) => Text('${r.paymentTermsDays} days')),
              AppColumn<VendorView>(label: 'Open POs', numeric: true, cell: (r) => Text('${r.openPoCount}')),
              AppColumn<VendorView>(
                label: 'Status',
                cell: (r) => StatusBadge(
                  label: r.isActive ? 'Active' : 'Inactive',
                  tone: r.isActive ? StatusTone.success : StatusTone.neutral,
                ),
              ),
            ],
            rows: async.valueOrNull ?? const <VendorView>[],
            loading: async.isLoading && !async.hasValue,
            error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
            onRetry: () => ref.invalidate(procurementVendorsProvider),
            onRowTap: canEdit ? (r) => _edit(context, ref, r) : null,
            empty: const EmptyState(
              title: 'No vendors yet',
              message: 'Add the distributors and suppliers you order from.',
              icon: Icons.storefront_outlined,
            ),
          ),
        ),
      ],
    );
  }
}

class _VendorDialog extends ConsumerStatefulWidget {
  const _VendorDialog({this.existing});

  final VendorView? existing;

  @override
  ConsumerState<_VendorDialog> createState() => _VendorDialogState();
}

class _VendorDialogState extends ConsumerState<_VendorDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _contact = TextEditingController(text: widget.existing?.contactName ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _gstin = TextEditingController(text: widget.existing?.gstin ?? '');
  late final _address = TextEditingController(text: widget.existing?.address ?? '');
  late final _terms = TextEditingController(text: '${widget.existing?.paymentTermsDays ?? 30}');
  late bool _active = widget.existing?.isActive ?? true;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _contact, _phone, _email, _gstin, _address, _terms]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the vendor name');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = VendorView(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      contactName: _opt(_contact),
      phone: _opt(_phone),
      email: _opt(_email),
      gstin: _opt(_gstin),
      address: _opt(_address),
      paymentTermsDays: int.tryParse(_terms.text.trim()) ?? 30,
      isActive: _active,
    );
    try {
      await ref.read(procurementRepositoryProvider).saveVendor(body, id: widget.existing?.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = inventoryErrorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      title: Text(widget.existing == null ? 'New vendor' : widget.existing!.name),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                InlineAlert(message: _error!),
                SizedBox(height: t.spacing.sm),
              ],
              AppTextField(label: 'Name', controller: _name),
              SizedBox(height: t.spacing.sm),
              AppTextField(label: 'Contact person', controller: _contact),
              SizedBox(height: t.spacing.sm),
              AppTextField(label: 'Phone', controller: _phone, keyboardType: TextInputType.phone),
              SizedBox(height: t.spacing.sm),
              AppTextField(label: 'Email', controller: _email, keyboardType: TextInputType.emailAddress),
              SizedBox(height: t.spacing.sm),
              AppTextField(label: 'GSTIN', controller: _gstin),
              SizedBox(height: t.spacing.sm),
              AppTextField(label: 'Address', controller: _address),
              SizedBox(height: t.spacing.sm),
              AppTextField(label: 'Payment terms (days)', controller: _terms, keyboardType: TextInputType.number),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Save vendor',
          variant: AppButtonVariant.primary,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
