import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../data/tax_repository.dart';
import '../domain/tax_rules.dart';

const _orderTypes = [
  AppSelectItem('DINE_IN', 'Dine-in'),
  AppSelectItem('BAR_COUNTER', 'Bar counter'),
  AppSelectItem('TAKEAWAY', 'Takeaway'),
  AppSelectItem('DELIVERY', 'Delivery'),
];

const _roundingModes = [
  AppSelectItem('NONE', 'No rounding'),
  AppSelectItem('NEAREST_1', 'Nearest ₹1'),
  AppSelectItem('NEAREST_5', 'Nearest ₹5'),
];

final _prefixPattern = RegExp(r'^[A-Za-z0-9-]{1,10}$');
final _countryPattern = RegExp(r'^[A-Z]{2}$');

/// Settings > Tax, invoice & payments. Four tabs: tax rules (tax classes),
/// service charge and rounding, invoice numbering, and the legacy global rate.
class TaxSettingsScreen extends StatelessWidget {
  const TaxSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(t.spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(title: 'Tax, invoice & payments', breadcrumb: 'Settings'),
              TabBar(
                isScrollable: true,
                tabs: const [
                  Tab(text: 'Tax rules'),
                  Tab(text: 'Service charge & rounding'),
                  Tab(text: 'Invoice numbering'),
                  Tab(text: 'Global tax'),
                ],
              ),
              SizedBox(height: t.spacing.md),
              const Expanded(
                child: TabBarView(
                  children: [
                    _TaxRulesTab(),
                    _ServiceTab(),
                    _InvoiceTab(),
                    _GlobalTaxTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a load error or spinner in place of a form.
Widget _loadState(Object? error, VoidCallback retry) => ErrorState(
      message: ApiError.from(error!).message,
      onRetry: retry,
    );

// ---------------------------------------------------------------------------
// Tax rules
// ---------------------------------------------------------------------------

class _TaxRulesTab extends ConsumerStatefulWidget {
  const _TaxRulesTab();

  @override
  ConsumerState<_TaxRulesTab> createState() => _TaxRulesTabState();
}

class _TaxRulesTabState extends ConsumerState<_TaxRulesTab> {
  String? _error;

  Future<void> _edit({TaxClass? taxClass}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _TaxClassDialog(taxClass: taxClass),
    );
    if (saved == true) {
      ref.invalidate(taxClassesProvider);
      if (mounted) showAppToast(context, taxClass == null ? 'Tax rule added' : 'Tax rule saved');
    }
  }

  Future<void> _delete(TaxClass taxClass) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${taxClass.name}?',
      message: 'Past orders keep the tax they were charged.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _error = null);
    try {
      await ref.read(taxRepositoryProvider).deleteTaxClass(taxClass.id);
      ref.invalidate(taxClassesProvider);
    } catch (e) {
      final err = ApiError.from(e);
      setState(() {
        _error = err.code == 'TAX_CLASS_IN_USE'
            ? '${taxClass.name} is used by products or categories. Move them first.'
            : err.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.adminSettings, AccessLevel.edit);
    final async = ref.watch(taxClassesProvider);
    final rows = async.valueOrNull ?? const <TaxClass>[];

    final columns = <AppColumn<TaxClass>>[
      AppColumn<TaxClass>(
        label: 'Tax rule',
        cell: (c) => Text(c.code.isEmpty ? c.name : '${c.name} (${c.code})', overflow: TextOverflow.ellipsis),
      ),
      AppColumn<TaxClass>(
        label: 'Rate',
        numeric: true,
        width: 90,
        cell: (c) => Text('${c.rate.toStringAsFixed(2)}%'),
      ),
      AppColumn<TaxClass>(
        label: 'Components',
        cell: (c) => Text(
          c.components.map((x) => '${x.name} ${x.rate.toStringAsFixed(2)}').join(' + '),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      AppColumn<TaxClass>(
        label: 'Liquor',
        width: 110,
        cell: (c) => StatusBadge(
          label: c.isLiquor ? 'Liquor' : 'Food',
          tone: c.isLiquor ? StatusTone.warning : StatusTone.neutral,
        ),
      ),
      if (canEdit)
        AppColumn<TaxClass>(
          label: 'Actions',
          width: 110,
          cell: (c) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit ${c.name}',
                onPressed: () => _edit(taxClass: c),
              ),
              AppIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete ${c.name}',
                onPressed: () => _delete(c),
              ),
            ],
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Each product or category points at one tax rule. Components must add up to the rate.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (canEdit)
              AppButton(
                label: 'New tax rule',
                icon: Icons.add,
                variant: AppButtonVariant.primary,
                onPressed: () => _edit(),
              ),
          ],
        ),
        if (_error != null) ...[
          SizedBox(height: t.spacing.sm),
          InlineAlert(message: _error!),
        ],
        SizedBox(height: t.spacing.sm),
        Expanded(
          child: AppDataTable<TaxClass>(
            columns: columns,
            rows: rows,
            loading: async.isLoading && !async.hasValue,
            error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
            onRetry: () => ref.invalidate(taxClassesProvider),
            empty: EmptyState(
              title: 'No tax rules yet',
              message: 'Add a rule such as GST 5% with CGST and SGST components.',
              icon: Icons.percent,
            ),
          ),
        ),
      ],
    );
  }
}

class _CompRow {
  _CompRow({String name = '', String rate = ''})
      : name = TextEditingController(text: name),
        rate = TextEditingController(text: rate);

  final TextEditingController name;
  final TextEditingController rate;

  void dispose() {
    name.dispose();
    rate.dispose();
  }
}

class _TaxClassDialog extends ConsumerStatefulWidget {
  const _TaxClassDialog({this.taxClass});

  final TaxClass? taxClass;

  @override
  ConsumerState<_TaxClassDialog> createState() => _TaxClassDialogState();
}

class _TaxClassDialogState extends ConsumerState<_TaxClassDialog> {
  late final _code = TextEditingController(text: widget.taxClass?.code ?? '');
  late final _name = TextEditingController(text: widget.taxClass?.name ?? '');
  late final _rate = TextEditingController(text: widget.taxClass?.rate.toStringAsFixed(2) ?? '');
  late bool _isLiquor = widget.taxClass?.isLiquor ?? false;
  late bool _inclusive = widget.taxClass?.inclusive ?? false;
  late final List<_CompRow> _components = [
    for (final c in widget.taxClass?.components ?? const <TaxComponent>[])
      _CompRow(name: c.name, rate: c.rate.toStringAsFixed(2)),
  ];
  String? _nameError;
  String? _rateError;
  String? _componentError;
  String? _apiError;
  bool _saving = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _rate.dispose();
    for (final c in _components) {
      c.dispose();
    }
    super.dispose();
  }

  List<TaxComponent> _parsedComponents() => [
        for (final c in _components)
          TaxComponent(name: c.name.text.trim(), rate: double.tryParse(c.rate.text.trim()) ?? -1),
      ];

  Future<void> _save() async {
    final rate = double.tryParse(_rate.text.trim());
    final components = _parsedComponents();
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'Enter a name' : null;
      _rateError = (rate == null || rate < 0 || rate > 100) ? 'Enter a rate from 0 to 100' : null;
      final bad = components.any((c) => c.name.isEmpty || c.rate < 0);
      _componentError = bad ? 'Each component needs a name and a rate' : null;
      if (_componentError == null && _rateError == null) {
        _componentError = taxComponentsError(rate!, components);
      }
      _apiError = null;
    });
    if (_nameError != null || _rateError != null || _componentError != null) return;

