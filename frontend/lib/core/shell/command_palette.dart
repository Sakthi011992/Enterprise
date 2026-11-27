import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../ui/ui.dart';
import 'nav_registry.dart';

/// Opens the jump-to dialog with the pages the user may see.
Future<void> showCommandPalette(BuildContext context, List<NavItem> items) {
  return showDialog<void>(
    context: context,
    builder: (_) => CommandPalette(items: items),
  );
}

/// Type to filter pages, Enter opens the highlighted one, arrows move the
/// highlight when the key reaches this widget.
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.items});

  final List<NavItem> items;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<NavItem> get _matches {
    final q = _controller.text.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return widget.items
        .where((i) =>
            i.label.toLowerCase().contains(q) ||
            i.group.toLowerCase().contains(q))
        .toList();
  }

  void _open(NavItem item) {
    Navigator.of(context).pop();
    context.go(item.route);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final count = _matches.length;
    if (count == 0) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _index = (_index + 1) % count);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _index = (_index - 1 + count) % count);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final matches = _matches;
    final highlighted =
        matches.isEmpty ? 0 : _index.clamp(0, matches.length - 1);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.color.background.raised,
            borderRadius: BorderRadius.circular(t.radius.lg),
            border: Border.all(color: t.color.border.standard),
            boxShadow: context.ext.raisedShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(t.radius.lg),
            child: Material(
              color: Colors.transparent,
              child: Focus(
                onKeyEvent: _onKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(t.spacing.md),
                      child: AppTextField(
                        label: 'Search or jump to',
                        hint: 'Type a page name',
                        controller: _controller,
                        autofocus: true,
                        onChanged: (_) => setState(() => _index = 0),
                        onSubmitted: (_) {
                          if (matches.isNotEmpty) _open(matches[highlighted]);
                        },
                      ),
                    ),
                    Flexible(
                      child: matches.isEmpty
                          ? Padding(
                              padding: EdgeInsets.all(t.spacing.lg),
                              child: EmptyState(title: 'No matching pages'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: matches.length,
                              itemBuilder: (context, i) {
                                final item = matches[i];
                                return ListTile(
                                  selected: i == highlighted,
                                  selectedTileColor: context.ext.selectedRow,
                                  selectedColor: t.color.background.accent,
                                  leading: Icon(item.icon),
                                  title: Text(item.label),
                                  subtitle: Text(item.group),
                                  onTap: () => _open(item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
