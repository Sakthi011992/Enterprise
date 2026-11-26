import 'package:flutter/material.dart';

import '../../../core/theme/theme_tokens.dart';
import '../../../core/ui/ui.dart';
import '../../pos/presentation/pos_format.dart';
import '../data/guest_models.dart';

/// Colours of the guest design, all taken from the active theme tokens.
class GuestPalette {
  GuestPalette(BuildContext context)
      : t = context.tokens,
        ext = context.ext;

  final ThemeTokens t;
  final ExtTokens ext;

  Color get header => t.color.background.header;
  Color get onHeader => t.color.content.onHeader;
  Color get canvas => t.color.background.canvas;
  Color get card => t.color.background.surface;
  Color get accent => t.color.background.accent;
  Color get onAccent => t.color.content.onAccent;
  Color get ink => t.color.content.primary;
  Color get ink2 => t.color.content.secondary;
  Color get muted => t.color.content.muted;
  Color get line => t.color.border.standard;
  Color get line2 => t.color.border.subtle;
  Color get accentSoft => ext.accentSubtle;
  Color get onAccentSoft => ext.onAccentSubtle;

  /// Drink thumbnails: a soft tint of the header green.
  Color get drinkSoft => Color.lerp(card, header, 0.12)!;

  /// Header chips and buttons: the header text at low opacity.
  Color get onHeaderFaint => onHeader.withValues(alpha: 0.14);

  TextStyle display(double size, {Color? color}) => AppFonts.apply(
        t.typography.displayFamily,
        TextStyle(fontSize: size, height: 1.15, color: color ?? ink, fontWeight: FontWeight.w400),
      );

  TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color? color, double? height}) =>
      AppFonts.apply(
        t.typography.bodyFamily,
        TextStyle(fontSize: size, fontWeight: weight, color: color ?? ink, height: height),
      );

  TextStyle mono(double size, {Color? color, FontWeight weight = FontWeight.w500}) => AppFonts.apply(
        t.typography.monoFamily,
        TextStyle(fontSize: size, fontWeight: weight, color: color ?? ink, fontFeatures: kTabularFigures),
      );
}

/// Green header bar: logo or back button, title and subtitle, a trailing chip.
class GuestHeader extends StatelessWidget {
  const GuestHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.onBack,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Material(
      color: p.header,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Row(
            children: [
              if (onBack != null)
                Semantics(
                  button: true,
                  label: 'Back',
                  child: InkWell(
                    onTap: onBack,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: p.onHeader.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.chevron_left, color: p.onHeader, size: 20),
                    ),
                  ),
                )
              else
                const GuestLogo(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: p.display(17, color: p.onHeader)),
                    if (subtitleWidget != null)
                      subtitleWidget!
                    else if (subtitle != null)
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: p.body(11, color: p.onHeader.withValues(alpha: 0.85))),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// "P&B" monogram tile.
class GuestLogo extends StatelessWidget {
  const GuestLogo({super.key, this.initials = 'P&B'});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.onHeader, borderRadius: BorderRadius.circular(9)),
      child: Text(initials, style: p.display(14, color: p.header)),
    );
  }
}

/// Initials of an outlet name: "Pegs & Bottles" -> "P&B".
String outletInitials(String name) {
  final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  return words.map((w) => w == '&' ? '&' : w[0].toUpperCase()).take(3).join();
}

/// Small pill on the header ("EN", "3 at table", "₹1,780").
class HeaderChip extends StatelessWidget {
  const HeaderChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: p.onHeaderFaint, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: p.body(11, weight: FontWeight.w600, color: p.onHeader)),
    );
  }
}

enum GuestButtonKind { primary, outline, green, off }

/// Full-width 52 px button in the guest style.
class GuestButton extends StatelessWidget {
  const GuestButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = GuestButtonKind.outline,
    this.icon,
    this.trailing,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final GuestButtonKind kind;
  final IconData? icon;
  final Widget? trailing;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final height = context.ext.controlLg;
    final (bg, fg, border) = switch (kind) {
      GuestButtonKind.primary => (p.accent, p.onAccent, p.accent),
      GuestButtonKind.green => (p.header, p.onHeader, p.header),
      GuestButtonKind.off => (p.ext.neutralSubtle, p.muted, p.ext.neutralSubtle),
      GuestButtonKind.outline => (p.card, p.ink, p.line),
    };
    final enabled = kind != GuestButtonKind.off && onPressed != null && !loading;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (icon != null)
          Icon(icon, size: 18, color: fg),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: p.body(14, weight: FontWeight.w600, color: fg)),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// "COMING SOON" pill.
