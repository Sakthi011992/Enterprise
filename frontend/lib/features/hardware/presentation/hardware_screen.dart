import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session.dart';
import '../../../core/ui/ui.dart';
import '../data/hardware_repository.dart';
import '../domain/printer_rules.dart';

const _printersHeight = 340.0;
const _retestDelay = Duration(seconds: 5);

/// Settings > Hardware. Printers with status and test prints, and which printer
/// takes each station's tickets.
class HardwareScreen extends ConsumerStatefulWidget {
  const HardwareScreen({super.key});

  @override
  ConsumerState<HardwareScreen> createState() => _HardwareScreenState();
}

class _HardwareScreenState extends ConsumerState<HardwareScreen> {
  String? _error;
  List<StationRoute>? _routes;
  bool _routesDirty = false;
  bool _savingRoutes = false;
  final _newStation = TextEditingController();

  @override
  void dispose() {
    _newStation.dispose();
    super.dispose();
  }

  Future<void> _addPrinter() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _PrinterDialog(),
    );
    if (saved == true) {
      ref.invalidate(printersProvider);
      if (mounted) showAppToast(context, 'Printer added');
    }
  }

  Future<void> _editPrinter(Printer printer) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PrinterDialog(printer: printer),
    );
    if (saved == true) {
      ref.invalidate(printersProvider);
      if (mounted) showAppToast(context, 'Printer saved');
    }
  }

  Future<void> _deletePrinter(Printer printer) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove ${printer.name}?',
      message: 'Tickets routed to it fall back to the fallback printer, or stop printing.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(hardwareRepositoryProvider).deletePrinter(printer.id);
      ref.invalidate(printersProvider);
      ref.invalidate(stationRoutesProvider);
    } catch (e) {
      if (mounted) setState(() => _error = ApiError.from(e).message);
    }
  }

  /// Queues a test print and checks the status again after the agent has had time.
  Future<void> _test(Printer printer) async {
    setState(() => _error = null);
    try {
      await ref.read(hardwareRepositoryProvider).testPrinter(printer.id);
      if (mounted) showAppToast(context, 'Test print queued for ${printer.name}');
      Future.delayed(_retestDelay, () {
        if (mounted) ref.invalidate(printersProvider);
      });
    } catch (e) {
      if (mounted) setState(() => _error = ApiError.from(e).message);
    }
  }

  Future<void> _testAll(List<Printer> printers) async {
    for (final p in printers) {
      await _test(p);
    }
  }

  Future<void> _saveRoutes() async {
    final routes = _routes;
    if (routes == null) return;
    setState(() {
      _savingRoutes = true;
      _error = null;
    });
    try {
      await ref.read(hardwareRepositoryProvider).saveStationRoutes(routes);
      ref.invalidate(stationRoutesProvider);
      if (mounted) {
        setState(() => _routesDirty = false);
        showAppToast(context, 'Ticket routing saved');
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiError.from(e).message);
    } finally {
      if (mounted) setState(() => _savingRoutes = false);
    }
  }

  void _addStation() {
    final name = _newStation.text.trim();
    if (name.isEmpty || (_routes ?? const []).any((r) => r.station == name)) return;
    setState(() {
      _routes = [...?_routes, StationRoute(station: name)];
      _routesDirty = true;
      _newStation.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final canEdit = can(ref, Perm.adminSettings, AccessLevel.edit);
    final printers = ref.watch(printersProvider);
    final routes = ref.watch(stationRoutesProvider);
    if (_routes == null && routes.hasValue) _routes = List.of(routes.requireValue);
    final printerList = printers.valueOrNull ?? const <Printer>[];

    final offline = [
      for (final p in printerList)
        if (p.status == PrinterStatus.offline && p.lastError != null) p,
    ];

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: ListView(
          children: [
            PageHeader(
              title: 'Printers, routing & terminals',
              breadcrumb: 'Settings',
              actions: [
                if (canEdit && printerList.isNotEmpty)
                  AppButton(
                    label: 'Test all',
                    icon: Icons.print_outlined,
                    onPressed: () => _testAll(printerList),
                  ),
                if (canEdit)
                  AppButton(
                    label: 'Add printer',
                    icon: Icons.add,
                    variant: AppButtonVariant.primary,
                    onPressed: _addPrinter,
                  ),
              ],
            ),
            if (_error != null) ...[
              SizedBox(height: t.spacing.sm),
              InlineAlert(message: _error!),
            ],
            for (final p in offline) ...[
              SizedBox(height: t.spacing.sm),
              InlineAlert(
                message: "Can't reach this printer: ${p.name}. ${p.lastError}",
                actionLabel: canEdit ? 'Test again' : null,
                onAction: canEdit ? () => _test(p) : null,
              ),
            ],
            SizedBox(height: t.spacing.md),
            AppCard(
              title: 'Printers',
              child: SizedBox(
                height: _printersHeight,
                child: AppDataTable<Printer>(
                  columns: _printerColumns(canEdit),
                  rows: printerList,
                  loading: printers.isLoading && !printers.hasValue,
                  error: printers.hasError && !printers.hasValue
                      ? ApiError.from(printers.error!).message
                      : null,
                  onRetry: () => ref.invalidate(printersProvider),
                  empty: EmptyState(
                    title: 'No printers yet',
                    message: 'Add a counter receipt printer or a kitchen printer.',
                    icon: Icons.print_disabled_outlined,
                    actionLabel: canEdit ? 'Add printer' : null,
                    onAction: canEdit ? _addPrinter : null,
                  ),
                ),
              ),
            ),
            SizedBox(height: t.spacing.md),
            AppCard(
              title: 'Where each station’s tickets go',
              actions: [
                if (canEdit && _routesDirty)
                  AppButton(
                    label: 'Save routing',
                    variant: AppButtonVariant.primary,
                    size: AppControlSize.sm,
                    loading: _savingRoutes,
                    onPressed: _saveRoutes,
                  ),
              ],
              child: _routing(routes, printerList, canEdit),
            ),
          ],
        ),
      ),
    );
  }

  List<AppColumn<Printer>> _printerColumns(bool canEdit) => [
        AppColumn<Printer>(
          label: 'Printer',
          cell: (p) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(p.name, overflow: TextOverflow.ellipsis),
              Text(
                p.host == null ? p.connection : '${p.connection} · ${p.host}${p.port == null ? '' : ':${p.port}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        AppColumn<Printer>(
          label: 'Paper',
          width: 90,
          cell: (p) => Text('${p.paperWidth} mm'),
        ),
        AppColumn<Printer>(
          label: 'Status',
          width: 130,
          cell: (p) {
            final style = printerStatusStyle(p.status);
            return StatusBadge(label: style.$1, tone: style.$2);
          },
        ),
        AppColumn<Printer>(
          label: 'Actions',
          width: canEdit ? 220 : 110,
          cell: (p) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: 'Test',
                size: AppControlSize.sm,
                variant: AppButtonVariant.ghost,
                onPressed: canEdit ? () => _test(p) : null,
              ),
              if (canEdit) ...[
                AppIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit ${p.name}',
                  onPressed: () => _editPrinter(p),
                ),
                AppIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Remove ${p.name}',
                  onPressed: () => _deletePrinter(p),
                ),
              ],
            ],
          ),
        ),
      ];

  Widget _routing(AsyncValue<List<StationRoute>> routes, List<Printer> printers, bool canEdit) {
    final t = context.tokens;
    final draft = _routes;
    if (draft == null) {
      if (routes.hasError) {
        return ErrorState(
          message: ApiError.from(routes.error!).message,
          onRetry: () => ref.invalidate(stationRoutesProvider),
        );
      }
      return DelayedSkeleton(child: SkeletonList(rows: 3));
    }
    final printerIds = {for (final p in printers) p.id};

    String? valueOf(String? id) => id != null && printerIds.contains(id) ? id : null;

    DropdownMenuItem<String?> item(String? id, String label) => DropdownMenuItem<String?>(
          value: id,
          child: Text(label),
        );

    final columns = <AppColumn<StationRoute>>[
      AppColumn<StationRoute>(
        label: 'Station',
        cell: (r) => Text(r.station),
      ),
      AppColumn<StationRoute>(
        label: 'Printer',
        cell: (r) => SizedBox(
          width: 220,
          child: DropdownButton<String?>(
            isExpanded: true,
            value: valueOf(r.printerId),
            items: [
              item(null, 'None'),
              for (final p in printers) item(p.id, p.name),
            ],
            onChanged: canEdit
                ? (v) => _changeRoute(draft.indexOf(r), fallback: false, printerId: v)
                : null,
          ),
        ),
      ),
      AppColumn<StationRoute>(
        label: 'Fallback',
        cell: (r) => SizedBox(
          width: 220,
          child: DropdownButton<String?>(
            isExpanded: true,
            value: valueOf(r.fallbackPrinterId),
            items: [
              item(null, 'None'),
              for (final p in printers) item(p.id, p.name),
            ],
            onChanged: canEdit
                ? (v) => _changeRoute(draft.indexOf(r), fallback: true, printerId: v)
                : null,
          ),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 260,
          child: AppDataTable<StationRoute>(
            columns: columns,
            rows: draft,
            empty: EmptyState(
              title: 'No stations yet',
              message: 'Add a station such as Main bar or Kitchen to route its tickets.',
              icon: Icons.alt_route,
            ),
          ),
        ),
        if (canEdit) ...[
          SizedBox(height: t.spacing.md),
          Row(
            children: [
              Expanded(
                child: AppTextField(label: 'New station', controller: _newStation, hint: 'Main bar'),
              ),
              SizedBox(width: t.spacing.sm),
              AppButton(label: 'Add station', icon: Icons.add, onPressed: _addStation),
            ],
          ),
        ],
      ],
    );
  }

  /// Sets the printer (or the fallback, when [fallback] is true) for one station.
  /// A null [printerId] means "None".
  void _changeRoute(int index, {required bool fallback, required String? printerId}) {
    final routes = _routes;
    if (routes == null || index < 0) return;
    setState(() {
      final r = routes[index];
      routes[index] = StationRoute(
        station: r.station,
        printerId: fallback ? r.printerId : printerId,
        fallbackPrinterId: fallback ? printerId : r.fallbackPrinterId,
      );
      _routesDirty = true;
    });
  }
}

