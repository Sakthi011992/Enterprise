import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_billing/core/auth/permission_keys.dart';
import 'package:pos_billing/core/auth/permissions.dart';
import 'package:pos_billing/core/auth/session.dart';
import 'package:pos_billing/core/theme/app_theme.dart';
import 'package:pos_billing/core/ui/ui.dart';
import 'package:pos_billing/features/outlets/data/outlets_repository.dart';
import 'package:pos_billing/features/personas/data/admin_api.dart';

import '../data/devices_repository.dart';
import 'register_device_dialog.dart';

/// Settings > Devices. Pick an outlet, then see and register its tablets, KDS, printers.
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  String? _outletId;
  String? _error;

  Future<void> _deactivate(String outletId, Device device) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Deactivate ${device.name}?',
      message: 'This device stops working until you register it again.',
      confirmLabel: 'Deactivate',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _error = null);
    try {
      await ref.read(devicesRepositoryProvider).deactivate(device.id);
      ref.invalidate(devicesListProvider(outletId));
      if (mounted) showAppToast(context, 'Device deactivated');
    } catch (e) {
      if (mounted) setState(() => _error = AdminApiError.from(e).friendly);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = can(ref, Perm.adminSettings, AccessLevel.edit);
    final outlets = ref.watch(outletsListProvider);
    final t = context.tokens;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(title: 'Devices', breadcrumb: 'Settings'),
            if (_error != null) ...[
              SizedBox(height: t.spacing.md),
              InlineAlert(message: _error!),
            ],
            SizedBox(height: t.spacing.md),
            Expanded(
              child: outlets.when(
                skipLoadingOnReload: true,
                loading: () => DelayedSkeleton(child: SkeletonList()),
                error: (e, _) => ErrorState(
                  message: AdminApiError.from(e).friendly,
                  onRetry: () => ref.invalidate(outletsListProvider),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return EmptyState(
                      title: 'No outlets yet',
                      message: 'Create an outlet before you register devices.',
                      icon: Icons.storefront_outlined,
                    );
                  }
                  final selectedId =
                      list.any((o) => o.id == _outletId) ? _outletId! : list.first.id;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: AppSelect<String>(
                              label: 'Outlet',
                              value: selectedId,
                              items: [for (final o in list) AppSelectItem(o.id, o.name)],
                              onChanged: (v) {
                                if (v != null) setState(() => _outletId = v);
                              },
                            ),
                          ),
                          if (canEdit) ...[
                            SizedBox(width: t.spacing.md),
                            AppButton(
                              label: 'Register device',
                              icon: Icons.add,
                              variant: AppButtonVariant.primary,
                              onPressed: () => showRegisterDeviceDialog(
                                context,
                                outlets: list,
                                initialOutletId: selectedId,
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: t.spacing.md),
                      Expanded(
                        child: _DeviceTable(
                          outletId: selectedId,
                          canEdit: canEdit,
                          onDeactivate: (device) => _deactivate(selectedId, device),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTable extends ConsumerWidget {
  const _DeviceTable({required this.outletId, required this.canEdit, required this.onDeactivate});

  final String outletId;
  final bool canEdit;
  final void Function(Device device) onDeactivate;

  static String _lastSeen(DateTime? at) =>
      at == null ? 'Never' : DateFormat('d MMM y, h:mm a').format(at.toLocal());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesListProvider(outletId));
    return SingleChildScrollView(
      child: AppDataTable<Device>(
        columns: [
          AppColumn<Device>(
            label: 'Name',
            cell: (d) => Text(d.name, style: Theme.of(context).textTheme.titleMedium),
          ),
          AppColumn<Device>(label: 'Type', cell: (d) => Text(deviceTypeLabel(d.type))),
          AppColumn<Device>(label: 'Last seen', cell: (d) => Text(_lastSeen(d.lastSeenAt))),
          AppColumn<Device>(
            label: 'Status',
            cell: (d) => StatusBadge(
              label: d.isActive ? 'Active' : 'Deactivated',
              tone: d.isActive ? StatusTone.success : StatusTone.neutral,
            ),
          ),
          if (canEdit)
            AppColumn<Device>(
              label: 'Actions',
              cell: (d) => d.isActive
                  ? AppIconButton(
                      icon: Icons.block,
                      tooltip: 'Deactivate ${d.name}',
                      onPressed: () => onDeactivate(d),
                    )
                  : Text('—', style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
        rows: devices.valueOrNull ?? const <Device>[],
        loading: devices.isLoading && !devices.hasValue,
        error: devices.hasError && !devices.hasValue
            ? AdminApiError.from(devices.error!).friendly
            : null,
        onRetry: () => ref.invalidate(devicesListProvider(outletId)),
        empty: EmptyState(
          title: 'No devices yet',
          message: 'Register a POS tablet, KDS, TV or printer for this outlet.',
          icon: Icons.devices_other_outlined,
        ),
      ),
    );
  }
}