class SoonPill extends StatelessWidget {
  const SoonPill({super.key});

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(999)),
      child: Text('COMING SOON',
          style: p.body(9.5, weight: FontWeight.w700, color: p.ink2).copyWith(letterSpacing: 0.3)),
    );
  }
}

/// Rounded white card with the hairline border.
class GuestCard extends StatelessWidget {
  const GuestCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

enum GuestNoteTone { warn, info, error }

/// Coloured message box (warning note, info, error).
class GuestNote extends StatelessWidget {
  const GuestNote(this.message, {super.key, this.tone = GuestNoteTone.warn, this.title, this.center = false});

  final String message;
  final String? title;
  final GuestNoteTone tone;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final (bg, fg) = switch (tone) {
      GuestNoteTone.warn => (p.ext.warningSubtle, p.ext.onWarningSubtle),
      GuestNoteTone.info => (p.ext.infoSubtle, p.ext.onInfoSubtle),
      GuestNoteTone.error => (p.ext.dangerSubtle, p.ext.onDangerSubtle),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          if (title != null) Text(title!, style: p.body(12, weight: FontWeight.w700, color: fg)),
          Text(message,
              textAlign: center ? TextAlign.center : TextAlign.start,
              style: p.body(12, color: fg)),
        ],
      ),
    );
  }
}

/// Green "Happy hour 30% off cocktails until 8 pm" strip.
class HappyHourBanner extends StatelessWidget {
  const HappyHourBanner(this.happyHour, {super.key});

  final GuestHappyHour happyHour;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(color: p.header, borderRadius: BorderRadius.circular(10)),
      child: Text.rich(
        TextSpan(style: p.body(12, color: p.onHeader), children: [
          const TextSpan(text: 'Happy hour '),
          TextSpan(
              text: happyHour.label,
              style: p.body(12, weight: FontWeight.w700, color: p.ext.brassSubtle)),
          if (happyHour.until != null) TextSpan(text: ' until ${happyHour.until}'),
        ]),
      ),
    );
  }
}

/// Price with the pre-happy-hour price struck through.
class GuestPrice extends StatelessWidget {
  const GuestPrice({super.key, required this.price, this.basePrice, this.size = 12.5});

  final double price;
  final double? basePrice;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final struck = basePrice != null && basePrice! > price;
    return Text.rich(TextSpan(children: [
      if (struck)
        TextSpan(
          text: '${formatRupees(basePrice!)} ',
          style: p.mono(size - 1.5, color: p.muted).copyWith(decoration: TextDecoration.lineThrough),
        ),
      TextSpan(text: formatRupees(price), style: p.mono(size)),
    ]));
  }
}

/// Round "+" outline button.
class AddButton extends StatelessWidget {
  const AddButton({super.key, required this.onTap, required this.label});

  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: p.accent, width: 1.5),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(Icons.add, size: 20, color: p.accent),
        ),
      ),
    );
  }
}

/// − n + stepper on the accent tint.
class GuestStepper extends StatelessWidget {
  const GuestStepper({super.key, required this.value, this.onMinus, this.onPlus, this.name = ''});

  final int value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final String name;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    Widget btn(IconData icon, VoidCallback? onTap, String label) => Semantics(
          button: true,
          label: label,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(7),
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(7)),
              child: Icon(icon, size: 16, color: p.onAccent),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(9)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove, onMinus, 'Remove one $name'),
        SizedBox(
          width: 26,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: p.body(13, weight: FontWeight.w700, color: p.onAccentSoft)),
        ),
        btn(Icons.add, onPlus, 'Add one more $name'),
      ]),
    );
  }
}

/// "Sold out" tag.
class SoldOutTag extends StatelessWidget {
  const SoldOutTag({super.key});

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: p.ext.neutralSubtle, borderRadius: BorderRadius.circular(999)),
      child: Text('SOLD OUT', style: p.body(9.5, weight: FontWeight.w700, color: p.muted)),
    );
  }
}

