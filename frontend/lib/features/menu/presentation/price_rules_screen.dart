import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../data/menu_repository.dart';

final _timeFormat = DateFormat('d MMM, h:mm a');

/// Menu > Happy hours. Percent-off rules for categories, optionally ending at a time.
class PriceRulesScreen extends ConsumerStatefulWidget {
  const PriceRulesScreen({super.key});

  @override
  ConsumerState<PriceRulesScreen> createState() => _PriceRulesScreenState();
}

class _PriceRulesScreenState extends ConsumerState<PriceRulesScreen> {
  String? _error;

  Future<void> _edit({PriceRule? rule}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PriceRuleDialog(rule: rule),
    );
    if (saved == true) {
      ref.invalidate(menuPriceRulesProvider);
      if (mounted) showAppToast(context, rule == null ? 'Happy hour added' : 'Happy hour saved');
    }
  }

  Future<void> _delete(PriceRule rule) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${rule.name}?',
      message: 'The discount stops applying on the POS straight away.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _error = null);
    try {
      await ref.read(menuRepositoryProvider).deletePriceRule(rule.id);
      ref.invalidate(menuPriceRulesProvider);
    } catch (e) {
      setState(() => _error = ApiError.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.menuEdit, AccessLevel.edit);
    final async = ref.watch(menuPriceRulesProvider);
    final rows = async.valueOrNull ?? const <PriceRule>[];

    final columns = <AppColumn<PriceRule>>[
      AppColumn<PriceRule>(
        label: 'Happy hour',
        cell: (r) => Text(r.name, overflow: TextOverflow.ellipsis),
      ),
      AppColumn<PriceRule>(
        label: 'Off',
        numeric: true,
        width: 90,
        cell: (r) => Text('${r.percentOff.toStringAsFixed(0)}%'),
      ),
      AppColumn<PriceRule>(
        label: 'Categories',
        cell: (r) => Text('${r.categoryIds.length}'),
      ),
      AppColumn<PriceRule>(
        label: 'Ends',
        cell: (r) => Text(r.endsAt == null ? 'No end time' : _timeFormat.format(r.endsAt!.toLocal())),
      ),
      AppColumn<PriceRule>(
        label: 'Status',
        width: 130,
        cell: (r) {
          if (!r.isActive) return const StatusBadge(label: 'Off', tone: StatusTone.neutral);
          return r.activeNow
              ? const StatusBadge(label: 'On now', tone: StatusTone.success)
              : const StatusBadge(label: 'Scheduled', tone: StatusTone.info);
        },
      ),
      if (canEdit)
        AppColumn<PriceRule>(
          label: 'Actions',
          width: 110,
          cell: (r) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit ${r.name}',
                onPressed: () => _edit(rule: r),
              ),
              AppIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Delete ${r.name}',
                onPressed: () => _delete(r),
              ),
            ],
          ),
        ),
    ];

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Happy hours',
              breadcrumb: 'Menu & products',
              actions: [
                if (canEdit)
                  AppButton(
                    label: 'New happy hour',
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
            SizedBox(height: t.spacing.md),
            Expanded(
              child: AppDataTable<PriceRule>(
                columns: columns,
                rows: rows,
                loading: async.isLoading && !async.hasValue,
                error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
                onRetry: () => ref.invalidate(menuPriceRulesProvider),
                empty: EmptyState(
                  title: 'No happy hours yet',
                  message: 'Set a percent off for a category at set times, such as 4 to 7 pm.',
                  icon: Icons.schedule_outlined,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Validates a percent-off value. Returns the error or null.
String? percentOffError(double? value) {
  if (value == null) return 'Enter a number';
  if (value <= 0 || value > 100) return 'Enter more than 0 and up to 100';
  return null;
}

class _PriceRuleDialog extends ConsumerStatefulWidget {
  const _PriceRuleDialog({this.rule});

  final PriceRule? rule;

  @override
  ConsumerState<_PriceRuleDialog> createState() => _PriceRuleDialogState();
}

class _PriceRuleDialogState extends ConsumerState<_PriceRuleDialog> {
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late final _percent = TextEditingController(
    text: widget.rule == null ? '' : widget.rule!.percentOff.toStringAsFixed(0),
  );
  late Set<String> _categoryIds = {...?widget.rule?.categoryIds};
  late DateTime? _endsAt = widget.rule?.endsAt?.toLocal();
  late bool _isActive = widget.rule?.isActive ?? true;
  String? _nameError;
  String? _percentError;
  String? _categoryError;
  String? _apiError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _percent.dispose();
    super.dispose();
  }

  Future<void> _pickEnd() async {
    final now = DateTime.now();
    final initial = _endsAt ?? now.add(const Duration(hours: 3));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() => _endsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final percent = double.tryParse(_percent.text.trim());
    setState(() {
      _apiError = null;
      _nameError = _name.text.trim().isEmpty ? 'Enter a name' : null;
      _percentError = percentOffError(percent);
      _categoryError = _categoryIds.isEmpty ? 'Pick at least one category' : null;
    });
    if (_nameError != null || _percentError != null || _categoryError != null) return;

    setState(() => _saving = true);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'percentOff': percent!.toStringAsFixed(2),
      'categoryIds': _categoryIds.toList(),
      // Product-level scope is not edited here; keep whatever the rule already has.
      'productIds': widget.rule?.productIds ?? const <String>[],
      'endsAt': _endsAt?.toUtc().toIso8601String(),
      'isActive': _isActive,
    };
    final repo = ref.read(menuRepositoryProvider);
    try {
      if (widget.rule == null) {
        await repo.createPriceRule(body);
      } else {
        await repo.updatePriceRule(widget.rule!.id, body);
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
    final categories = ref.watch(menuCategoriesProvider).valueOrNull ?? const <MenuCategory>[];
    final endsAt = _endsAt;

    return AlertDialog(
      title: Text(widget.rule == null ? 'New happy hour' : 'Edit happy hour'),
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
              AppTextField(label: 'Name', controller: _name, errorText: _nameError, hint: 'Happy hour'),
              SizedBox(height: t.spacing.md),
              AppTextField(
                label: 'Percent off',
                controller: _percent,
                keyboardType: TextInputType.number,
                errorText: _percentError,
                suffix: const Padding(padding: EdgeInsets.only(right: 12), child: Text('%')),
              ),
              SizedBox(height: t.spacing.md),
              _Labelled(
                label: 'Categories',
                errorText: _categoryError,
                child: Wrap(
                  spacing: t.spacing.sm,
                  runSpacing: t.spacing.xs,
                  children: [
                    for (final c in categories)
                      FilterChip(
                        label: Text(c.name),
                        selected: _categoryIds.contains(c.id),
                        onSelected: (on) => setState(() {
                          final next = {..._categoryIds};
                          if (on) {
                            next.add(c.id);
                          } else {
                            next.remove(c.id);
                          }
                          _categoryIds = next;
                        }),
                      ),
                  ],
                ),
              ),
              SizedBox(height: t.spacing.md),
              _Labelled(
                label: 'Ends at',
                helperText: 'Leave empty for a rule that runs until you turn it off.',
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        endsAt == null ? 'No end time' : _timeFormat.format(endsAt),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    AppButton(
                      label: endsAt == null ? 'Set end' : 'Change',
                      size: AppControlSize.sm,
                      onPressed: _pickEnd,
                    ),
                    if (endsAt != null)
                      AppIconButton(
                        icon: Icons.clear,
                        tooltip: 'Clear end time',
                        onPressed: () => setState(() => _endsAt = null),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
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
