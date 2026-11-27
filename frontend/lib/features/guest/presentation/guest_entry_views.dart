import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ui/ui.dart';
import '../../pos/presentation/pos_format.dart';
import '../application/guest_controller.dart';
import '../data/guest_models.dart';
import 'guest_menu.dart';
import 'guest_widgets.dart';

/// Phone: header plus a padded body. Tablet and desktop: the header, then the
/// body as a centred card over the page (design "centred card").
class EntryFrame extends StatelessWidget {
  const EntryFrame({super.key, required this.header, required this.child, required this.wide});

  final Widget header;
  final Widget child;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    if (!wide) {
      return Column(children: [
        header,
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - 28),
                child: IntrinsicHeight(child: child),
              ),
            ),
          ),
        ),
      ]);
    }
    return Column(children: [
      header,
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
          child: Center(
            child: ConstrainedBox(
              key: const Key('guest-centred-card'),
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: p.card,
                  border: Border.all(color: p.line),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: p.ext.raisedShadow,
                ),
                child: IntrinsicHeight(child: child),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Screen 1: Welcome.
class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key, required this.state, required this.controller});

  final GuestState state;
  final GuestController controller;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final info = state.info!;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 150,
        padding: const EdgeInsets.all(14),
        alignment: Alignment.bottomLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.55, 1],
            colors: [
              p.t.color.background.inverse,
              p.header,
              Color.lerp(p.header, p.accent, 0.45)!,
            ],
          ),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(greeting, style: p.display(24, color: p.onHeader)),
          Text('Order from your table. Your food comes to ${info.tableName}.',
              style: p.body(12, color: p.onHeader.withValues(alpha: 0.85))),
        ]),
      ),
      const SizedBox(height: 12),
      GuestButton(
        key: const Key('guest-see-menu'),
        kind: GuestButtonKind.primary,
        label: 'See menu & order',
        onPressed: () => controller.begin(),
      ),
      const SizedBox(height: 12),
      GuestButton(
        icon: Icons.notifications_none,
        label: 'Call a waiter',
        onPressed: state.joined ? controller.callWaiter : () => controller.begin(),
      ),
      const SizedBox(height: 12),
      GuestButton(
        icon: Icons.receipt_long_outlined,
        label: 'View bill',
        onPressed: () => controller.begin(page: GuestPage.bill),
      ),
      const SizedBox(height: 12),
      if (info.settings.ageGate)
        GuestNote(
            'Alcohol is served only to guests ${info.settings.minAge} and over. Staff may check ID at your table.'),
      if (state.error != null) ...[
        const SizedBox(height: 12),
        GuestNote(state.error!, tone: GuestNoteTone.error),
      ],
    ]);
  }
}

/// "Table not seated yet": read-only menu (Q-4).
class NotSeatedView extends StatefulWidget {
  const NotSeatedView({super.key, required this.state, required this.wide});

  final GuestState state;
  final bool wide;

  @override
  State<NotSeatedView> createState() => _NotSeatedViewState();
}

class _NotSeatedViewState extends State<NotSeatedView> {
  String? _tab;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final menu = widget.state.menu ?? const GuestMenu();
    final tab = _tab ?? defaultTab(menu);
    final products = productsFor(menu, tab, _query);
    return ListView(padding: const EdgeInsets.all(14), children: [
      const GuestNote('You can look at the menu now.',
          title: 'Ask staff to seat you to start ordering.', tone: GuestNoteTone.info),
      const SizedBox(height: 12),
      if (widget.wide) ...[
        MenuSearchField(onChanged: (q) => setState(() => _query = q)),
        const SizedBox(height: 12),
      ],
      CategoryTabs(menu: menu, selected: tab, onSelect: (id) => setState(() => _tab = id)),
      const SizedBox(height: 12),
      if (widget.wide)
        MenuGrid(products: products, controlFor: (_) => null)
      else
        GuestCard(
          child: Column(children: [
            for (var i = 0; i < products.length; i++)
              MenuRow(product: products[i], last: i == products.length - 1),
          ]),
        ),
    ]);
  }
}

