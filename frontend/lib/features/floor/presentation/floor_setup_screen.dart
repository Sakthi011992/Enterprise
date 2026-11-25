import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/ui/ui.dart';
import '../data/floor_repository.dart';

/// Grid of cells the floor plan snaps to. posX/posY are cell indices.
const _cols = 12;
const _rows = 8;
const _cell = 72.0;
const _tileSize = 64.0;
const _areasWidth = 240.0;

const _shapes = [
  AppSelectItem('SQUARE', 'Square'),
  AppSelectItem('ROUND', 'Round'),
  AppSelectItem('RECT', 'Rectangle'),
];

/// Result of the table dialog: a save body, or a delete request.
typedef _TableDialogResult = ({bool delete, Map<String, dynamic> body});

/// Settings > Floor setup. Manage areas and tables; drag tables on the grid to
/// place them. A drop snaps to the nearest cell and is saved straight away.
class FloorSetupScreen extends ConsumerStatefulWidget {
  const FloorSetupScreen({super.key});

  @override
  ConsumerState<FloorSetupScreen> createState() => _FloorSetupScreenState();
}

class _FloorSetupScreenState extends ConsumerState<FloorSetupScreen> {
  String? _areaId;
  String? _error;

  /// Pixel positions of tables being dragged, keyed by table id.
  final Map<String, Offset> _drag = {};

  void _report(Object e) {
    if (mounted) setState(() => _error = ApiError.from(e).message);
  }

  Future<void> _addArea() async {
    final name = await _askName(title: 'Add area', initial: '');
    if (name == null) return;
    try {
      final area = await ref.read(floorRepositoryProvider).createArea(name);
      ref.invalidate(floorAreasProvider);
      if (mounted) setState(() => _areaId = area.id);
    } catch (e) {
      _report(e);
    }
  }

  Future<void> _renameArea(FloorArea area) async {
    final name = await _askName(title: 'Rename area', initial: area.name);
    if (name == null) return;
    try {
      await ref.read(floorRepositoryProvider).renameArea(area.id, name);
      ref.invalidate(floorAreasProvider);
    } catch (e) {
      _report(e);
    }
  }