/// Status label and tone for a printer. Returned as a pair to keep the screen short.
(String, StatusTone) printerStatusStyle(String? status) => switch (status) {
      PrinterStatus.ready => ('Ready', StatusTone.success),
      PrinterStatus.paperLow => ('Paper low', StatusTone.warning),
      PrinterStatus.offline => ('Offline', StatusTone.danger),
      _ => ('Unknown', StatusTone.neutral),
    };

class _PrinterDialog extends ConsumerStatefulWidget {
  const _PrinterDialog({this.printer});

  final Printer? printer;

  @override
  ConsumerState<_PrinterDialog> createState() => _PrinterDialogState();
}

class _PrinterDialogState extends ConsumerState<_PrinterDialog> {
  late final _name = TextEditingController(text: widget.printer?.name ?? '');
  late final _host = TextEditingController(text: widget.printer?.host ?? '');
  late final _port = TextEditingController(text: '${widget.printer?.port ?? 9100}');
  late String _connection = widget.printer?.connection ?? 'LAN';
  late int _paper = widget.printer?.paperWidth ?? 80;
  String? _nameError;
  String? _addressError;
  String? _apiError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final isLan = _connection == 'LAN';
    setState(() {
      _apiError = null;
      _nameError = _name.text.trim().isEmpty ? 'Enter a name' : null;
      _addressError = isLan ? lanAddressError(host: _host.text, port: _port.text) : null;
    });
    if (_nameError != null || _addressError != null) return;

