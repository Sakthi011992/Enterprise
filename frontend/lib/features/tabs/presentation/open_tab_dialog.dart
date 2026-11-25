import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/api_error.dart';
import '../../../core/auth/permission_keys.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/theme/theme_tokens.dart';
import '../../../core/ui/ui.dart';
import '../../pos/presentation/dialogs/dialog_frame.dart';
import '../../pos/presentation/dialogs/manager_pin_dialog.dart';
import '../../pos/presentation/pos_format.dart';
import '../../pos/presentation/pos_order_controller.dart';
import '../data/tabs_models.dart';
import '../data/tabs_repository.dart';
import '../domain/tab_rules.dart';

/// "Open a new tab" form (BarTabs board). Resolves to the new [TabView], or
/// null when dismissed. The caller opens the tab's order.
Future<TabView?> showOpenTabDialog(
  BuildContext context, {
  String? linkLabel,
  String? tableId,
}) {
  return showDialog<TabView>(
    context: context,
    builder: (_) => _OpenTabDialog(linkLabel: linkLabel, tableId: tableId),
  );
}

/// Edit form for an open tab: guest, mobile, limit, warning point and link.
/// Resolves to the updated [TabView], or null when dismissed.
Future<TabView?> showEditTabDialog(BuildContext context, TabView tab) {
  return showDialog<TabView>(
    context: context,
    builder: (_) => _EditTabDialog(tab: tab),
  );
}

/// Picks the persona's tab limit from the session. Null means no limit.
num? _personaLimitOf(WidgetRef ref) =>
    ref.read(sessionProvider).session?.permissions[Perm.salesTabOpen]?.limit;

class _OpenTabDialog extends ConsumerStatefulWidget {
  const _OpenTabDialog({this.linkLabel, this.tableId});

  final String? linkLabel;
  final String? tableId;

  @override
  ConsumerState<_OpenTabDialog> createState() => _OpenTabDialogState();
}

class _OpenTabDialogState extends ConsumerState<_OpenTabDialog> {
  final _guest = TextEditingController();
  final _mobile = TextEditingController();
  final _card = TextEditingController();
  final _held = TextEditingController();
  final _house = TextEditingController();
  final _limit = TextEditingController(text: '5000');
  final _label = TextEditingController();