/// Letter tile for a product without an image.
class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, required this.product, this.size = 44, this.radius = 10});

  final GuestProduct product;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final drink = isDrink(product);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: drink ? p.drinkSoft : p.accentSoft,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(product.name.isEmpty ? '' : product.name[0].toUpperCase(),
          style: p.display(size * 0.38, color: drink ? p.header : p.accent)),
    );
  }
}

/// Drinks get the green thumbnail; food gets the red one.
bool isDrink(GuestProduct p) {
  if (p.isAlcohol) return true;
  final c = p.categoryId.toLowerCase();
  return const ['cocktail', 'beer', 'wine', 'whisky', 'drink', 'mocktail', 'spirit', 'beverage']
      .any(c.contains);
}

/// Wording and colours of a line state (design "Item states guests see").
String lineStateLabel(GuestLineState s, {bool short = false}) => switch (s) {
      GuestLineState.waitingWaiter => short ? 'Waiting' : 'Waiting for waiter',
      GuestLineState.sent => 'Sent to kitchen',
      GuestLineState.cooking => 'Cooking',
      GuestLineState.ready => short ? 'Ready' : 'Ready to serve',
      GuestLineState.served => 'Served',
      GuestLineState.cancelled => 'Cancelled',
    };

class LineStateChip extends StatelessWidget {
  const LineStateChip(this.state, {super.key, this.short = false});

  final GuestLineState state;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final ext = p.ext;
    final (bg, fg) = switch (state) {
      GuestLineState.waitingWaiter => (ext.warningSubtle, ext.onWarningSubtle),
      GuestLineState.sent => (ext.infoSubtle, ext.onInfoSubtle),
      GuestLineState.cooking => (ext.brassSubtle, ext.onBrassSubtle),
      GuestLineState.ready => (p.header, ext.brassSubtle),
      GuestLineState.served => (ext.successSubtle, ext.onSuccessSubtle),
      GuestLineState.cancelled => (ext.neutralSubtle, p.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(lineStateLabel(state, short: short),
            style: p.body(10, weight: FontWeight.w700, color: fg)),
      ]),
    );
  }
}

/// Green "Live" dot and word.
class LiveIndicator extends StatelessWidget {
  const LiveIndicator({super.key, this.label = 'Live', this.onDark = false});

  final String? label;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: p.ext.statusGreen,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: p.ext.statusGreen.withValues(alpha: 0.2), spreadRadius: 3)],
      ),
    );
    if (label == null) return Semantics(label: 'Live', child: dot);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      dot,
      const SizedBox(width: 6),
      Text(label!,
          style: p.body(10.5,
              weight: FontWeight.w600, color: onDark ? p.ext.statusGreen : p.ext.onSuccessSubtle)),
    ]);
  }
}

/// Round avatar with the first letter of a name.
class GuestAvatar extends StatelessWidget {
  const GuestAvatar(this.name, {super.key, this.alt = false, this.size = 24});

  final String name;
  final bool alt;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: alt ? p.ext.onBrassSubtle : p.header,
        shape: BoxShape.circle,
      ),
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
          style: p.body(size * 0.45, weight: FontWeight.w700, color: p.onHeader)),
    );
  }
}

/// "1 min ago", "just now".
String agoText(DateTime? at, {DateTime? now, bool suffix = true}) {
  if (at == null) return '';
  final mins = (now ?? DateTime.now()).difference(at).inMinutes;
  if (mins < 1) return 'just now';
  final text = mins < 60 ? '$mins min' : '${mins ~/ 60} h';
  return suffix ? '$text ago' : text;
}

/// Row of a label and an amount.
class AmountRow extends StatelessWidget {
  const AmountRow({super.key, required this.label, required this.amount, this.strong = false});

  final String label;
  final String amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = GuestPalette(context);
    return Row(children: [
      Expanded(
        child: Text(label,
            style: strong ? p.body(13, weight: FontWeight.w700) : p.body(12.5, color: p.ink2)),
      ),
      Text(amount, style: strong ? p.mono(20) : p.mono(12.5)),
    ]);
  }
}

/// Offline strip shown above the content.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) =>
      const AppBanner(message: "You're offline — we'll retry", tone: StatusTone.warning);
}