/// Screen 2: Your details.
class DetailsView extends StatefulWidget {
  const DetailsView({super.key, required this.state, required this.controller});

  final GuestState state;
  final GuestController controller;

  @override
  State<DetailsView> createState() => _DetailsViewState();
}

class _DetailsViewState extends State<DetailsView> {
  late final _name = TextEditingController(text: widget.state.name);
  late final _phone = TextEditingController(text: formatPhone(widget.state.phone));
  bool _consent = false;
  bool _busy = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final errors = await widget.controller.submitDetails(
      name: _name.text,
      phone: _phone.text,
      consent: _consent,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errors = errors;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text("Who's ordering?", style: p.display(22)),
      const SizedBox(height: 6),
      Text('Your name shows on your items so the table knows whose is whose.',
          style: p.body(12, color: p.ink2)),
      const SizedBox(height: 12),
      AppTextField(
        key: const Key('guest-name'),
        label: 'Your name',
        controller: _name,
        hint: 'Deepa',
        errorText: _errors['name'],
        autofillHints: const [AutofillHints.givenName],
      ),
      const SizedBox(height: 12),
      AppTextField(
        key: const Key('guest-phone'),
        label: 'Mobile number',
        controller: _phone,
        hint: '98765 43210',
        keyboardType: TextInputType.phone,
        errorText: _errors['phone'],
        autofillHints: const [AutofillHints.telephoneNumberNational],
        prefix: Padding(
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Container(
            padding: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(border: Border(right: BorderSide(color: p.line))),
            child: Text('+91', style: p.body(14, color: p.ink2)),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Semantics(
        checked: _consent,
        child: InkWell(
          key: const Key('guest-consent'),
          onTap: () => setState(() => _consent = !_consent),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _consent,
                onChanged: (v) => setState(() => _consent = v ?? false),
                activeColor: p.accent,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text('Use my number for this order and updates. We delete it after 90 days.',
                  style: p.body(12, color: p.ink2)),
            ),
          ]),
        ),
      ),
      if (_errors['consent'] != null) ...[
        const SizedBox(height: 8),
        GuestNote(_errors['consent']!, tone: GuestNoteTone.error),
      ],
      if (widget.state.error != null) ...[
        const SizedBox(height: 8),
        GuestNote(widget.state.error!, tone: GuestNoteTone.error),
      ],
      const Spacer(),
      const SizedBox(height: 16),
      GuestButton(
        key: const Key('guest-details-continue'),
        kind: GuestButtonKind.primary,
        label: 'Continue',
        loading: _busy,
        onPressed: _submit,
      ),
    ]);
  }
}

/// Screen 3: Enter the code (6-digit static OTP or 4-digit table PIN).
class CodeView extends StatefulWidget {
  const CodeView({super.key, required this.state, required this.controller});

  final GuestState state;
  final GuestController controller;

  @override
  State<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends State<CodeView> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(CodeView old) {
    super.didUpdateWidget(old);
    _syncTimer();
  }

