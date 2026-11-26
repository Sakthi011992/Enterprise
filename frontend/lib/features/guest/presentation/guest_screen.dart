import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/ui.dart';
import '../../pos/presentation/pos_format.dart';
import '../application/guest_controller.dart';
import '../data/guest_models.dart';
import 'guest_entry_views.dart';
import 'guest_menu.dart';
import 'guest_order_views.dart';
import 'guest_theme.dart';
import 'guest_widgets.dart';

/// Width breakpoints (design "Guest screens on desktop and tablet").
enum GuestLayout { phone, tablet, desktop }

GuestLayout guestLayoutFor(double width) => width < 600
    ? GuestLayout.phone
    : (width < 1024 ? GuestLayout.tablet : GuestLayout.desktop);

/// Public guest app at `/t/:qrToken`, outside the staff shell. Light only.
class GuestScreen extends StatelessWidget {
  const GuestScreen({super.key, required this.qrToken});

  final String qrToken;

  @override
  Widget build(BuildContext context) => GuestThemeScope(child: _GuestBody(qrToken: qrToken));
}

class _GuestBody extends ConsumerWidget {
  const _GuestBody({required this.qrToken});

  final String qrToken;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = guestControllerProvider(qrToken);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    ref.listen<String?>(provider.select((s) => s.message), (_, next) {
      if (next != null) {
        showAppToast(context, next);
        controller.clearMessage();
      }
    });
    final p = GuestPalette(context);
    return Scaffold(
      backgroundColor: p.canvas,
      body: LayoutBuilder(builder: (context, c) {
        final layout = guestLayoutFor(c.maxWidth);
        return _stage(context, state, controller, layout);
      }),
    );
  }

  Widget _stage(BuildContext context, GuestState state, GuestController controller, GuestLayout layout) {
    final wide = layout != GuestLayout.phone;
    final info = state.info;
    final outlet = info?.outletName ?? '';
    final logo = outletInitials(outlet);
    Widget welcomeHeader() => GuestHeader(
          title: outlet,
          subtitle: info?.tableLine,
          trailing: const HeaderChip('EN'),
        );

    switch (state.stage) {
      case GuestStage.loading:
        return const Column(children: [
          GuestHeader(title: ''),
          Expanded(child: Center(child: CircularProgressIndicator())),
        ]);
      case GuestStage.failed:
        return Column(children: [
          if (info != null) welcomeHeader() else const GuestHeader(title: ''),
          Expanded(
            child: Center(
              child: ErrorState(
                message: state.offline ? "You're offline — we'll retry" : (state.error ?? 'Something went wrong'),
                onRetry: controller.retry,
              ),
            ),
          ),
        ]);
      case GuestStage.ended:
        return EntryFrame(
          wide: wide,
          header: GuestHeader(title: outlet.isEmpty ? 'Thank you' : outlet, subtitle: info == null ? null : 'Table ${info.tableName}'),
          child: EndedView(state: state),
        );
      case GuestStage.welcome:
        if (info != null && !info.seated) {
          return Column(children: [
            welcomeHeader(),
            Expanded(child: NotSeatedView(state: state, wide: wide)),
          ]);
        }
        return EntryFrame(
          wide: wide,
          header: welcomeHeader(),
          child: WelcomeView(state: state, controller: controller),
        );
      case GuestStage.details:
        return EntryFrame(
          wide: wide,
          header: GuestHeader(
            title: 'Join table ${info?.tableName ?? ''}',
            subtitle: outlet,
            onBack: controller.backToWelcome,
          ),
          child: DetailsView(state: state, controller: controller),
        );
      case GuestStage.code:
        return EntryFrame(
          wide: wide,
          header: GuestHeader(
            title: 'Verify',
            subtitle: '+91 ${formatPhone(state.phone)}',
            onBack: controller.backToDetails,
          ),
          child: CodeView(state: state, controller: controller),
        );
      case GuestStage.ordering:
        return switch (layout) {
          GuestLayout.phone => _PhoneOrdering(state: state, controller: controller),
          GuestLayout.tablet => _TabletOrdering(state: state, controller: controller, logo: logo),
          GuestLayout.desktop => _DesktopOrdering(state: state, controller: controller, logo: logo),
        };
    }
  }
}

// --- phone --------------------------------------------------------------------

class _PhoneOrdering extends StatelessWidget {
  const _PhoneOrdering({required this.state, required this.controller});

  final GuestState state;
  final GuestController controller;

