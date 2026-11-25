import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/api_error.dart';
import '../../../../core/auth/permission_keys.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session.dart';
import '../../../../core/ui/ui.dart';
import '../../../pos/presentation/pos_format.dart';
import '../../data/inventory_models.dart';
import '../../data/inventory_repository.dart';
import '../inventory_messages.dart';

const _kinds = <(String, String)>[
  ('STORE', 'Store'),
  ('BAR', 'Bar'),
  ('KITCHEN', 'Kitchen'),
  ('CELLAR', 'Cellar'),
];

/// Inventory > Locations. Stock is kept per location; a station sells from the
/// location that lists it.
class LocationsTab extends ConsumerWidget {
  const LocationsTab({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, LocationView? existing) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _LocationDialog(existing: existing),
    );
    if (saved == true) {
      ref.invalidate(inventoryLocationsProvider);
      ref.invalidate(inventorySummaryProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.menuEdit, AccessLevel.edit) ||
        can(ref, Perm.stockPurchaseOrders, AccessLevel.edit);
    final async = ref.watch(inventoryLocationsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Where stock is kept. A station sells from the location that lists it.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (canEdit)
              AppButton(
                label: 'New location',
                icon: Icons.add,
                variant: AppButtonVariant.primary,
                onPressed: () => _edit(context, ref, null),
              ),
          ],
        ),
        SizedBox(height: t.spacing.md),
        Expanded(
          child: async.when(
            loading: () => DelayedSkeleton(child: SkeletonList()),
            error: (e, _) => ErrorState(
              message: ApiError.from(e).message,
              onRetry: () => ref.invalidate(inventoryLocationsProvider),
            ),
            data: (locations) {
              if (locations.isEmpty) {
                return const EmptyState(
                  title: 'No locations yet',
                  message: 'Add a store, bar, kitchen or cellar to start tracking stock.',
                  icon: Icons.warehouse_outlined,
                );
              }
              return SingleChildScrollView(
                child: Wrap(
                  spacing: t.spacing.md,
                  runSpacing: t.spacing.md,
                  children: [
                    for (final l in locations)
                      SizedBox(
                        width: 320,
                        child: AppCard(
                          child: InkWell(
                            onTap: canEdit ? () => _edit(context, ref, l) : null,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(l.name, style: Theme.of(context).textTheme.titleMedium),
                                    ),
                                    StatusBadge(label: _kindLabel(l.kind)),
                                  ],
                                ),
                                SizedBox(height: t.spacing.xs),
                                Text(
                                  l.stations.isEmpty
                                      ? 'No stations sell from here'
                                      : 'Sells for: ${l.stations.join(', ')}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (l.isDefaultSales)
                                  Text(
                                    'Fallback for stations not listed anywhere',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                SizedBox(height: t.spacing.sm),
                                Text('${l.itemCount} items · ${formatWire(l.value)}'),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _kindLabel(String kind) {
    for (final (wire, label) in _kinds) {
      if (wire == kind) return label;
    }
    return kind;
  }
}

class _LocationDialog extends ConsumerStatefulWidget {
  const _LocationDialog({this.existing});

  final LocationView? existing;

  @override
  ConsumerState<_LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends ConsumerState<_LocationDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _stations = TextEditingController(text: widget.existing?.stations.join(', ') ?? '');
  late String _kind = widget.existing?.kind ?? 'STORE';
  late bool _isDefault = widget.existing?.isDefaultSales ?? false;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _stations.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final stations = [
      for (final s in _stations.text.split(',')) if (s.trim().isNotEmpty) s.trim().toUpperCase(),
    ];
    final body = LocationView(
      id: widget.existing?.id ?? '',
      name: name,
      kind: _kind,
      stations: stations,
      isDefaultSales: _isDefault,
    );
    final repo = ref.read(inventoryRepositoryProvider);
    try {
      if (widget.existing == null) {
        await repo.createLocation(body);
      } else {
        await repo.updateLocation(widget.existing!.id, body);
      }
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
      title: Text(widget.existing == null ? 'New location' : 'Edit ${widget.existing!.name}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              InlineAlert(message: _error!),
              SizedBox(height: t.spacing.sm),
            ],
            AppTextField(label: 'Name', controller: _name, hint: 'Rooftop bar'),
            SizedBox(height: t.spacing.md),
            AppSelect<String>(
              label: 'Kind',
              value: _kind,
              items: [for (final (wire, label) in _kinds) AppSelectItem(wire, label)],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            SizedBox(height: t.spacing.md),
            AppTextField(
              label: 'Stations that sell from here',
              controller: _stations,
              hint: 'BAR, KITCHEN',
              helperText: 'Comma separated. Matches the station on each category.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Default for unlisted stations'),
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v),
            ),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Save',
          variant: AppButtonVariant.primary,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