  void _syncTimer() {
    final lock = widget.state.codeError?.lockedUntil;
    final locked = lock != null && DateTime.now().isBefore(lock);
    if (locked && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final until = widget.state.codeError?.lockedUntil;
        if (until == null || !DateTime.now().isBefore(until)) {
          _tick?.cancel();
          _tick = null;
        }
        setState(() {});
      });
    } else if (!locked) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  int get _length => widget.state.verification?.codeLength ?? widget.state.settings.codeLength;

  Future<void> _submit() async {
    if (_busy || _code.text.length != _length) return;
    setState(() => _busy = true);
    await widget.controller.submitCode(_code.text);
    if (!mounted) return;
    setState(() => _busy = false);
    _syncTimer();
  }

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final method = widget.state.verification?.method ?? widget.state.settings.method;
    final pin = method == GuestVerifyMethod.tablePin;
    final err = widget.state.codeError;
    final lock = err?.lockedUntil;
    final remaining = lock?.difference(DateTime.now());
    final locked = remaining != null && !remaining.isNegative && remaining.inSeconds > 0;
    final wrong = err?.attemptsLeft != null;
    final value = _code.text;

    String? message;
    if (locked) {
      final m = remaining.inMinutes;
      final s = (remaining.inSeconds % 60).toString().padLeft(2, '0');
      message = 'Too many wrong tries. Try again in $m:$s';
    } else if (err?.expired == true) {
      message = 'This code has expired. Ask for a new one.';
    } else if (wrong) {
      final left = err!.attemptsLeft!;
      message = "That code doesn't match · $left ${left == 1 ? 'try' : 'tries'} left";
    } else if (err?.message != null) {
      message = err!.message;
    }

    final boxW = pin ? 44.0 : 36.0;
    final boxH = pin ? 52.0 : 46.0;
    final showError = wrong || locked;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Enter the code', style: p.display(22)),
      const SizedBox(height: 6),
      Text(pin ? "Ask your server for this table's 4-digit PIN" : "Ask your server for today's code.",
          style: p.body(12, color: p.ink2)),
      const SizedBox(height: 12),
      Stack(alignment: Alignment.center, children: [
        GestureDetector(
          onTap: () => _focus.requestFocus(),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _length; i++) ...[
              if (i > 0) const SizedBox(width: 7),
              Container(
                key: Key('guest-code-box-$i'),
                width: boxW,
                height: boxH,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: showError ? p.ext.dangerSubtle : p.card,
                  border: Border.all(
                    color: showError
                        ? p.ext.dangerBorder
                        : (i == value.length && _focus.hasFocus ? p.accent : p.line),
                    width: i == value.length && _focus.hasFocus && !showError ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(i < value.length ? value[i] : '', style: p.mono(pin ? 20 : 18)),
              ),
            ],
          ]),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              key: const Key('guest-code-input'),
              controller: _code,
              focusNode: _focus,
              autofocus: true,
              enabled: !locked,
              keyboardType: TextInputType.number,
              maxLength: _length,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(counterText: '', border: InputBorder.none),
            ),
          ),
        ),
      ]),
      if (message != null) ...[
        const SizedBox(height: 12),
        GuestNote(message, tone: GuestNoteTone.error),
      ],
      if (err?.expired == true) ...[
        const SizedBox(height: 12),
        GuestButton(label: 'Get a new code', onPressed: widget.controller.restartVerification),
      ],
      const Spacer(),
      const SizedBox(height: 16),
      GuestButton(
        key: const Key('guest-join-table'),
        kind: value.length == _length && !locked ? GuestButtonKind.primary : GuestButtonKind.off,
        label: 'Join table',
        loading: _busy,
        onPressed: value.length == _length && !locked ? _submit : null,
      ),
    ]);
  }
}

/// Screen 8: Paid · thank you, or a link whose session has ended.
class EndedView extends StatelessWidget {
  const EndedView({super.key, required this.state});

  final GuestState state;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final paid = state.endedPaid;
    final name = state.guest?.name ?? (state.name.isEmpty ? null : state.name);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: p.ext.successSubtle, shape: BoxShape.circle),
              child: Icon(paid != null ? Icons.check : Icons.qr_code_2, size: 30, color: p.ext.onSuccessSubtle),
            ),
            const SizedBox(height: 10),
            Text(
              paid != null ? 'Paid · thank you${name == null ? '' : ', $name'}' : 'Thank you for visiting',
              textAlign: TextAlign.center,
              style: p.display(22),
            ),
            if (paid != null && paid > 0) ...[
              const SizedBox(height: 10),
              Text('${formatRupees(paid)} paid', style: p.body(13, color: p.ink2)),
            ],
          ]),
        ),
      ),
      const GuestNote("This table's session has ended. Scan again on your next visit.",
          tone: GuestNoteTone.info, center: true),
    ]);
  }
}