  @override
  Widget build(BuildContext context) {
    final info = state.info!;
    final name = state.guest?.name ?? state.name;
    final order = state.order;
    final banner = state.offline ? const OfflineBanner() : null;

    Widget page(Widget header, Widget body) => Column(children: [
          header,
          if (banner != null) banner,
          Expanded(child: body),
        ]);

    switch (state.page) {
      case GuestPage.menu:
        return page(
          GuestHeader(
            title: 'Menu',
            subtitle: 'Table ${info.tableName} · $name',
            onBack: controller.backToWelcome,
            trailing: order?.atTable != null ? HeaderChip('${order!.atTable} at table') : null,
          ),
          _PhoneMenu(state: state, controller: controller),
        );
      case GuestPage.cart:
        return page(
          GuestHeader(
            title: 'Your cart',
            subtitle: '$name · Table ${info.tableName}',
            onBack: () => controller.goTo(GuestPage.menu),
          ),
          _ScrollWithFooter(
            body: CartLines(state: state, controller: controller),
            footer: CartFooter(state: state, controller: controller),
          ),
        );
      case GuestPage.order:
        return page(
          GuestHeader(
            title: 'Table ${info.tableName}',
            subtitleWidget: const LiveIndicator(onDark: true),
            onBack: () => controller.goTo(GuestPage.menu),
            trailing: order == null ? null : HeaderChip(formatRupees(order.totals.grandTotal)),
          ),
          _ScrollWithFooter(
            body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (state.error != null) ...[
                GuestNote(state.error!, tone: GuestNoteTone.error),
                const SizedBox(height: 10),
              ],
              TableOrderRounds(state: state, controller: controller),
            ]),
            footer: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GuestButton(
                kind: GuestButtonKind.green,
                label: 'Add more items',
                onPressed: () => controller.goTo(GuestPage.menu),
              ),
              const SizedBox(height: 9),
              GuestButton(
                icon: Icons.receipt_long_outlined,
                label: 'View bill',
                onPressed: () => controller.goTo(GuestPage.bill),
              ),
            ]),
          ),
        );
      case GuestPage.bill:
        return page(
          GuestHeader(
            title: 'Bill',
            subtitle: 'Table ${info.tableName}',
            onBack: () => controller.goTo(GuestPage.order),
          ),
          _ScrollWithFooter(
            body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (order != null) BillTotals(order: order),
              if (state.error != null) ...[
                const SizedBox(height: 10),
                GuestNote(state.error!, tone: GuestNoteTone.error),
              ],
            ]),
            footer: BillActions(state: state, controller: controller),
          ),
        );
      case GuestPage.billAsked:
        return page(
          GuestHeader(
            title: 'Bill',
            subtitle: 'Table ${info.tableName}',
            onBack: () => controller.goTo(GuestPage.order),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: BillAskedView(state: state, onBack: () => controller.goTo(GuestPage.order)),
          ),
        );
    }
  }
}

/// Scrolling body with a fixed footer, 14 px padding.
class _ScrollWithFooter extends StatelessWidget {
  const _ScrollWithFooter({required this.body, required this.footer});

  final Widget body;
  final Widget footer;

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: body)),
        Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: footer),
      ]);
}

/// Menu browsing state shared by the three layouts: tab and search.
mixin _MenuBrowse<T extends StatefulWidget> on State<T> {
  String? tab;
  String query = '';

  List<GuestProduct> visible(GuestMenu menu) => productsFor(menu, tab ?? defaultTab(menu), query);

  Widget? controlFor(BuildContext context, GuestState state, GuestController controller, GuestProduct p) =>
      ProductControl(
        product: p,
        state: state,
        onAdd: () => addProductFlow(context, controller, p),
        onChange: (d) => controller.changeProduct(p, d),
      );
}

class _PhoneMenu extends StatefulWidget {
  const _PhoneMenu({required this.state, required this.controller});

  final GuestState state;
  final GuestController controller;

  @override
  State<_PhoneMenu> createState() => _PhoneMenuState();
}