    setState(() => _saving = true);
    final body = <String, dynamic>{
      'code': _code.text.trim(),
      'name': _name.text.trim(),
      'rate': rate!.toStringAsFixed(2),
      'isLiquor': _isLiquor,
      'inclusive': _inclusive,
      'components': [for (final c in components) c.toJson()],
    };
    final repo = ref.read(taxRepositoryProvider);
    try {
      if (widget.taxClass == null) {
        await repo.createTaxClass(body);
      } else {
        await repo.updateTaxClass(widget.taxClass!.id, body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _apiError = ApiError.from(e).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      title: Text(widget.taxClass == null ? 'New tax rule' : 'Edit tax rule'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_apiError != null) ...[
                InlineAlert(message: _apiError!),
                SizedBox(height: t.spacing.sm),
              ],
              AppTextField(label: 'Name', controller: _name, errorText: _nameError, autofocus: true),
              SizedBox(height: t.spacing.md),
              AppTextField(label: 'Code', controller: _code, hint: 'GST5'),
              SizedBox(height: t.spacing.md),
              AppTextField(
                label: 'Rate %',
                controller: _rate,
                keyboardType: TextInputType.number,
                errorText: _rateError,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Liquor'),
                value: _isLiquor,
                onChanged: (v) => setState(() => _isLiquor = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Price includes tax'),
                value: _inclusive,
                onChanged: (v) => setState(() => _inclusive = v),
              ),
              SizedBox(height: t.spacing.sm),
              Text('Components', style: Theme.of(context).textTheme.labelLarge),
              SizedBox(height: t.spacing.xs),
              for (var i = 0; i < _components.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: t.spacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: AppTextField(label: 'Part ${i + 1}', controller: _components[i].name),
                      ),
                      SizedBox(width: t.spacing.sm),
                      Expanded(
                        flex: 2,
                        child: AppTextField(
                          label: 'Rate %',
                          controller: _components[i].rate,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      AppIconButton(
                        icon: Icons.remove_circle_outline,
                        tooltip: 'Remove part ${i + 1}',
                        onPressed: () => setState(() => _components.removeAt(i).dispose()),
                      ),
                    ],
                  ),
                ),
              if (_componentError != null) ...[
                InlineAlert(message: _componentError!),
                SizedBox(height: t.spacing.sm),
              ],
              AppButton(
                label: 'Add component',
                icon: Icons.add,
                size: AppControlSize.sm,
                onPressed: () => setState(() => _components.add(_CompRow(rate: '0'))),
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
          label: 'Save',
          variant: AppButtonVariant.primary,
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Service charge & rounding
// ---------------------------------------------------------------------------

class _ServiceTab extends ConsumerStatefulWidget {
  const _ServiceTab();

  @override
  ConsumerState<_ServiceTab> createState() => _ServiceTabState();
}

class _ServiceTabState extends ConsumerState<_ServiceTab> {
  final _percent = TextEditingController();
  Set<String> _types = {};
  String _rounding = 'NONE';
  bool _loaded = false;
  bool _saving = false;
  String? _percentError;
  String? _error;
  String? _saved;

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }

  void _load(OutletSettings s) {
    _percent.text = s.serviceChargePercent.toStringAsFixed(2);
    _types = s.serviceChargeTypes.toSet();
    _rounding = s.roundingMode;
    _loaded = true;
  }

  Future<void> _save() async {
    final value = double.tryParse(_percent.text.trim());
    setState(() {
      _percentError = (value == null || value < 0 || value > 100) ? 'Enter a percentage from 0 to 100' : null;
      _error = null;
      _saved = null;
    });
    if (_percentError != null) return;
    final current = ref.read(outletSettingsProvider).valueOrNull ?? const OutletSettings();
    setState(() => _saving = true);
    try {
      await ref.read(taxRepositoryProvider).saveOutletSettings(
            current.copyWith(
              serviceChargePercent: value,
              serviceChargeTypes: _types.toList(),
              roundingMode: _rounding,
            ),
          );
      ref.invalidate(outletSettingsProvider);
      if (mounted) setState(() => _saved = 'Saved');
    } catch (e) {
      if (mounted) setState(() => _error = ApiError.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.adminSettings, AccessLevel.edit);
    final async = ref.watch(outletSettingsProvider);
    if (!async.hasValue) {
      return async.hasError
          ? _loadState(async.error, () => ref.invalidate(outletSettingsProvider))
          : DelayedSkeleton(child: SkeletonList(rows: 3));
    }
    if (!_loaded) _load(async.requireValue);

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              title: 'Service charge',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppTextField(
                    label: 'Service charge %',
                    controller: _percent,
                    keyboardType: TextInputType.number,
                    errorText: _percentError,
                  ),
                  SizedBox(height: t.spacing.md),
                  _Labelled(
                    label: 'Applies to order types',
                    child: Wrap(
                      spacing: t.spacing.sm,
                      runSpacing: t.spacing.xs,
                      children: [
                        for (final item in _orderTypes)
                          FilterChip(
                            label: Text(item.label),
                            selected: _types.contains(item.value),
                            onSelected: canEdit
                                ? (on) => setState(() {
                                      if (on) {
                                        _types.add(item.value);
                                      } else {
                                        _types.remove(item.value);
                                      }
                                    })
                                : null,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: t.spacing.md),
            AppCard(
              title: 'Rounding',
              child: AppSelect<String>(
                label: 'Round the grand total',
                value: _rounding,
                items: _roundingModes,
                onChanged: canEdit ? (v) => setState(() => _rounding = v ?? _rounding) : (_) {},
              ),
            ),
            SizedBox(height: t.spacing.md),
            if (_error != null) ...[
              InlineAlert(message: _error!),
              SizedBox(height: t.spacing.sm),
            ],
            Row(
              children: [
                if (canEdit)
                  AppButton(
                    label: 'Save',
                    variant: AppButtonVariant.primary,
                    loading: _saving,
                    onPressed: _save,
                  ),
                if (_saved != null) ...[
                  SizedBox(width: t.spacing.md),
                  Text(_saved!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Invoice numbering
// ---------------------------------------------------------------------------

class _InvoiceTab extends ConsumerStatefulWidget {
  const _InvoiceTab();

  @override
  ConsumerState<_InvoiceTab> createState() => _InvoiceTabState();
}

class _InvoiceTabState extends ConsumerState<_InvoiceTab> {
  final _orderPrefix = TextEditingController();
  final _invoicePrefix = TextEditingController();
  final _country = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  String? _error;
  String? _orderError;
  String? _invoiceError;
  String? _countryError;

  @override
  void initState() {
    super.initState();
    // Rebuild the preview as the invoice prefix changes.
    _invoicePrefix.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _orderPrefix.dispose();
    _invoicePrefix.dispose();
    _country.dispose();
    super.dispose();
  }

  void _load(OutletSettings s) {
    _orderPrefix.text = s.orderPrefix;
    _invoicePrefix.text = s.invoicePrefix;
    _country.text = s.countryCode;
    _loaded = true;
  }

  Future<void> _save() async {
    setState(() {
      _orderError = _prefixPattern.hasMatch(_orderPrefix.text.trim()) ? null : 'Letters, digits or hyphen, up to 10';
      _invoiceError = _prefixPattern.hasMatch(_invoicePrefix.text.trim()) ? null : 'Letters, digits or hyphen, up to 10';
      _countryError = _countryPattern.hasMatch(_country.text.trim()) ? null : 'Two capital letters, such as IN';
      _error = null;
    });
    if (_orderError != null || _invoiceError != null || _countryError != null) return;
    final current = ref.read(outletSettingsProvider).valueOrNull ?? const OutletSettings();
    setState(() => _saving = true);
    try {
      await ref.read(taxRepositoryProvider).saveOutletSettings(
            current.copyWith(
              orderPrefix: _orderPrefix.text.trim(),
              invoicePrefix: _invoicePrefix.text.trim(),
              countryCode: _country.text.trim(),
            ),
          );
      ref.invalidate(outletSettingsProvider);
    } catch (e) {
      if (mounted) setState(() => _error = ApiError.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.adminSettings, AccessLevel.edit);
    final async = ref.watch(outletSettingsProvider);
    if (!async.hasValue) {
      return async.hasError
          ? _loadState(async.error, () => ref.invalidate(outletSettingsProvider))
          : DelayedSkeleton(child: SkeletonList(rows: 3));
    }
    if (!_loaded) _load(async.requireValue);

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              title: 'Numbering',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppTextField(
                    label: 'Order prefix',
                    controller: _orderPrefix,
                    hint: 'ORD',
                    errorText: _orderError,
                    helperText: 'Orders are numbered ORD-1, ORD-2 and so on.',
                  ),
                  SizedBox(height: t.spacing.md),
                  AppTextField(
                    label: 'Invoice prefix',
                    controller: _invoicePrefix,
                    hint: 'INV',
                    errorText: _invoiceError,
                  ),
                  SizedBox(height: t.spacing.md),
                  AppTextField(
                    label: 'Country code',
                    controller: _country,
                    hint: 'IN',
                    errorText: _countryError,
                    helperText: 'Picks the invoice rules for the country.',
                  ),
                  SizedBox(height: t.spacing.md),
                  Text(
                    'Preview: ${invoicePreview(_invoicePrefix.text, DateTime.now())}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            SizedBox(height: t.spacing.md),
            if (_error != null) ...[
              InlineAlert(message: _error!),
              SizedBox(height: t.spacing.sm),
            ],
            if (canEdit)
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  label: 'Save',
                  variant: AppButtonVariant.primary,
                  loading: _saving,
                  onPressed: _save,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Global tax (legacy single rate)
// ---------------------------------------------------------------------------

class _GlobalTaxTab extends ConsumerStatefulWidget {
  const _GlobalTaxTab();

  @override
  ConsumerState<_GlobalTaxTab> createState() => _GlobalTaxTabState();
}

class _GlobalTaxTabState extends ConsumerState<_GlobalTaxTab> {
  final _controller = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value < 0 || value > 100) {
      setState(() => _error = 'Enter a percentage from 0 to 100');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(taxRepositoryProvider).saveGlobalTax(value);
      ref.invalidate(globalTaxProvider);
      if (mounted) showAppToast(context, 'Global tax updated');
    } catch (e) {
      if (mounted) setState(() => _error = ApiError.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.adminSettings, AccessLevel.edit);
    final async = ref.watch(globalTaxProvider);
    if (!async.hasValue) {
      return async.hasError
          ? _loadState(async.error, () => ref.invalidate(globalTaxProvider))
          : DelayedSkeleton(child: SkeletonList(rows: 2));
    }
    if (!_loaded) {
      _controller.text = async.requireValue.toStringAsFixed(2);
      _loaded = true;
    }

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AppCard(
          title: 'Global tax',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Applied to products without a tax class. Tax rules above take priority.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SizedBox(height: t.spacing.md),
              AppTextField(
                label: 'Global tax %',
                controller: _controller,
                keyboardType: TextInputType.number,
              ),
              if (_error != null) ...[
                SizedBox(height: t.spacing.sm),
                InlineAlert(message: _error!),
              ],
              SizedBox(height: t.spacing.md),
              if (canEdit)
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    label: 'Save',
                    variant: AppButtonVariant.primary,
                    loading: _saving,
                    onPressed: _save,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label, child and optional error or helper text. Local stand-in for FieldFrame,
/// which is not part of the ui.dart barrel.
class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child, this.errorText, this.helperText});

  final String label;
  final Widget child;
  final String? errorText;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final error = errorText;
    final helper = helperText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: text.labelLarge),
        SizedBox(height: t.spacing.xs),
        child,
        if (error != null) ...[
          SizedBox(height: t.spacing.xs),
          Text(error, style: text.bodySmall?.copyWith(color: t.color.content.danger)),
        ],
        if (error == null && helper != null) ...[
          SizedBox(height: t.spacing.xs),
          Text(helper, style: text.bodySmall),
        ],
      ],
    );
  }
}