    setState(() => _saving = true);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'connection': _connection,
      'paperWidth': _paper,
      if (isLan) 'host': _host.text.trim(),
      if (isLan) 'port': int.parse(_port.text.trim()),
    };
    final repo = ref.read(hardwareRepositoryProvider);
    try {
      if (widget.printer == null) {
        await repo.createPrinter(body);
      } else {
        await repo.updatePrinter(widget.printer!.id, body);
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
    final isLan = _connection == 'LAN';
    return AlertDialog(
      title: Text(widget.printer == null ? 'Add printer' : 'Edit printer'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_apiError != null) ...[
              InlineAlert(message: _apiError!),
              SizedBox(height: t.spacing.sm),
            ],
            AppTextField(label: 'Name', controller: _name, errorText: _nameError, hint: 'Counter receipt'),
            SizedBox(height: t.spacing.md),
            AppSelect<String>(
              label: 'Connection',
              value: _connection,
              items: const [
                AppSelectItem('LAN', 'LAN (IP)'),
                AppSelectItem('USB', 'USB'),
                AppSelectItem('BLUETOOTH', 'Bluetooth'),
              ],
              onChanged: (v) => setState(() => _connection = v ?? _connection),
            ),
            if (isLan) ...[
              SizedBox(height: t.spacing.md),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: AppTextField(
                      label: 'IP address',
                      controller: _host,
                      keyboardType: TextInputType.number,
                      hint: '192.168.1.30',
                      errorText: _addressError,
                    ),
                  ),
                  SizedBox(width: t.spacing.sm),
                  Expanded(
                    flex: 2,
                    child: AppTextField(
                      label: 'Port',
                      controller: _port,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(height: t.spacing.md),
            AppSelect<int>(
              label: 'Paper width',
              value: _paper,
              items: const [AppSelectItem(58, '58 mm'), AppSelectItem(80, '80 mm')],
              onChanged: (v) => setState(() => _paper = v ?? _paper),
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