class _PhoneMenuState extends State<_PhoneMenu> with _MenuBrowse {
  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final state = widget.state;
    final menu = state.menu ?? const GuestMenu();
    final products = visible(menu);
    final hasCart = state.cart.isNotEmpty;
    final order = state.order;
    final showTableBar = !hasCart && order != null && order.rounds.isNotEmpty;
    return Stack(children: [
      ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 84), children: [
        MenuSearchField(onChanged: (q) => setState(() => query = q)),
        const SizedBox(height: 12),
        CategoryTabs(menu: menu, selected: tab ?? defaultTab(menu), onSelect: (id) => setState(() => tab = id)),
        if (menu.happyHour != null) ...[
          const SizedBox(height: 12),
          HappyHourBanner(menu.happyHour!),
        ],
        const SizedBox(height: 12),
        if (products.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Nothing matches', textAlign: TextAlign.center, style: p.body(13, color: p.ink2)),
          )
        else
          GuestCard(
            child: Column(children: [
              for (var i = 0; i < products.length; i++)
                MenuRow(
                  product: products[i],
                  last: i == products.length - 1,
                  control: controlFor(context, state, widget.controller, products[i]),
                ),
            ]),
          ),
      ]),
      if (hasCart || showTableBar)
        Positioned(
          left: 10,
          right: 10,
          bottom: 12,
          child: _CartBar(
            key: const Key('guest-cart-bar'),
            label: hasCart
                ? '${state.cartCount} ${state.cartCount == 1 ? 'item' : 'items'} · ${formatRupees(state.cartTotal)}'
                : 'Table order · ${formatRupees(order!.totals.grandTotal)}',
            action: hasCart ? 'View cart ›' : 'View ›',
            green: !hasCart,
            onTap: () => widget.controller.goTo(hasCart ? GuestPage.cart : GuestPage.order),
          ),
        ),
    ]);
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({super.key, required this.label, required this.action, required this.onTap, this.green = false});

  final String label;
  final String action;
  final VoidCallback onTap;
  final bool green;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final bg = green ? p.header : p.accent;
    final fg = green ? p.onHeader : p.onAccent;
    return Material(
      color: bg,
      elevation: 6,
      shadowColor: bg.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: [
            Expanded(child: Text(label, style: p.body(13, weight: FontWeight.w600, color: fg))),
            Text(action, style: p.body(13, weight: FontWeight.w600, color: fg)),
          ]),
        ),
      ),
    );
  }
}

// --- tablet and desktop -----------------------------------------------------

/// Header button on the wide header ("Call a waiter", "View bill").
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: p.onHeader.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: p.onHeader),
            const SizedBox(width: 7),
            Text(label, style: p.body(12.5, weight: FontWeight.w600, color: p.onHeader)),
          ]),
        ),
      ),
    );
  }
}

class _WideHeader extends StatelessWidget {
  const _WideHeader({
    required this.state,
    required this.controller,
    required this.logo,
    required this.desktop,
    required this.onBill,
  });

  final GuestState state;
  final GuestController controller;
  final String logo;
  final bool desktop;
  final VoidCallback onBill;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final info = state.info!;
    final name = state.guest?.name ?? state.name;
    final atTable = state.order?.atTable;
    final sub = desktop
        ? [info.tableLine, if (atTable != null) '$atTable at table'].join(' · ')
        : 'Table ${info.tableName} · $name';
    return Material(
      color: p.header,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: desktop ? 60 : 56,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: desktop ? 20 : 16),
            child: Row(children: [
              GuestLogo(initials: logo.isEmpty ? 'P&B' : logo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(info.outletName, style: p.display(19, color: p.onHeader)),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: p.body(12, color: p.onHeader.withValues(alpha: 0.85))),
                ]),
              ),
              _HeaderButton(
                icon: Icons.notifications_none,
                label: desktop ? 'Call a waiter' : 'Waiter',
                onTap: controller.callWaiter,
              ),
              _HeaderButton(icon: Icons.receipt_long_outlined, label: desktop ? 'View bill' : 'Bill', onTap: onBill),
              if (desktop) ...[
                const SizedBox(width: 12),
                GuestAvatar(name),
                const SizedBox(width: 7),
                Text(name, style: p.body(12.5, color: p.onHeader)),
                const SizedBox(width: 12),
                const HeaderChip('EN'),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Right panel (desktop) and side drawer (tablet): Your cart / Table order.
class _SidePanel extends StatefulWidget {
  const _SidePanel({required this.state, required this.controller});

  final GuestState state;
  final GuestController controller;

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> {
  late final _note = TextEditingController(text: widget.state.note);

  @override
  void didUpdateWidget(_SidePanel old) {
    super.didUpdateWidget(old);
    if (widget.state.note.isEmpty && _note.text.isNotEmpty) _note.clear();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final state = widget.state;
    final controller = widget.controller;
    final tableTab = state.page != GuestPage.menu && state.page != GuestPage.cart;
    final order = state.order;

    Widget tab(String label, bool on, VoidCallback onTap, {Widget? extra}) => Expanded(
          child: Semantics(
            selected: on,
            button: true,
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: on ? p.accent : Colors.transparent, width: 2)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(label, style: p.body(13, weight: FontWeight.w600, color: on ? p.accent : p.muted)),
                  if (extra != null) ...[const SizedBox(width: 6), extra],
                ]),
              ),
            ),
          ),
        );

    final cartLabel = state.cartCount > 0 ? 'Your cart · ${state.cartCount}' : 'Your cart';
    return Container(
      key: const Key('guest-side-panel'),
      color: p.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line))),
          child: Row(children: [
            tab(cartLabel, !tableTab, () => controller.goTo(GuestPage.cart)),
            tab('Table order', tableTab, () => controller.goTo(GuestPage.order),
                extra: const LiveIndicator(label: null)),
          ]),
        ),
        if (state.offline) const OfflineBanner(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: tableTab
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TableOrderRounds(state: state, controller: controller, compact: true),
                    if (order != null && order.rounds.isNotEmpty) BillTotals(order: order),
                  ])
                : CartLines(state: state, controller: controller, noteController: _note),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
          child: tableTab
              ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  AmountRow(
                    label: 'Table total',
                    amount: formatRupees(order?.totals.grandTotal ?? 0),
                    strong: true,
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: 9),
                    GuestNote(state.error!, tone: GuestNoteTone.error),
                  ],
                  const SizedBox(height: 9),
                  BillActions(state: state, controller: controller),
                ])
              : CartFooter(state: state, controller: controller, showTaxRow: false),
        ),
      ]),
    );
  }
}

