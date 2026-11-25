import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../data/menu_repository.dart';

final _hexColour = RegExp(r'^#[0-9A-Fa-f]{6}$');

/// Menu > Categories. Soft delete: a category with active products is refused.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  String? _error;

  Future<void> _edit({MenuCategory? category}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryDialog(category: category),
    );
    if (saved == true) {
      ref.invalidate(menuCategoriesProvider);
      if (mounted) showAppToast(context, category == null ? 'Category added' : 'Category saved');
    }
  }

  Future<void> _delete(MenuCategory category) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${category.name}?',
      message: 'Past orders keep their category. Items move out of this category.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _error = null);
    try {
      await ref.read(menuRepositoryProvider).deleteCategory(category.id);
      ref.invalidate(menuCategoriesProvider);
    } catch (e) {
      final err = ApiError.from(e);
      setState(() {
        _error = err.code == 'CATEGORY_IN_USE'
            ? 'Move or hide the products in ${category.name} first.'
            : err.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.menuEdit, AccessLevel.edit);
    final async = ref.watch(menuCategoriesProvider);
    final rows = async.valueOrNull ?? const <MenuCategory>[];

    final columns = <AppColumn<MenuCategory>>[
      AppColumn<MenuCategory>(
        label: 'Category',
        cell: (c) => Text(c.name, overflow: TextOverflow.ellipsis),
      ),
      AppColumn<MenuCategory>(
        label: 'Colour',
        cell: (c) => Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: _parseColour(c.color) ?? t.color.border.subtle,
                borderRadius: BorderRadius.circular(t.radius.sm),
                border: Border.all(color: t.color.border.standard, width: t.borderWidth.hairline),
              ),
            ),
            SizedBox(width: t.spacing.sm),
            Text(c.color ?? '-'),
          ],
        ),
      ),
      AppColumn<MenuCategory>(
        label: 'Sort',
        numeric: true,
        width: 80,
        cell: (c) => Text('${c.sortOrder}'),
      ),
      AppColumn<MenuCategory>(
        label: 'Status',
        width: 120,
        cell: (c) => StatusBadge(
          label: c.isActive ? 'Active' : 'Hidden',
          tone: c.isActive ? StatusTone.success : StatusTone.neutral,
        ),
      ),
      if (canEdit)
        AppColumn<MenuCategory>(
          label: 'Actions',
          width: 110,
          cell: (c) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit ${c.name}',
                onPressed: () => _edit(category: c),
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

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Categories',
              breadcrumb: 'Menu & products',
              actions: [
                if (canEdit)
                  AppButton(
                    label: 'Add category',
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
              child: AppDataTable<MenuCategory>(
                columns: columns,
                rows: rows,
                loading: async.isLoading && !async.hasValue,
                error: async.hasError && !async.hasValue ? ApiError.from(async.error!).message : null,
                onRetry: () => ref.invalidate(menuCategoriesProvider),
                empty: EmptyState(
                  title: 'No categories yet',
                  message: 'Categories group products on the POS, such as Drinks or Starters.',
                  icon: Icons.category_outlined,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color? _parseColour(String? hex) {
  if (hex == null || !_hexColour.hasMatch(hex)) return null;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

class _CategoryDialog extends ConsumerStatefulWidget {
  const _CategoryDialog({this.category});

  final MenuCategory? category;

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late final _colour = TextEditingController(text: widget.category?.color ?? '#3F3F46');
  late final _sort = TextEditingController(text: '${widget.category?.sortOrder ?? 0}');
  String? _nameError;
  String? _colourError;
  String? _sortError;
  String? _apiError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _colour.dispose();
    _sort.dispose();
    super.dispose();
  }

  bool _validate() {
    final sort = int.tryParse(_sort.text.trim());
    _nameError = _name.text.trim().isEmpty ? 'Enter a name' : null;
    _colourError = _hexColour.hasMatch(_colour.text.trim()) ? null : 'Use a hex colour such as #3F3F46';
    _sortError = (sort == null || sort < 0) ? 'Enter 0 or more' : null;
    return _nameError == null && _colourError == null && _sortError == null;
  }

  Future<void> _save() async {
    setState(() {
      _apiError = null;
      if (!_validate()) return;
    });
    if (_nameError != null || _colourError != null || _sortError != null) return;
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'color': _colour.text.trim(),
      'sortOrder': int.parse(_sort.text.trim()),
    };
    final repo = ref.read(menuRepositoryProvider);
    try {
      if (widget.category == null) {
        await repo.createCategory(body);
      } else {
        await repo.updateCategory(widget.category!.id, body);
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
      title: Text(widget.category == null ? 'Add category' : 'Edit category'),
      content: SizedBox(
        width: 380,
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
            AppTextField(
              label: 'Colour',
              controller: _colour,
              errorText: _colourError,
              hint: '#3F3F46',
            ),
            SizedBox(height: t.spacing.md),
            AppTextField(
              label: 'Sort order',
              controller: _sort,
              keyboardType: TextInputType.number,
              errorText: _sortError,
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
          onPressed: _save,
        ),
      ],
    );
  }
}
