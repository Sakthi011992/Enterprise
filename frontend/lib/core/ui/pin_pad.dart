import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'ui_style.dart';

/// Numeric keypad for PIN entry: a 3 by 4 grid of 52 px keys (1-9, empty, 0,
/// backspace), a row of dots for the digits entered, and hardware keyboard
/// support. When the length is reached it calls [onCompleted] and clears.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.length,
    required this.onCompleted,
    this.errorText,
    this.enabled = true,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final String? errorText;
  final bool enabled;

  @override
  State<PinPad> createState() => _PinPadState();
}

const double _keySize = 52;
const String _digitChars = '0123456789';

class _PinPadState extends State<PinPad> {
  String _entered = '';

  void _addDigit(String digit) {
    if (!widget.enabled || _entered.length >= widget.length) return;
    setState(() => _entered += digit);
    if (_entered.length == widget.length) {
      final pin = _entered;
      widget.onCompleted(pin);
      setState(() => _entered = '');
    }
  }

  void _backspace() {
    if (!widget.enabled || _entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    final ch = event.character;
    if (ch != null && ch.length == 1 && _digitChars.contains(ch)) {
      _addDigit(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final err = widget.errorText;
    final opacity = widget.enabled ? 1.0 : 0.5;

    Widget keyRow(List<Widget> keys) => Padding(
          padding: EdgeInsets.symmetric(vertical: t.spacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final key in keys)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.spacing.xs),
                  child: key,
                ),
            ],
          ),
        );

    Widget digitKey(String digit) => _PinKey(
          semanticsLabel: digit,
          onTap: widget.enabled ? () => _addDigit(digit) : null,
          child: Text(digit, style: kitTextStyle(t, t.typography.title, t.color.content.primary)),
        );

    final backspace = _PinKey(
      semanticsLabel: 'Delete digit',
      onTap: widget.enabled ? _backspace : null,
      child: Icon(Icons.backspace_outlined, color: t.color.content.primary),
    );

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Opacity(
        opacity: opacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dots(length: widget.length, filled: _entered.length),
            if (err != null && err.isNotEmpty) ...[
              SizedBox(height: t.spacing.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 16, color: t.color.content.danger),
                  SizedBox(width: t.spacing.xs),
                  Flexible(
                    child: Text(
                      err,
                      textAlign: TextAlign.center,
                      style: kitTextStyle(t, t.typography.caption, t.color.content.danger),
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(height: t.spacing.md),
            keyRow([digitKey('1'), digitKey('2'), digitKey('3')]),
            keyRow([digitKey('4'), digitKey('5'), digitKey('6')]),
            keyRow([digitKey('7'), digitKey('8'), digitKey('9')]),
            keyRow([const SizedBox(width: _keySize, height: _keySize), digitKey('0'), backspace]),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.length, required this.filled});

  final int length;
  final int filled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: '$filled of $length digits entered',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < length; i++)
            Container(
              margin: EdgeInsets.symmetric(horizontal: t.spacing.xs),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? t.color.background.accent : null,
                border: Border.all(
                  color: i < filled ? t.color.background.accent : t.color.border.strong,
                  width: t.borderWidth.thick,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({required this.child, required this.onTap, required this.semanticsLabel});

  final Widget child;
  final VoidCallback? onTap;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticsLabel,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(t.radius.md),
          child: Container(
            width: _keySize,
            height: _keySize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.radius.md),
              border: Border.all(color: t.color.border.standard, width: t.borderWidth.hairline),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