  bool _age = false;
  String _security = TabSecurities.cardPreauth;
  String _linkType = TabLinkTypes.barSeat;
  String? _tableId;
  int _warnAt = 80;
  Map<String, String> _errors = const {};
  String? _serverError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _label.text = widget.linkLabel ?? '';
    if (widget.tableId != null) {
      _linkType = TabLinkTypes.table;
      _tableId = widget.tableId;
    }
  }

  @override
  void dispose() {
    for (final c in [_guest, _mobile, _card, _held, _house, _limit, _label]) {
      c.dispose();
    }
    super.dispose();
  }

  OpenTabDraft _draft() => OpenTabDraft(
        guestName: _guest.text,
        mobile: _mobile.text,
        ageChecked: _age,
        security: _security,
        cardLast4: _card.text,
        amountHeld: _held.text,
        houseAccount: _house.text,
        tabLimit: _limit.text,
        linkType: _linkType,
        linkLabel: _label.text,
        tableId: _tableId,
      );

  Future<void> _submit() async {
    final draft = _draft();
    final persona = _personaLimitOf(ref);
    final errors = validateOpenTab(draft, personaLimit: persona);
    setState(() {
      _errors = errors;
      _serverError = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _busy = true);
    try {
      String? approvalId;
      final name = _guest.text.trim();
      if (_security == TabSecurities.none) {
        final approval = await showManagerPinDialog(
          context,
          type: tabNoSecurityApprovalType,
          payload: {
            'guestName': name,
            'tabLimit': wireMoney(parseRupeeInput(_limit.text)),
          },
          reason: 'Open a tab with no security for $name',
        );
        if (approval == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        approvalId = approval.id;
      }

      final held = parseRupeeInput(_held.text);
      final mobile = _mobile.text.trim();
      final label = _label.text.trim();
      final tab = await ref.read(tabsRepositoryProvider).openTab(
            OpenTabRequest(
              guestName: name,
              mobile: mobile.isEmpty ? null : mobile,
              ageChecked: _age,
              security: _security,
              cardLast4: _security == TabSecurities.cardPreauth ? _card.text.trim() : null,
              amountHeld: _security == TabSecurities.houseAccount || held <= 0
                  ? null
                  : wireMoney(held),
              houseAccount: _security == TabSecurities.houseAccount ? _house.text.trim() : null,
              tabLimit: wireMoney(parseRupeeInput(_limit.text)),
              warnAtPercent: _warnAt,
              linkType: _linkType,
              linkLabel: label.isEmpty ? null : label,
              tableId: _linkType == TabLinkTypes.table ? _tableId : null,
              approvalId: approvalId,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(tab);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _serverError = tabErrorMessage(ApiError.from(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final persona = _personaLimitOf(ref);
    final limitNow = parseRupeeInput(_limit.text);
    final liveLimitError = persona != null && limitNow > persona
        ? personaLimitWarning(limitNow, persona)
        : null;

    return PosDialogFrame(
      title: 'Open a new tab',
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Open tab',
          variant: AppButtonVariant.primary,
          loading: _busy,
          onPressed: _busy ? null : _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_serverError != null) ...[
            InlineAlert(message: _serverError!),
            SizedBox(height: t.spacing.sm),
          ],
          AppTextField(
            label: 'Guest name',
            controller: _guest,
            autofocus: true,
            errorText: _errors[TabField.guestName],
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: t.spacing.sm),
          AppTextField(
            label: 'Mobile',
            controller: _mobile,
            keyboardType: TextInputType.phone,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _age,
            onChanged: _busy ? null : (v) => setState(() => _age = v ?? false),
            title: const Text('Age checked (ID seen, 21+)'),
            subtitle: _errors[TabField.ageChecked] == null
                ? null
                : Text(
                    _errors[TabField.ageChecked]!,
                    style: TextStyle(color: t.color.content.danger),
                  ),
          ),
          SizedBox(height: t.spacing.sm),
          Text('Security', style: Theme.of(context).textTheme.labelLarge),
          SizedBox(height: t.spacing.xs),
          Wrap(
            spacing: t.spacing.sm,
            runSpacing: t.spacing.sm,
            children: [
              for (final entry in const [
                (TabSecurities.cardPreauth, 'Card pre-authorisation'),
                (TabSecurities.cashDeposit, 'Cash deposit'),
                (TabSecurities.houseAccount, 'House account'),
                (TabSecurities.none, 'None (manager approval)'),
              ])
                PosChoiceChip(
                  label: entry.$2,
                  selected: _security == entry.$1,
                  onTap: _busy ? null : () => setState(() => _security = entry.$1),
                ),
            ],
          ),
          SizedBox(height: t.spacing.sm),
          ..._securityFields(t),
          AppTextField(
            label: 'Tab limit',
            controller: _limit,
            keyboardType: TextInputType.number,
            errorText: _errors[TabField.tabLimit] ?? liveLimitError,
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: t.spacing.sm),
          Text('Warn at', style: Theme.of(context).textTheme.labelLarge),
          SizedBox(height: t.spacing.xs),
          Wrap(
            spacing: t.spacing.sm,
            children: [
              for (final pct in const [80, 90])
                PosChoiceChip(
                  label: '$pct% of limit',
                  selected: _warnAt == pct,
                  onTap: _busy ? null : () => setState(() => _warnAt = pct),
                ),
            ],
          ),
          SizedBox(height: t.spacing.md),
          TabLinkFields(
            linkType: _linkType,
            onLinkType: _busy ? null : (v) => setState(() => _linkType = v),
            labelController: _label,
            tableId: _tableId,
            onTableId: (v) => setState(() => _tableId = v),
            tableError: _errors[TabField.tableId],
          ),
        ],
      ),
    );
  }

  List<Widget> _securityFields(ThemeTokens t) {
    switch (_security) {
      case TabSecurities.cardPreauth:
        return [
          AppTextField(
            label: 'Card last 4 digits',
            controller: _card,
            keyboardType: TextInputType.number,
            errorText: _errors[TabField.cardLast4],
          ),
          SizedBox(height: t.spacing.sm),
          AppTextField(
            label: 'Amount held',
            controller: _held,
            keyboardType: TextInputType.number,
            hint: '5000',
            errorText: _errors[TabField.amountHeld],
          ),
          SizedBox(height: t.spacing.sm),
        ];
      case TabSecurities.cashDeposit:
        return [
          AppTextField(
            label: 'Deposit amount',
            controller: _held,
            keyboardType: TextInputType.number,
            errorText: _errors[TabField.amountHeld],
          ),
          SizedBox(height: t.spacing.sm),
        ];
      case TabSecurities.houseAccount:
        return [
          AppTextField(
            label: 'House account',
            controller: _house,
            hint: 'Corporate: Acme',
            errorText: _errors[TabField.houseAccount],
          ),
          SizedBox(height: t.spacing.sm),
        ];
      default:
        return [
          Padding(
            padding: EdgeInsets.only(bottom: t.spacing.sm),
            child: Text(
              'A manager approves this with their PIN before the tab opens.',
              style: TextStyle(color: t.color.content.secondary),
            ),
          ),
        ];
    }
  }
}

/// Edit an open tab. PUT /tabs/:id with the form values.
class _EditTabDialog extends ConsumerStatefulWidget {
  const _EditTabDialog({required this.tab});

  final TabView tab;

  @override
  ConsumerState<_EditTabDialog> createState() => _EditTabDialogState();
}

class _EditTabDialogState extends ConsumerState<_EditTabDialog> {
  late final _guest = TextEditingController(text: widget.tab.guestName);
  late final _mobile = TextEditingController(text: widget.tab.mobile ?? '');
  late final _limit = TextEditingController(text: widget.tab.tabLimit);
  late final _label = TextEditingController(text: widget.tab.linkLabel ?? '');
  late String _linkType = widget.tab.linkType;
  late String? _tableId = widget.tab.table?.id;
  late int _warnAt = widget.tab.warnAtPercent;
  String? _limitError;
  String? _serverError;
  String? _guestError;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_guest, _mobile, _limit, _label]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final limit = parseRupeeInput(_limit.text);
    final persona = _personaLimitOf(ref);
    setState(() {
      _guestError = _guest.text.trim().isEmpty ? 'Enter the guest name.' : null;
      _limitError = limit <= 0
          ? 'Enter a tab limit above ₹0.'
          : (persona != null && limit > persona ? personaLimitWarning(limit, persona) : null);
      _serverError = null;
    });
    if (_guestError != null || _limitError != null) return;

    setState(() => _busy = true);
    try {
      final mobile = _mobile.text.trim();
      final label = _label.text.trim();
      final onTable = widget.tab.linkType == TabLinkTypes.table;
      final updated = await ref.read(tabsRepositoryProvider).updateTab(
            widget.tab.id,
            TabEditRequest(
              guestName: _guest.text.trim(),
              mobile: mobile.isEmpty ? null : mobile,
              // Only a changed limit is sent: the server re-checks it against the persona limit.
              tabLimit: limit != widget.tab.tabLimitValue ? wireMoney(limit) : null,
              warnAtPercent: _warnAt,
              // A tab on a table keeps its link (use Move to table); edits never send a table.
              linkType: onTable || _linkType == TabLinkTypes.table || _linkType == widget.tab.linkType
                  ? null
                  : _linkType,
              linkLabel: onTable || label == (widget.tab.linkLabel ?? '') ? null : label,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _serverError = tabErrorMessage(ApiError.from(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PosDialogFrame(
      title: 'Edit tab ${widget.tab.number}',
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Save',
          variant: AppButtonVariant.primary,
          loading: _busy,
          onPressed: _busy ? null : _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_serverError != null) ...[
            InlineAlert(message: _serverError!),
            SizedBox(height: t.spacing.sm),
          ],
          AppTextField(label: 'Guest name', controller: _guest, errorText: _guestError),
          SizedBox(height: t.spacing.sm),
          AppTextField(label: 'Mobile', controller: _mobile, keyboardType: TextInputType.phone),
          SizedBox(height: t.spacing.sm),
          AppTextField(
            label: 'Tab limit',
            controller: _limit,
            keyboardType: TextInputType.number,
            errorText: _limitError,
          ),
          SizedBox(height: t.spacing.sm),
          Text('Warn at', style: Theme.of(context).textTheme.labelLarge),
          SizedBox(height: t.spacing.xs),
          Wrap(
            spacing: t.spacing.sm,
            children: [
              for (final pct in const [80, 90])
                PosChoiceChip(
                  label: '$pct% of limit',
                  selected: _warnAt == pct,
                  onTap: _busy ? null : () => setState(() => _warnAt = pct),
                ),
            ],
          ),
          SizedBox(height: t.spacing.md),
          TabLinkFields(
            linkType: _linkType,
            onLinkType: _busy ? null : (v) => setState(() => _linkType = v),
            labelController: _label,
            tableId: _tableId,
            onTableId: (v) => setState(() => _tableId = v),
          ),
        ],
      ),
    );
  }
}

/// "Link to" section shared by the open and edit forms: link type chips, a
/// label, and a table picker when the link is a table.
class TabLinkFields extends ConsumerWidget {
  const TabLinkFields({
    super.key,
    required this.linkType,
    required this.onLinkType,
    required this.labelController,
    required this.tableId,
    required this.onTableId,
    this.tableError,
  });

  final String linkType;
  final ValueChanged<String>? onLinkType;
  final TextEditingController labelController;
  final String? tableId;
  final ValueChanged<String?> onTableId;
  final String? tableError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final tables = ref.watch(posTablesProvider).valueOrNull ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Link to', style: Theme.of(context).textTheme.labelLarge),
        SizedBox(height: t.spacing.xs),
        Wrap(
          spacing: t.spacing.sm,
          runSpacing: t.spacing.sm,
          children: [
            for (final type in const [
              TabLinkTypes.barSeat,
              TabLinkTypes.table,
              TabLinkTypes.queueToken,
            ])
              PosChoiceChip(
                label: linkTypeLabel(type),
                selected: linkType == type,
                onTap: onLinkType == null ? null : () => onLinkType!(type),
              ),
          ],
        ),
        SizedBox(height: t.spacing.sm),
        if (linkType == TabLinkTypes.table)
          AppSelect<String?>(
            label: 'Table',
            value: tableId,
            errorText: tableError,
            items: [for (final table in tables) AppSelectItem<String?>(table.id, table.name)],
            onChanged: onTableId,
          )
        else
          AppTextField(
            label: linkType == TabLinkTypes.queueToken ? 'Queue token' : 'Seat label',
            controller: labelController,
            hint: linkType == TabLinkTypes.queueToken ? 'Queue W-009' : 'Bar seat 3',
          ),
      ],
    );
  }
}
