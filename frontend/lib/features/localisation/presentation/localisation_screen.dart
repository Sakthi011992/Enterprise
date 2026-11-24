import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_mode_toggle.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

const _locales = ['en', 'hi', 'ja', 'kn'];
const _localeNames = {'en': 'English', 'hi': 'Hindi', 'ja': 'Japanese', 'kn': 'Kannada'};

final _bundleProvider = FutureProvider.family<Map<String, String>, String>((ref, locale) async {
  final res = await ref.watch(dioProvider).get('/locales/$locale/bundle');
  final raw = res.data as Map;
  return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class LocalisationScreen extends ConsumerStatefulWidget {
  const LocalisationScreen({super.key});
  @override
  ConsumerState<LocalisationScreen> createState() => _LocalisationScreenState();
}

class _LocalisationScreenState extends ConsumerState<LocalisationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _locales.length, vsync: this);
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
        title: const Text('Localisation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add translation key',
            onPressed: () => _addKey(context),
          ),
          const ThemeModeToggle(),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: _locales.map((l) => Tab(text: _localeNames[l])).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: _locales.map((l) => _LocaleTab(locale: l)).toList(),
      ),
    );
  }

  Future<void> _addKey(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddKeyDialog(),
    );
    if (saved == true) {
      for (final l in _locales) {
        ref.invalidate(_bundleProvider(l));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Per-locale tab
// ---------------------------------------------------------------------------

class _LocaleTab extends ConsumerStatefulWidget {
  const _LocaleTab({required this.locale});
  final String locale;
  @override
  ConsumerState<_LocaleTab> createState() => _LocaleTabState();
}

class _LocaleTabState extends ConsumerState<_LocaleTab> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(_bundleProvider(widget.locale));
    final t = context.tokens;
    return bundle.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading ${widget.locale}: $e')),
      data: (map) {
        final entries = map.entries
            .where((e) => _search.isEmpty ||
                e.key.contains(_search) ||
                e.value.toLowerCase().contains(_search.toLowerCase()))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.all(t.spacing.step(3)),
              child: TextField(
                decoration: const InputDecoration(hintText: 'Search keys or values', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('No translation keys yet.\nTap + to add one.', textAlign: TextAlign.center))
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = entries[i];
                        return ListTile(
                          title: Text(e.key, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                          subtitle: Text(e.value.isEmpty ? '(empty)' : e.value,
                              style: TextStyle(color: e.value.isEmpty ? context.tokens.color.content.muted : null)),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _editValue(context, e.key, e.value),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editValue(BuildContext context, String key, String current) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditValueDialog(locale: widget.locale, translationKey: key, current: current),
    );
    if (saved == true) ref.invalidate(_bundleProvider(widget.locale));
  }
}

// ---------------------------------------------------------------------------
// Add key dialog
// ---------------------------------------------------------------------------

class _AddKeyDialog extends ConsumerStatefulWidget {
  const _AddKeyDialog();
  @override
  ConsumerState<_AddKeyDialog> createState() => _AddKeyDialogState();
}

class _AddKeyDialogState extends ConsumerState<_AddKeyDialog> {
  final _key = TextEditingController();
  final _desc = TextEditingController();
  bool _saving = false;

  Future<void> _save() async {
    if (_key.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).post('/locales/keys', data: {
        'key': _key.text.trim(),
        if (_desc.text.trim().isNotEmpty) 'description': _desc.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Translation Key'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _key,
            decoration: const InputDecoration(labelText: 'Key (e.g. product.name)', hintText: 'dot.separated.key'),
          ),
          const SizedBox(height: 16),
          TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Description (optional)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Add')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Edit value dialog
// ---------------------------------------------------------------------------

class _EditValueDialog extends ConsumerStatefulWidget {
  const _EditValueDialog({required this.locale, required this.translationKey, required this.current});
  final String locale;
  final String translationKey;
  final String current;
  @override
  ConsumerState<_EditValueDialog> createState() => _EditValueDialogState();
}

class _EditValueDialogState extends ConsumerState<_EditValueDialog> {
  late final _value = TextEditingController(text: widget.current);
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).post('/locales/${widget.locale}/values', data: {
        'key': widget.translationKey,
        'value': _value.text,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_localeNames[widget.locale] ?? widget.locale),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.translationKey, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            controller: _value,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Translation', border: OutlineInputBorder()),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