  Future<void> _deleteArea(FloorArea area) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${area.name}?',
      message: 'Its tables must be removed first.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(floorRepositoryProvider).deleteArea(area.id);
      ref.invalidate(floorAreasProvider);
      if (mounted && _areaId == area.id) setState(() => _areaId = null);
    } catch (e) {
      _report(e);
    }
  }

  Future<void> _addTable(FloorArea area) async {
    final result = await showDialog<_TableDialogResult>(
      context: context,
      builder: (_) => _TableDialog(areaId: area.id),
    );
    if (result == null || result.delete) return;
    try {
      await ref.read(floorRepositoryProvider).createTable({...result.body, 'posX': 0, 'posY': 0});
      ref.invalidate(floorTablesProvider);
    } catch (e) {
      _report(e);
    }
  }

  Future<void> _editTable(FloorTable table) async {
    final result = await showDialog<_TableDialogResult>(
      context: context,
      builder: (_) => _TableDialog(table: table, areaId: table.areaId),
    );
    if (result == null) return;
    try {
      final repo = ref.read(floorRepositoryProvider);
      if (result.delete) {
        final ok = await showConfirmDialog(
          context,
          title: 'Delete ${table.name}?',
          message: 'Past orders keep their table name.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (!ok) return;
        await repo.deleteTable(table.id);
      } else {
        await repo.updateTable(table.id, result.body);
      }
      ref.invalidate(floorTablesProvider);
    } catch (e) {
      _report(e);
    }
  }

  /// Saves the snapped position of a dragged table.
  Future<void> _commitDrag(FloorTable table) async {
    final at = _drag[table.id];
    if (at == null) return;
    final x = (at.dx / _cell).round().clamp(0, _cols - 1).toInt();
    final y = (at.dy / _cell).round().clamp(0, _rows - 1).toInt();
    setState(() => _drag[table.id] = Offset(x * _cell, y * _cell));
    try {
      await ref.read(floorRepositoryProvider).updateTable(table.id, {'posX': x, 'posY': y});
    } catch (e) {
      _report(e);
    }
    if (!mounted) return;
    setState(() => _drag.remove(table.id));
    ref.invalidate(floorTablesProvider);
  }

  Future<String?> _askName({required String title, required String initial}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(title: title, initial: initial),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final areas = ref.watch(floorAreasProvider);
    final tables = ref.watch(floorTablesProvider);

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Floor setup',
              breadcrumb: 'Settings',
              actions: [
                AppButton(
                  label: 'Add area',
                  icon: Icons.add,
                  onPressed: _addArea,
                ),
              ],
            ),
            if (_error != null) ...[
              SizedBox(height: t.spacing.sm),
              InlineAlert(message: _error!),
            ],
            SizedBox(height: t.spacing.md),
            Expanded(
              child: areas.when(
                skipLoadingOnReload: true,
                loading: () => DelayedSkeleton(child: SkeletonList()),
                error: (e, _) => ErrorState(
                  message: ApiError.from(e).message,
                  onRetry: () => ref.invalidate(floorAreasProvider),
                ),
                data: (areaList) => tables.when(
                  skipLoadingOnReload: true,
                  loading: () => DelayedSkeleton(child: SkeletonList()),
                  error: (e, _) => ErrorState(
                    message: ApiError.from(e).message,
                    onRetry: () => ref.invalidate(floorTablesProvider),
                  ),
                  data: (tableList) => _content(areaList, tableList),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(List<FloorArea> areas, List<FloorTable> tables) {
    final t = context.tokens;
    if (areas.isEmpty) {
      return EmptyState(
        title: 'No areas yet',
        message: 'Add an area such as Indoor or Rooftop, then place its tables.',
        icon: Icons.map_outlined,
        actionLabel: 'Add area',
        onAction: _addArea,
      );
    }
    final area = _areaById(areas, _areaId) ?? areas.first;
    final inArea = [
      for (final table in tables)
        if (table.areaId == area.id) table,
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _areasWidth,
          child: AppCard(
            title: 'Areas',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final a in areas)
                  InkWell(
                    onTap: () => setState(() => _areaId = a.id),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: t.spacing.sm, vertical: t.spacing.xs),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(t.radius.sm),
                        color: a.id == area.id ? t.color.background.surface : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              a.name,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: a.id == area.id ? FontWeight.w600 : FontWeight.w400,
                                  ),
                            ),
                          ),
                          AppIconButton(
                            icon: Icons.edit_outlined,
                            tooltip: 'Rename ${a.name}',
                            onPressed: () => _renameArea(a),
                          ),
                          AppIconButton(
                            icon: Icons.delete_outline,
                            tooltip: 'Delete ${a.name}',
                            onPressed: () => _deleteArea(a),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(width: t.spacing.md),
        Expanded(
          child: AppCard(
            title: 'Layout · ${area.name} (${inArea.length} tables)',
            actions: [
              AppButton(
                label: 'Add table',
                icon: Icons.add,
                variant: AppButtonVariant.primary,
                size: AppControlSize.sm,
                onPressed: () => _addTable(area),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Drag a table to move it. Tap a table to edit it.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(height: t.spacing.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: _canvas(inArea),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _canvas(List<FloorTable> tables) {
    final t = context.tokens;
    return Container(
      width: _cols * _cell,
      height: _rows * _cell,
      decoration: BoxDecoration(
        color: t.color.background.surface,
        borderRadius: BorderRadius.circular(t.radius.md),
        border: Border.all(color: t.color.border.subtle, width: t.borderWidth.hairline),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(color: t.color.border.subtle, cell: _cell),
            ),
          ),
          for (final table in tables) _positioned(table),
        ],
      ),
    );
  }

  Widget _positioned(FloorTable table) {
    final base = Offset(table.posX * _cell + 4, table.posY * _cell + 4);
    final at = _drag[table.id] ?? base;
    return Positioned(
      left: at.dx,
      top: at.dy,
      child: GestureDetector(
        onTap: () => _editTable(table),
        onPanUpdate: (d) => setState(() => _drag[table.id] = (_drag[table.id] ?? base) + d.delta),
        onPanEnd: (_) => _commitDrag(table),
        child: _SetupTile(table: table),
      ),
    );
  }
}

FloorArea? _areaById(List<FloorArea> areas, String? id) {
  if (id == null) return null;
  for (final area in areas) {
    if (area.id == id) return area;
  }
  return null;
}

class _SetupTile extends StatelessWidget {
  const _SetupTile({required this.table});

  final FloorTable table;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final round = table.shape == 'ROUND';
    return Semantics(
      button: true,
      label: '${table.name}, ${table.seats} seats',
      child: Container(
        width: _tileSize,
        height: _tileSize,
        padding: EdgeInsets.all(t.spacing.xs),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.color.background.raised,
          shape: round ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: round ? null : BorderRadius.circular(t.radius.md),
          border: Border.all(color: t.color.border.strong, width: t.borderWidth.hairline),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              table.name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text('${table.seats} seats', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.color, required this.cell});

  final Color color;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color || old.cell != cell;
}

/// Add or edit a table. Pops a [_TableDialogResult].
class _TableDialog extends StatefulWidget {
  const _TableDialog({this.table, required this.areaId});

  final FloorTable? table;
  final String areaId;

  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  late final _name = TextEditingController(text: widget.table?.name ?? '');
  late final _seats = TextEditingController(text: '${widget.table?.seats ?? 4}');
  late String _shape = widget.table?.shape ?? 'SQUARE';
  String? _nameError;
  String? _seatsError;

  @override
  void dispose() {
    _name.dispose();
    _seats.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final seats = int.tryParse(_seats.text.trim());
    setState(() {
      _nameError = name.isEmpty ? 'Enter a table name' : null;
      _seatsError = (seats == null || seats < 1 || seats > 50) ? 'Enter 1 to 50 seats' : null;
    });
    if (_nameError != null || _seatsError != null) return;
    Navigator.of(context).pop<_TableDialogResult>((
      delete: false,
      body: <String, dynamic>{'name': name, 'areaId': widget.areaId, 'seats': seats, 'shape': _shape},
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.table != null;
    return AlertDialog(
      title: Text(editing ? 'Edit table' : 'Add table'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(label: 'Name', controller: _name, errorText: _nameError, autofocus: true),
            SizedBox(height: context.tokens.spacing.md),
            AppTextField(
              label: 'Seats',
              controller: _seats,
              keyboardType: TextInputType.number,
              errorText: _seatsError,
            ),
            SizedBox(height: context.tokens.spacing.md),
            AppSelect<String>(
              label: 'Shape',
              value: _shape,
              items: _shapes,
              onChanged: (v) => setState(() => _shape = v ?? _shape),
            ),
          ],
        ),
      ),
      actions: [
        if (editing)
          AppButton(
            label: 'Delete',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop<_TableDialogResult>((
              delete: true,
              body: <String, dynamic>{},
            )),
          ),
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(label: 'Save', variant: AppButtonVariant.primary, onPressed: _save),
      ],
    );
  }
}

/// Single text value dialog, used for area names. Pops the trimmed name.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    Navigator.of(context).pop<String>(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: AppTextField(
          label: 'Name',
          controller: _controller,
          errorText: _error,
          autofocus: true,
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(label: 'Save', variant: AppButtonVariant.primary, onPressed: _save),
      ],
    );
  }
}
