import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../data/menu_repository.dart';

const _listWidth = 280.0;

/// Menu > Modifiers. Pick a group on the left to edit its rules and options.
class ModifierGroupsScreen extends ConsumerStatefulWidget {
  const ModifierGroupsScreen({super.key});

  @override
  ConsumerState<ModifierGroupsScreen> createState() => _ModifierGroupsScreenState();
}

class _ModifierGroupsScreenState extends ConsumerState<ModifierGroupsScreen> {
  String? _selectedId;
  bool _creating = false;

  void _select(String? id) => setState(() {
        _selectedId = id;
        _creating = false;
      });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.menuEdit, AccessLevel.edit);
    final async = ref.watch(menuModifierGroupsProvider);
    final groups = async.valueOrNull ?? const <ModifierGroup>[];
    ModifierGroup? selected;
    for (final g in groups) {
      if (g.id == _selectedId) selected = g;
    }

    Widget body;
    if (!async.hasValue) {
      body = async.hasError
          ? ErrorState(
              message: ApiError.from(async.error!).message,
              onRetry: () => ref.invalidate(menuModifierGroupsProvider),
            )
          : DelayedSkeleton(child: SkeletonList());
    } else if (groups.isEmpty && !_creating) {
      body = EmptyState(
        title: 'No modifier groups yet',
        message: 'Groups such as Ice level or Add-ons attach to products on the POS.',
        icon: Icons.tune,
        actionLabel: canEdit ? 'New group' : null,
        onAction: canEdit ? () => setState(() => _creating = true) : null,
      );
    } else {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _listWidth,
            child: AppCard(
              title: 'Groups',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final g in groups)
                    _GroupTile(
                      group: g,
                      selected: !_creating && g.id == _selectedId,
                      onTap: () => _select(g.id),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(width: t.spacing.md),
          Expanded(
            child: _creating || selected != null
                ? _GroupEditor(
                    key: ValueKey(selected?.id ?? 'new'),
                    group: selected,
                    canEdit: canEdit,
                    onSaved: (id) {
                      ref.invalidate(menuModifierGroupsProvider);
                      _select(id);
                      showAppToast(context, 'Modifier group saved');
                    },
                    onDeleted: () {
                      ref.invalidate(menuModifierGroupsProvider);
                      _select(null);
                    },
                  )
                : const EmptyState(
                    title: 'Pick a group',
                    message: 'Choose a group on the left to edit its options.',
                    icon: Icons.touch_app_outlined,
                  ),
          ),
        ],
      );
    }

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Modifier groups',
              breadcrumb: 'Menu & products',
              actions: [
                if (canEdit)
                  AppButton(
                    label: 'New group',
                    icon: Icons.add,
                    variant: AppButtonVariant.primary,
                    onPressed: () => setState(() {
                      _creating = true;
                      _selectedId = null;
                    }),
                  ),
              ],
            ),
            SizedBox(height: t.spacing.md),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.selected, required this.onTap});

  final ModifierGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radius.sm),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.spacing.sm, vertical: t.spacing.sm),
        decoration: BoxDecoration(
          color: selected ? t.color.background.surface : null,
          borderRadius: BorderRadius.circular(t.radius.sm),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                group.name,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
              ),
            ),
            Text(
              'Pick ${group.minSelect}-${group.maxSelect}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// One editable option row. Owns its controllers.
class _OptionRow {
  _OptionRow({this.id, String name = '', String price = '0.00'})
      : name = TextEditingController(text: name),
        price = TextEditingController(text: price);

  final String? id;
  final TextEditingController name;
  final TextEditingController price;

  void dispose() {
    name.dispose();
    price.dispose();
  }
}

/// Editor for one group, or a new group when [group] is null. Keyed by group id
/// so switching groups starts with fresh controllers.
class _GroupEditor extends ConsumerStatefulWidget {
  const _GroupEditor({
    super.key,
    this.group,
    required this.canEdit,
    required this.onSaved,
    required this.onDeleted,
  });

  final ModifierGroup? group;
  final bool canEdit;
  final ValueChanged<String> onSaved;
  final VoidCallback onDeleted;

  @override
  ConsumerState<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends ConsumerState<_GroupEditor> {
  late final _name = TextEditingController(text: widget.group?.name ?? '');
  late final _min = TextEditingController(text: '${widget.group?.minSelect ?? 0}');
  late final _max = TextEditingController(text: '${widget.group?.maxSelect ?? 1}');
  late final List<_OptionRow> _options = [
    for (final o in widget.group?.options ?? const <ModifierOption>[])
      _OptionRow(id: o.id, name: o.name, price: o.priceDelta.toStringAsFixed(2)),
  ];
  String? _nameError;
  String? _rulesError;
  String? _optionError;
  String? _apiError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    _max.dispose();
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  /// Returns the rule error (min and max), or null when they are valid.
  static String? rulesError(int? min, int? max) {
    if (min == null || max == null) return 'Enter whole numbers';
    if (min < 0) return 'Minimum cannot be negative';
    if (max < 1) return 'Maximum must be at least 1';
    if (min > max) return 'Minimum cannot be more than maximum';
    return null;
  }

  Future<void> _save() async {
    final min = int.tryParse(_min.text.trim());
    final max = int.tryParse(_max.text.trim());
    final prices = [for (final o in _options) double.tryParse(o.price.text.trim())];
    setState(() {
      _apiError = null;
      _nameError = _name.text.trim().isEmpty ? 'Enter a name' : null;
      _rulesError = rulesError(min, max);
      _optionError = null;
      for (var i = 0; i < _options.length; i++) {
        if (_options[i].name.text.trim().isEmpty || prices[i] == null) {
          _optionError = 'Each option needs a name and a price change';
        }
      }
    });
    if (_nameError != null || _rulesError != null || _optionError != null) return;

    setState(() => _saving = true);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'minSelect': min,
      'maxSelect': max,
      'options': [
        for (var i = 0; i < _options.length; i++)
          ModifierOption(
            id: _options[i].id,
            name: _options[i].name.text.trim(),
            priceDelta: prices[i]!,
          ).toJson(i),
      ],
    };
    final repo = ref.read(menuRepositoryProvider);
    try {
      final id = widget.group == null
          ? (await repo.createModifierGroup(body)).id
          : widget.group!.id;
      if (widget.group != null) await repo.updateModifierGroup(id, body);
      if (mounted) widget.onSaved(id);
    } catch (e) {
      if (mounted) setState(() => _apiError = ApiError.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final group = widget.group;
    if (group == null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${group.name}?',
      message: group.usedBy > 0
          ? 'It is used by ${group.usedBy} items and will be removed from them.'
          : 'Items that use it will lose these options.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(menuRepositoryProvider).deleteModifierGroup(group.id);
      if (mounted) widget.onDeleted();
    } catch (e) {
      if (mounted) setState(() => _apiError = ApiError.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canEdit = widget.canEdit;
    return AppCard(
      title: widget.group == null ? 'New group' : widget.group!.name,
      actions: [
        if (canEdit && widget.group != null)
          AppButton(
            label: 'Delete',
            variant: AppButtonVariant.danger,
            size: AppControlSize.sm,
            onPressed: _delete,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_apiError != null) ...[
            InlineAlert(message: _apiError!),
            SizedBox(height: t.spacing.sm),
          ],
          AppTextField(
            label: 'Group name',
            controller: _name,
            errorText: _nameError,
            hint: 'Ice level',
          ),
          SizedBox(height: t.spacing.md),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Minimum to pick',
                  controller: _min,
                  keyboardType: TextInputType.number,
                  errorText: _rulesError,
                ),
              ),
              SizedBox(width: t.spacing.md),
              Expanded(
                child: AppTextField(
                  label: 'Maximum to pick',
                  controller: _max,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          SizedBox(height: t.spacing.md),
          Text('Options', style: Theme.of(context).textTheme.labelLarge),
          SizedBox(height: t.spacing.xs),
          if (_optionError != null) ...[
            InlineAlert(message: _optionError!),
            SizedBox(height: t.spacing.sm),
          ],
          for (var i = 0; i < _options.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: t.spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: AppTextField(label: 'Option ${i + 1}', controller: _options[i].name),
                  ),
                  SizedBox(width: t.spacing.sm),
                  Expanded(
                    flex: 2,
                    child: AppTextField(
                      label: 'Price change',
                      controller: _options[i].price,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  if (canEdit)
                    AppIconButton(
                      icon: Icons.remove_circle_outline,
                      tooltip: 'Remove option ${i + 1}',
                      onPressed: () => setState(() => _options.removeAt(i).dispose()),
                    ),
                ],
              ),
            ),
          if (canEdit)
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'Add option',
                icon: Icons.add,
                size: AppControlSize.sm,
                onPressed: () => setState(() => _options.add(_OptionRow(price: '0.00'))),
              ),
            ),
          SizedBox(height: t.spacing.md),
          if (canEdit)
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Save group',
                variant: AppButtonVariant.primary,
                loading: _saving,
                onPressed: _save,
              ),
            ),
        ],
      ),
    );
  }
}