class _TabletOrdering extends StatefulWidget {
  const _TabletOrdering({required this.state, required this.controller, required this.logo});

  final GuestState state;
  final GuestController controller;
  final String logo;

  @override
  State<_TabletOrdering> createState() => _TabletOrderingState();
}

class _TabletOrderingState extends State<_TabletOrdering> with _MenuBrowse {
  final _scaffold = GlobalKey<ScaffoldState>();

  void _open(GuestPage page) {
    widget.controller.goTo(page);
    _scaffold.currentState?.openEndDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final state = widget.state;
    final menu = state.menu ?? const GuestMenu();
    final products = visible(menu);
    return LayoutBuilder(builder: (context, c) {
      return Scaffold(
        key: _scaffold,
        backgroundColor: p.canvas,
        endDrawer: Drawer(
          width: c.maxWidth * 0.62,
          backgroundColor: p.card,
          shape: const RoundedRectangleBorder(),
          child: SafeArea(child: _SidePanel(state: state, controller: widget.controller)),
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('guest-cart-fab'),
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          onPressed: () => _open(state.cart.isEmpty && (state.order?.rounds.isNotEmpty ?? false)
              ? GuestPage.order
              : GuestPage.cart),
          icon: const Icon(Icons.shopping_bag_outlined),
          label: Text(state.cartCount > 0
              ? 'Cart · ${state.cartCount} · ${formatRupees(state.cartTotal)}'
              : 'Cart'),
        ),
        body: Column(children: [
          _WideHeader(
            state: state,
            controller: widget.controller,
            logo: widget.logo,
            desktop: false,
            onBill: () => _open(GuestPage.order),
          ),
          if (state.offline) const OfflineBanner(),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 88), children: [
              CategoryTabs(menu: menu, selected: tab ?? defaultTab(menu), onSelect: (id) => setState(() => tab = id)),
              const SizedBox(height: 12),
              MenuSearchField(onChanged: (q) => setState(() => query = q)),
              if (menu.happyHour != null) ...[
                const SizedBox(height: 12),
                HappyHourBanner(menu.happyHour!),
              ],
              const SizedBox(height: 14),
              MenuGrid(
                columns: 2,
                products: products,
                controlFor: (prod) => controlFor(context, state, widget.controller, prod),
              ),
            ]),
          ),
        ]),
      );
    });
  }
}

class _DesktopOrdering extends StatefulWidget {
  const _DesktopOrdering({required this.state, required this.controller, required this.logo});

  final GuestState state;
  final GuestController controller;
  final String logo;

  @override
  State<_DesktopOrdering> createState() => _DesktopOrderingState();
}

class _DesktopOrderingState extends State<_DesktopOrdering> with _MenuBrowse {
  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final state = widget.state;
    final menu = state.menu ?? const GuestMenu();
    final products = visible(menu);
    final selected = tab ?? defaultTab(menu);
    return Column(children: [
      _WideHeader(
        state: state,
        controller: widget.controller,
        logo: widget.logo,
        desktop: true,
        onBill: () => widget.controller.goTo(GuestPage.order),
      ),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 190,
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border(right: BorderSide(color: p.line))),
              child: CategoryRail(menu: menu, selected: selected, onSelect: (id) => setState(() => tab = id)),
            ),
          ),
          Expanded(
            key: const Key('guest-menu-column'),
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), children: [
              Row(children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: MenuSearchField(onChanged: (q) => setState(() => query = q)),
                  ),
                ),
                if (menu.happyHour != null) ...[
                  const SizedBox(width: 12),
                  HappyHourBanner(menu.happyHour!),
                ],
              ]),
              const SizedBox(height: 14),
              MenuGrid(
                products: products,
                controlFor: (prod) => controlFor(context, state, widget.controller, prod),
              ),
            ]),
          ),
          SizedBox(
            width: 320,
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border(left: BorderSide(color: p.line))),
              child: _SidePanel(state: state, controller: widget.controller),
            ),
          ),
        ]),
      ),
    ]);
  }
}
