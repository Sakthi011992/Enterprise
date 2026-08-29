import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode_toggle.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _kioskDevicesProvider = FutureProvider<List<Map>>((ref) async {
  final res = await ref.watch(dioProvider).get('/admin/kiosk/configs');
  return (res.data as List).cast<Map>();
});

final _featuredItemsProvider = FutureProvider<List<Map>>((ref) async {
  final res = await ref.watch(dioProvider).get('/admin/kiosk/featured');
  return (res.data as List).cast<Map>();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class KioskAdminScreen extends ConsumerStatefulWidget {
  const KioskAdminScreen({super.key});
  @override
  ConsumerState<KioskAdminScreen> createState() => _KioskAdminScreenState();
}

class _KioskAdminScreenState extends ConsumerState<KioskAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kiosk Admin'),
        actions: const [ThemeModeToggle()],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.devices), text: 'Devices'),
            Tab(icon: Icon(Icons.star), text: 'Featured Items'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _DevicesTab(),
          _FeaturedItemsTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Devices Tab
// ---------------------------------------------------------------------------

class _DevicesTab extends ConsumerWidget {
  const _DevicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(_kioskDevicesProvider);
    final t = context.tokens;
    return devices.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) => items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.devices_other, size: 56, color: t.color.content.muted),
                  const SizedBox(height: 16),
                  const Text('No kiosk devices configured yet.'),
                  const SizedBox(height: 8),
                  const Text('Create a KIOSK-role user first, then configure their device here.',
                      textAlign: TextAlign.center),
                ],
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.all(t.spacing.md),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final d = items[i];
                final ordering = d['orderingEnabled'] as bool? ?? false;
                final user = d['user'] as Map? ?? {};
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(Icons.tv, color: t.color.background.accent)),
                    title: Text(user['username']?.toString() ?? 'Unknown device'),
                    subtitle: Text('Store: ${d['storeId']} · Ordering: ${ordering ? "ON" : "OFF"}'),
                    trailing: Switch(
                      value: ordering,
                      onChanged: (v) => _setOrdering(context, ref, user['id']?.toString() ?? '', v),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _setOrdering(BuildContext context, WidgetRef ref, String userId, bool enabled) async {
    try {
      await ref.read(dioProvider).patch(
        '/admin/kiosk/devices/$userId/ordering',
        data: {'enabled': enabled},
      );
      ref.invalidate(_kioskDevicesProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Featured Items Tab
// ---------------------------------------------------------------------------

class _FeaturedItemsTab extends ConsumerWidget {
  const _FeaturedItemsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(_featuredItemsProvider);
    final t = context.tokens;
    final df = DateFormat('dd MMM yyyy');
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addItem(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Featured'),
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_border, size: 56, color: t.color.content.muted),
                    const SizedBox(height: 16),
                    const Text('No featured items. Tap + to add one.'),
                  ],
                ),
              )
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(t.spacing.md, t.spacing.md, t.spacing.md, 80),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final item = list[i];
                  final product = item['product'] as Map? ?? {};
                  final from = item['dateFrom'] != null
                      ? df.format(DateTime.parse(item['dateFrom']))
                      : '—';
                  final to = item['dateTo'] != null
                      ? df.format(DateTime.parse(item['dateTo']))
                      : '—';
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.star)),
                      title: Text(product['name']?.toString() ?? item['productId']?.toString() ?? ''),
                      subtitle: Text('$from → $to · ${item['label'] ?? ""}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () => _editItem(context, ref, item),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: t.color.content.danger),
                          onPressed: () => _deleteItem(context, ref, item['id'] as String),
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _FeaturedItemDialog(),
    );
    if (saved == true) ref.invalidate(_featuredItemsProvider);
  }

  Future<void> _editItem(BuildContext context, WidgetRef ref, Map item) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FeaturedItemDialog(existing: item),
    );
    if (saved == true) ref.invalidate(_featuredItemsProvider);
  }

  Future<void> _deleteItem(BuildContext context, WidgetRef ref, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove featured item?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(dioProvider).delete('/admin/kiosk/featured/$id');
      ref.invalidate(_featuredItemsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Add/Edit Featured Item Dialog
// ---------------------------------------------------------------------------

class _FeaturedItemDialog extends ConsumerStatefulWidget {
  const _FeaturedItemDialog({this.existing});
  final Map? existing;
  @override
  ConsumerState<_FeaturedItemDialog> createState() => _FeaturedItemDialogState();
}

class _FeaturedItemDialogState extends ConsumerState<_FeaturedItemDialog> {
  final _productId = TextEditingController();
  final _label = TextEditingController();
  DateTime? _dateFrom;
  DateTime? _dateTo;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _productId.text = e['productId']?.toString() ?? '';
      _label.text = e['label']?.toString() ?? '';
      if (e['dateFrom'] != null) _dateFrom = DateTime.tryParse(e['dateFrom']);
      if (e['dateTo'] != null) _dateTo = DateTime.tryParse(e['dateTo']);
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => isFrom ? _dateFrom = picked : _dateTo = picked);
  }

  Future<void> _save() async {
    if (_productId.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final id = widget.existing?['id'] as String?;
    final body = {
      if (id == null) 'productId': _productId.text.trim(),
      'storeId': 'default',
      if (_label.text.trim().isNotEmpty) 'label': _label.text.trim(),
      if (_dateFrom != null) 'dateFrom': _dateFrom!.toIso8601String(),
      if (_dateTo != null) 'dateTo': _dateTo!.toIso8601String(),
    };
    try {
      if (id == null) {
        await ref.read(dioProvider).post('/admin/kiosk/featured', data: body);
      } else {
        await ref.read(dioProvider).patch('/admin/kiosk/featured/$id', data: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy');
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Featured Item' : 'Edit Featured Item'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.existing == null)
            TextField(
              controller: _productId,
              decoration: const InputDecoration(labelText: 'Product ID'),
            ),
          const SizedBox(height: 12),
          TextField(controller: _label, decoration: const InputDecoration(labelText: 'Display label (optional)')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_dateFrom != null ? df.format(_dateFrom!) : 'From date'),
                onPressed: () => _pickDate(true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_dateTo != null ? df.format(_dateTo!) : 'To date'),
                onPressed: () => _pickDate(false),
              ),
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
